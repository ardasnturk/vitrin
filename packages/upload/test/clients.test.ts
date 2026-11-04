import { generateKeyPairSync } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import { AscApiError, AscClient, AscNetworkError, backoffMs, errorsFromBody, parseRetryAfterMs, performUploadOperations, retryDelayMs, retryPolicy } from '../src/index.js';

// ---- retry policy (pure) ------------------------------------------------------------------------------------------

describe('retry policy', () => {
  const now = Date.UTC(2026, 10, 3, 12, 0, 0);

  it('reads Retry-After as seconds or as an HTTP-date, never as NaN', () => {
    expect(parseRetryAfterMs('3', now)).toBe(3000);
    expect(parseRetryAfterMs(' 0 ', now)).toBe(0);
    expect(parseRetryAfterMs(new Date(now + 10_000).toUTCString(), now)).toBe(10_000);
    expect(parseRetryAfterMs(new Date(now - 10_000).toUTCString(), now)).toBe(0);
    for (const bad of ['soon', '', null, undefined, 'Wed, 99 Foo 2026']) expect(parseRetryAfterMs(bad, now)).toBeUndefined();
  });

  it('backs off exponentially under a per-wait cap and a total-wait cap', () => {
    const policy = retryPolicy({ baseDelayMs: 1000, maxDelayMs: 5000, maxAttempts: 10, maxTotalWaitMs: 9000, now: () => now });
    expect([1, 2, 3, 4].map((a) => backoffMs(a, policy))).toEqual([1000, 2000, 4000, 5000]);
    expect(retryDelayMs({ attempt: 1, waitedMs: 0 }, policy)).toBe(1000);
    expect(retryDelayMs({ attempt: 3, waitedMs: 3000 }, policy)).toBe(4000);
    // 3000 + 4000 waited; the fourth wait (5000) would pass the 9000 budget.
    expect(retryDelayMs({ attempt: 4, waitedMs: 7000 }, policy)).toBeUndefined();
    // Retry-After wins over backoff while it fits; a header past the budget stops the retries at once.
    expect(retryDelayMs({ attempt: 1, waitedMs: 0, retryAfter: '7' }, policy)).toBe(7000);
    expect(retryDelayMs({ attempt: 1, waitedMs: 0, retryAfter: '600' }, policy)).toBeUndefined();
    expect(retryDelayMs({ attempt: 1, waitedMs: 0, retryAfter: 'garbage' }, policy)).toBe(1000);
    expect(retryDelayMs({ attempt: 10, waitedMs: 0 }, policy)).toBeUndefined();
  });

  it('turns any error body into an errors list that keeps the first 300 characters', () => {
    expect(errorsFromBody('{"errors":[{"code":"NOT_FOUND","detail":"gone"}]}')).toEqual([{ code: 'NOT_FOUND', detail: 'gone' }]);
    expect(errorsFromBody('<html><body>502 Bad Gateway</body></html>')).toEqual([{ detail: '<html><body>502 Bad Gateway</body></html>' }]);
    expect(errorsFromBody('{"message":"no errors key"}')).toEqual([{ detail: '{"message":"no errors key"}' }]);
    expect(errorsFromBody('')).toEqual([{ detail: '(empty body)' }]);
    expect(errorsFromBody('x'.repeat(1000))[0]!.detail).toHaveLength(300);
  });
});

// ---- AscClient -------------------------------------------------------------------------------------------------------

const { privateKey } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
const creds = { keyId: 'KEY1234567', issuerId: '69a6de7e-0000-0000-0000-000000000000', privateKey: privateKey.export({ type: 'pkcs8', format: 'pem' }).toString() };

type Step = Response | Error | (() => Response | Error);

/** A fetch that answers one scripted step per call (the last step repeats) and records every sleep instead of waiting. */
function scripted(steps: Step[], retry: Record<string, unknown> = {}) {
  const calls: Array<{ method: string; url: string }> = [];
  const sleeps: number[] = [];
  const fetchImpl = (async (url: string, init?: RequestInit) => {
    calls.push({ method: init?.method ?? 'GET', url: String(url) });
    const step = steps[Math.min(calls.length, steps.length) - 1]!;
    const out = typeof step === 'function' ? step() : step;
    if (out instanceof Error) throw out;
    return out.clone(); // a step may answer several calls; a Response body can be read only once
  }) as typeof fetch;
  const sleep = async (ms: number) => {
    sleeps.push(ms);
  };
  const client = new AscClient(creds, fetchImpl, { retry: { sleep, baseDelayMs: 1000, maxDelayMs: 30_000, maxTotalWaitMs: 60_000, ...retry } });
  return { client, calls, sleeps, fetchImpl, sleep };
}

const json = (body: unknown, status = 200, headers: Record<string, string> = {}) => new Response(JSON.stringify(body), { status, headers });
const html = (status: number, headers: Record<string, string> = {}) => new Response(`<html><body>${status} from the gateway</body></html>`, { status, headers: { 'content-type': 'text/html', ...headers } });
const network = () => new TypeError('fetch failed');

describe('AscClient retries', () => {
  it('waits the Retry-After seconds of a 429, then succeeds', async () => {
    const { client, calls, sleeps } = scripted([json({ errors: [{ code: 'RATE_LIMIT' }] }, 429, { 'retry-after': '7' }), json({ data: [] })]);
    expect(await client.get('/v1/apps')).toEqual({ data: [] });
    expect(calls).toHaveLength(2);
    expect(sleeps).toEqual([7000]);
  });

  it('waits until a Retry-After HTTP-date, measured against the injected clock', async () => {
    const now = Date.UTC(2026, 10, 3, 12, 0, 0);
    const { client, sleeps } = scripted([json({}, 429, { 'retry-after': new Date(now + 12_000).toUTCString() }), json({ data: [] })], { now: () => now });
    await client.get('/v1/apps');
    expect(sleeps).toEqual([12_000]);
  });

  it('falls back to backoff for a Retry-After it cannot read, so the attempts are never burnt at once', async () => {
    const { client, sleeps } = scripted([json({}, 429, { 'retry-after': 'soon' }), json({}, 429, { 'retry-after': 'soon' }), json({ data: [] })]);
    await client.get('/v1/apps');
    expect(sleeps).toEqual([1000, 2000]);
    expect(sleeps.every((ms) => Number.isFinite(ms) && ms > 0)).toBe(true);
  });

  it('retries 5xx and dropped connections with backoff', async () => {
    const { client, calls, sleeps } = scripted([html(503), network(), json({}, 500), json({ data: { type: 'apps', id: '1', attributes: {} } })]);
    const doc = await client.get('/v1/apps/1');
    expect((doc.data as { id: string }).id).toBe('1');
    expect(calls).toHaveLength(4);
    expect(sleeps).toEqual([1000, 2000, 4000]);
  });

  it('gives up after maxAttempts with the last status, path and the non-JSON body', async () => {
    const { client, calls } = scripted([html(502)], { maxAttempts: 3 });
    const err = await client.get('/v1/apps').catch((e: unknown) => e);
    expect(err).toBeInstanceOf(AscApiError);
    expect(err as AscApiError).toMatchObject({ status: 502, path: '/v1/apps' });
    expect((err as Error).message).toContain('ASC API 502 /v1/apps: <html><body>502 from the gateway');
    expect(calls).toHaveLength(3);
  });

  it('reports a request that never got a response, with its cause', async () => {
    const { client, calls } = scripted([network()], { maxAttempts: 2 });
    const err = await client.get('/v1/apps').catch((e: unknown) => e);
    expect(err).toBeInstanceOf(AscNetworkError);
    expect((err as Error).message).toContain('no response after 2 attempt(s): fetch failed');
    expect((err as Error).cause).toBeInstanceOf(TypeError);
    expect(calls).toHaveLength(2);
  });

  it('does not sleep when Retry-After is past the total-wait cap, and never retries other 4xx', async () => {
    const capped = scripted([json({}, 429, { 'retry-after': '3600' }), json({ data: [] })]);
    await expect(capped.client.get('/v1/apps')).rejects.toMatchObject({ status: 429 });
    expect(capped.sleeps).toEqual([]);
    expect(capped.calls).toHaveLength(1);
    const forbidden = scripted([html(403), json({ data: [] })]);
    const err = await forbidden.client.get('/v1/apps').catch((e: unknown) => e as AscApiError);
    expect(err).toMatchObject({ status: 403, path: '/v1/apps', errors: [{ detail: '<html><body>403 from the gateway</body></html>' }] });
    expect(forbidden.calls).toHaveLength(1);
  });

  it('treats a 404 on a repeated DELETE as done', async () => {
    const { client, calls } = scripted([html(503), json({ errors: [{ code: 'NOT_FOUND' }] }, 404)]);
    await expect(client.request('DELETE', '/v1/appScreenshots/x')).resolves.toBeUndefined();
    expect(calls.map((c) => c.method)).toEqual(['DELETE', 'DELETE']);
    const fresh = scripted([json({ errors: [{ code: 'NOT_FOUND' }] }, 404)]);
    await expect(fresh.client.request('DELETE', '/v1/appScreenshots/x')).rejects.toMatchObject({ status: 404 });
  });

  it('reports a 2xx that is not JSON instead of throwing a SyntaxError', async () => {
    const { client } = scripted([new Response('<html>maintenance</html>', { status: 200 })]);
    const err = await client.get('/v1/apps').catch((e: unknown) => e);
    expect(err).toBeInstanceOf(AscApiError);
    expect((err as Error).message).toContain('response is not JSON: <html>maintenance</html>');
  });
});

describe('AscClient.getAll', () => {
  const page = (ids: string[], next?: string) => json({ data: ids.map((id) => ({ type: 't', id, attributes: {} })), ...(next ? { links: { next } } : {}) });

  it('follows links.next and concatenates the pages', async () => {
    const { client, calls } = scripted([page(['a', 'b'], 'https://api.appstoreconnect.apple.com/v1/x?cursor=2'), page(['c'], 'https://api.appstoreconnect.apple.com/v1/x?cursor=3'), page(['d'])]);
    expect((await client.getAll('/v1/x')).map((r) => r.id)).toEqual(['a', 'b', 'c', 'd']);
    expect(calls.map((c) => c.url)).toEqual(['https://api.appstoreconnect.apple.com/v1/x', 'https://api.appstoreconnect.apple.com/v1/x?cursor=2', 'https://api.appstoreconnect.apple.com/v1/x?cursor=3']);
  });

  it('refuses a list longer than the page limit instead of returning a prefix', async () => {
    const { client, calls } = scripted([page(['a'], 'https://api.appstoreconnect.apple.com/v1/x?more')]);
    await expect(client.getAll('/v1/x', 3)).rejects.toThrow(/more than 3 pages/);
    expect(calls).toHaveLength(3);
  });
});

// ---- performUploadOperations ------------------------------------------------------------------------------------------

describe('performUploadOperations', () => {
  const ops = [
    { method: 'PUT', url: 'https://u/1', offset: 0, length: 3, requestHeaders: [{ name: 'Content-Type', value: 'image/png' }] },
    { method: 'PUT', url: 'https://u/2', offset: 3, length: 3 },
  ];
  const bytes = Buffer.from('ABCDEF') as Buffer<ArrayBuffer>;

  it('sends a part again after a 5xx or a dropped connection, with backoff', async () => {
    const { calls, sleeps, fetchImpl, sleep } = scripted([html(500), network(), new Response(null, { status: 200 })]);
    await performUploadOperations(ops, bytes, 'a.png', fetchImpl, { sleep, baseDelayMs: 1000 });
    expect(calls.map((c) => c.url)).toEqual(['https://u/1', 'https://u/1', 'https://u/1', 'https://u/2']);
    expect(sleeps).toEqual([1000, 2000]);
  });

  it('fails at once on a final status and after the attempts on a persistent one', async () => {
    const forbidden = scripted([html(403)]);
    await expect(performUploadOperations(ops, bytes, 'a.png', forbidden.fetchImpl, { sleep: forbidden.sleep })).rejects.toThrow(/Could not upload part of a\.png @0 \(403\)\./);
    expect(forbidden.calls).toHaveLength(1);
    const down = scripted([html(503, { 'retry-after': '2' })]);
    await expect(performUploadOperations(ops, bytes, 'a.png', down.fetchImpl, { sleep: down.sleep, maxAttempts: 3 })).rejects.toThrow(/\(503\) after 3 attempts/);
    expect(down.calls).toHaveLength(3);
    expect(down.sleeps).toEqual([2000, 2000]);
  });
});

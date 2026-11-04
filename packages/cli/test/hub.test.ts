import { mkdtemp, mkdir, readFile, rename, rm, stat, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { startHub, type Hub } from '../src/hub/server.js';
import { dotenvNames, KeyStore, ProjectList } from '../src/hub/store.js';

let base: string;
let hub: Hub;

const api = (path: string, init: RequestInit = {}) =>
  fetch(hub.url + path, { ...init, headers: { authorization: `Bearer ${hub.token}`, ...init.headers } });
const post = (path: string, body: unknown) => api(path, { method: 'POST', body: JSON.stringify(body), headers: { 'content-type': 'application/json' } });

beforeEach(async () => {
  base = await mkdtemp(join(tmpdir(), 'vitrin-hub-'));
  hub = await startHub({ support: base, bin: '/nonexistent' });
});

afterEach(async () => {
  await hub.close();
  await rm(base, { recursive: true, force: true });
});

describe('vitrin hub', () => {
  it('turns away a request without the token', async () => {
    expect((await fetch(`${hub.url}/v1/status`)).status).toBe(401);
    expect((await fetch(`${hub.url}/v1/status`, { headers: { authorization: 'Bearer nope' } })).status).toBe(401);
  });

  it('writes its control file for its owner only, and removes it when it stops', async () => {
    const control = JSON.parse(await readFile(hub.controlFile, 'utf8')) as { port: number; token: string; pid: number };
    expect(control).toMatchObject({ port: hub.port, token: hub.token, pid: process.pid });
    expect((await stat(hub.controlFile)).mode & 0o777).toBe(0o600);
  });

  it('keeps the project list in the Mac app\'s format', async () => {
    const folder = join(base, 'Ritim');
    await mkdir(folder);
    const added = (await (await post('/v1/projects', { path: folder })).json()) as { id: string; name: string; initialized: boolean };
    expect(added).toMatchObject({ name: 'Ritim', initialized: false });
    expect((await (await post('/v1/projects', { path: folder })).json()) as { id: string }).toMatchObject({ id: added.id });
    const file = JSON.parse(await readFile(join(base, 'projects.json'), 'utf8')) as Array<{ id: string; path: string; addedAt: number }>;
    expect(file).toHaveLength(1);
    // Swift's default Date: seconds since 2001, so a value this size, not milliseconds since 1970.
    expect(file[0]!.addedAt).toBeLessThan(2_000_000_000);
    expect(((await api(`/v1/projects/${added.id}`, { method: 'DELETE' })).status)).toBe(200);
    expect(await (await api('/v1/projects')).json()).toEqual([]);
  });

  it('tells the phone when the Mac app changes the project list', async () => {
    const response = await api('/v1/events');
    const reader = response.body!.getReader();
    const decoder = new TextDecoder();
    let seen = '';
    const heard = (async () => {
      while (!seen.includes('event: projects')) {
        const { value, done } = await reader.read();
        if (done) return;
        seen += decoder.decode(value);
      }
    })();
    await new Promise((ok) => setTimeout(ok, 50));
    // As the Mac app saves it: a whole new file renamed into place.
    await writeFile(join(base, 'projects.json.new'), '[]');
    await rename(join(base, 'projects.json.new'), join(base, 'projects.json'));
    await heard;
    await reader.cancel();
    expect(seen).toContain('event: projects');
  });

  it('refuses a project that is not an existing absolute folder', async () => {
    expect((await post('/v1/projects', { path: 'relative' })).status).toBe(400);
    expect((await post('/v1/projects', { path: join(base, 'missing') })).status).toBe(404);
  });

  it('stores an App Store Connect key the way the Mac app reads it', async () => {
    const p8 = '-----BEGIN PRIVATE KEY-----\nabc\n-----END PRIVATE KEY-----';
    expect((await post('/v1/asc/key', { keyId: 'ABC123DEF4', issuerId: '69a6de70-03db-47e3-e053-5b8c7c11a4d1', p8: 'nope' })).status).toBe(400);
    expect((await post('/v1/asc/key', { keyId: 'ABC123DEF4', issuerId: '69a6de70-03db-47e3-e053-5b8c7c11a4d1', p8 })).status).toBe(200);
    const stored = new KeyStore(base).get()!;
    expect(stored).toMatchObject({ keyId: 'ABC123DEF4', keyPath: join(base, 'keys', 'AuthKey_ABC123DEF4.p8') });
    expect((await stat(stored.keyPath)).mode & 0o777).toBe(0o600);
    expect(await (await api('/v1/asc/key')).json()).toEqual({ keyId: 'ABC123DEF4', issuerId: '69a6de70-03db-47e3-e053-5b8c7c11a4d1' });
    await api('/v1/asc/key', { method: 'DELETE' });
    expect(new KeyStore(base).get()).toBeUndefined();
  });

  it('stores a key asc left on this Mac, by its path', async () => {
    const file = join(base, 'AuthKey_ABC123DEF4.p8');
    await writeFile(file, '-----BEGIN PRIVATE KEY-----\nabc\n-----END PRIVATE KEY-----\n');
    const res = await post('/v1/asc/key', { keyId: 'ABC123DEF4', issuerId: '69a6de70-03db-47e3-e053-5b8c7c11a4d1', p8Path: file });
    expect(res.status).toBe(200);
    expect(new KeyStore(base).get()?.keyId).toBe('ABC123DEF4');
  });

  it('makes one Apple Ads key pair and keeps it', async () => {
    const first = (await (await post('/v1/ads/keypair', {})).json()) as { publicKey: string; privateKey: string };
    expect(first.publicKey).toContain('BEGIN PUBLIC KEY');
    expect((await stat(first.privateKey)).mode & 0o777).toBe(0o600);
    expect(((await (await post('/v1/ads/keypair', {})).json()) as { publicKey: string }).publicKey).toBe(first.publicKey);
  });

  it('answers 404 for an unknown project\'s Studio', async () => {
    expect((await api('/v1/projects/nope/studio/api/overview')).status).toBe(404);
  });
});

describe('the hub\'s files', () => {
  it('reads what a .env sets', async () => {
    const file = join(base, '.env');
    await writeFile(file, '# note\nASC_KEY_ID=abc\nexport GOOGLE="x"\nEMPTY=\n');
    expect([...dotenvNames(file)].sort()).toEqual(['ASC_KEY_ID', 'GOOGLE']);
  });

  it('reads a list the Mac app wrote', async () => {
    await writeFile(join(base, 'projects.json'), '[{"addedAt":815000000.5,"id":"ABC","path":"/tmp/x"}]');
    expect(new ProjectList(base).find('ABC')?.path).toBe('/tmp/x');
  });
});

import { addSecret, log, mask } from '@vitrin/core';
import { importPKCS8, SignJWT } from 'jose';
import { existsSync, readFileSync } from 'node:fs';
import { attemptLabel, isRetryableStatus, retryDelayMs, retryPolicy, type RetryPolicy } from './retry.js';

const BASE = 'https://api.appstoreconnect.apple.com';
/** Apple allows at most 20 minutes; we stay a bit below. */
const TOKEN_LIFETIME_SEC = 19 * 60;

export interface AscCredentials {
  keyId: string;
  issuerId: string;
  privateKey: string;
}

export class AscCredentialError extends Error {}

/** Reads ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_PATH (or ASC_KEY_CONTENT_BASE64). Throws with a readable message. */
export function credentialsFromEnv(env: NodeJS.ProcessEnv = process.env): AscCredentials {
  const keyId = env.ASC_KEY_ID?.trim();
  const issuerId = env.ASC_ISSUER_ID?.trim();
  let privateKey: string | undefined;
  if (env.ASC_KEY_CONTENT_BASE64?.trim()) {
    privateKey = Buffer.from(env.ASC_KEY_CONTENT_BASE64.trim(), 'base64').toString('utf8');
  } else if (env.ASC_KEY_PATH?.trim()) {
    if (!existsSync(env.ASC_KEY_PATH.trim())) throw new AscCredentialError(`.p8 file not found: ${env.ASC_KEY_PATH}`);
    privateKey = readFileSync(env.ASC_KEY_PATH.trim(), 'utf8');
  }
  if (!keyId || !issuerId || !privateKey) throw new AscCredentialError('ASC API key is missing (ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH).');
  if (!isPem(privateKey)) throw new AscCredentialError('.p8 content is not in PEM format (expected -----BEGIN PRIVATE KEY-----).');
  addSecret(keyId);
  addSecret(issuerId);
  return { keyId, issuerId, privateKey };
}

export function isPem(text: string): boolean {
  return /-----BEGIN PRIVATE KEY-----[\s\S]+-----END PRIVATE KEY-----/.test(text.trim());
}

export async function createToken(creds: AscCredentials, now = Math.floor(Date.now() / 1000)): Promise<string> {
  const key = await importPKCS8(creds.privateKey, 'ES256');
  const token = await new SignJWT({})
    .setProtectedHeader({ alg: 'ES256', kid: creds.keyId, typ: 'JWT' })
    .setIssuer(creds.issuerId)
    .setIssuedAt(now)
    .setExpirationTime(now + TOKEN_LIFETIME_SEC)
    .setAudience('appstoreconnect-v1')
    .sign(key);
  addSecret(token);
  return token;
}

export class AscApiError extends Error {
  constructor(
    public readonly status: number,
    public readonly path: string,
    public readonly errors: Array<{ code?: string; title?: string; detail?: string }>,
  ) {
    super(mask(`ASC API ${status} ${path}: ${errors.map((e) => e.detail ?? e.title ?? e.code).join('; ')}`));
  }
}

/** Thrown when every attempt of a request ended without a response (DNS, reset, timeout). `cause` is the last one. */
export class AscNetworkError extends Error {
  constructor(
    public readonly path: string,
    public readonly attempts: number,
    cause: unknown,
  ) {
    super(mask(`ASC API ${path}: no response after ${attempts} attempt(s): ${cause instanceof Error ? cause.message : String(cause)}`), { cause });
  }
}

/**
 * The body of an error response as the JSON:API `errors` list. App Store Connect's gateways answer 502/503 with
 * HTML, and some 4xx come without a body: both become one entry with the first 300 characters, so the status and
 * path are never lost to a SyntaxError.
 */
export function errorsFromBody(text: string): AscApiError['errors'] {
  const fallback = [{ detail: text.trim().slice(0, 300) || '(empty body)' }];
  try {
    const json = JSON.parse(text) as { errors?: unknown };
    return Array.isArray(json?.errors) && json.errors.length ? (json.errors as AscApiError['errors']) : fallback;
  } catch {
    return fallback;
  }
}

export interface JsonApiResource<A = Record<string, unknown>> {
  type: string;
  id: string;
  attributes: A;
  relationships?: Record<string, { data?: { type: string; id: string } | Array<{ type: string; id: string }> }>;
}

export interface JsonApiDocument<A = Record<string, unknown>> {
  data: JsonApiResource<A> | Array<JsonApiResource<A>>;
  included?: JsonApiResource[];
  links?: { next?: string };
}

/** A 2xx body: JSON, or nothing. A non-JSON 2xx (a gateway page with the wrong status) is reported, not crashed on. */
function parseJsonBody<T>(text: string, status: number, path: string): T {
  if (!text.trim()) return {} as T;
  try {
    return JSON.parse(text) as T;
  } catch {
    throw new AscApiError(status, path, [{ detail: `response is not JSON: ${text.trim().slice(0, 300)}` }]);
  }
}

export class AscClient {
  private token?: { value: string; exp: number };
  private readonly retry: RetryPolicy;

  /** `creds` is undefined only for subclasses that send requests another way (AscCliClient: `asc api`). */
  constructor(
    private readonly creds: AscCredentials | undefined,
    private readonly fetchImpl: typeof fetch = fetch,
    opts: { retry?: Partial<RetryPolicy> } = {},
  ) {
    this.retry = retryPolicy(opts.retry);
  }

  private async auth(): Promise<string> {
    const now = Math.floor(Date.now() / 1000);
    if (!this.creds) throw new AscCredentialError('ASC API key is missing (ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH).');
    if (!this.token || this.token.exp - now < 60) {
      this.token = { value: await createToken(this.creds, now), exp: now + TOKEN_LIFETIME_SEC };
    }
    return this.token.value;
  }

  /**
   * One API call with bounded retries: 429, 5xx and requests that got no response at all are tried again after
   * `Retry-After` (seconds or HTTP-date) or exponential backoff, within the policy's attempt and total-wait caps.
   * Any other 4xx is final. A write may be repeated after a 5xx or a dropped connection, since App Store Connect
   * may or may not have applied it, so it is retried the same way. A DELETE that is answered 404 on a
   * repeat counts as done: the first attempt removed the resource before the response was lost.
   */
  async request<T = JsonApiDocument>(method: string, path: string, body?: unknown): Promise<T> {
    const url = path.startsWith('http') ? path : BASE + path;
    let waitedMs = 0;
    for (let attempt = 1; ; attempt++) {
      const token = await this.auth();
      let res: Response;
      try {
        res = await this.fetchImpl(url, {
          method,
          headers: { Authorization: `Bearer ${token}`, ...(body ? { 'Content-Type': 'application/json' } : {}) },
          body: body ? JSON.stringify(body) : undefined,
        });
      } catch (err) {
        const delay = retryDelayMs({ attempt, waitedMs }, this.retry);
        if (delay === undefined) throw new AscNetworkError(path, attempt, err);
        log.dim(`ASC ${method} ${path}: no response (${(err as Error).message}); retrying in ${Math.round(delay / 1000)} s (${attemptLabel(attempt, this.retry)})`);
        await this.retry.sleep(delay);
        waitedMs += delay;
        continue;
      }
      if (res.status === 204 || (method === 'DELETE' && attempt > 1 && res.status === 404)) return undefined as T;
      const text = await res.text();
      if (res.ok) return parseJsonBody<T>(text, res.status, path);
      const errors = errorsFromBody(text);
      const delay = isRetryableStatus(res.status) ? retryDelayMs({ attempt, waitedMs, retryAfter: res.headers.get('retry-after') }, this.retry) : undefined;
      if (delay === undefined) throw new AscApiError(res.status, path, errors);
      log.dim(`ASC ${method} ${path}: ${res.status}; retrying in ${Math.round(delay / 1000)} s (${attemptLabel(attempt, this.retry)})`);
      await this.retry.sleep(delay);
      waitedMs += delay;
    }
  }

  get<T = JsonApiDocument>(path: string): Promise<T> {
    return this.request<T>('GET', path);
  }

  /**
   * Follows `links.next` and concatenates `data`. A list longer than `maxPages` pages is an error, not a prefix:
   * callers delete what is not in this list, so a silently truncated one would make them delete too much or too
   * little.
   */
  async getAll<A = Record<string, unknown>>(path: string, maxPages = 20): Promise<Array<JsonApiResource<A>>> {
    const out: Array<JsonApiResource<A>> = [];
    let next: string | undefined = path;
    for (let page = 0; next; page++) {
      if (page >= maxPages) throw new Error(`ASC API ${path}: more than ${maxPages} pages; refusing to work with a partial list.`);
      const doc: JsonApiDocument<A> = await this.get<JsonApiDocument<A>>(next);
      out.push(...(Array.isArray(doc.data) ? doc.data : [doc.data]));
      next = doc.links?.next;
    }
    return out;
  }

  async findApp(bundleId: string): Promise<JsonApiResource<{ name: string; bundleId: string; sku: string; primaryLocale: string }> | null> {
    const doc = await this.get<JsonApiDocument<{ name: string; bundleId: string; sku: string; primaryLocale: string }>>(
      `/v1/apps?filter[bundleId]=${encodeURIComponent(bundleId)}&limit=1`,
    );
    const list = Array.isArray(doc.data) ? doc.data : [doc.data];
    return list.find((a) => a.attributes.bundleId === bundleId) ?? null;
  }

  async appStoreVersions(appId: string, platform = 'IOS') {
    return this.getAll<{ versionString: string; appStoreState?: string; appVersionState?: string; platform: string }>(
      `/v1/apps/${appId}/appStoreVersions?filter[platform]=${platform}&limit=50`,
    );
  }

  async versionLocalizations(versionId: string) {
    return this.getAll<Record<string, string | null>>(`/v1/appStoreVersions/${versionId}/appStoreVersionLocalizations?limit=50`);
  }

  async appInfos(appId: string) {
    return this.getAll<{ appStoreState?: string; state?: string }>(`/v1/apps/${appId}/appInfos`);
  }

  async appInfoLocalizations(appInfoId: string) {
    return this.getAll<Record<string, string | null>>(`/v1/appInfos/${appInfoId}/appInfoLocalizations?limit=50`);
  }

  /** GET /v1/appAssetLibraryRefData — placements, display classes, dimensions and limits (API 4.5.1). */
  async assetLibraryRefData(): Promise<unknown> {
    return this.get('/v1/appAssetLibraryRefData');
  }
}

/** Version states in which metadata can still be edited. */
export const EDITABLE_VERSION_STATES = new Set([
  'PREPARE_FOR_SUBMISSION',
  'DEVELOPER_REJECTED',
  'REJECTED',
  'METADATA_REJECTED',
  'INVALID_BINARY',
]);

export function isEditableVersion(v: { attributes: { appStoreState?: string; appVersionState?: string } }): boolean {
  const s = v.attributes.appVersionState ?? v.attributes.appStoreState ?? '';
  return EDITABLE_VERSION_STATES.has(s);
}

/**
 * Bounded retry with exponential backoff for the store APIs and the pre-signed upload PUTs.
 *
 * Everything here is pure except `defaultSleep`: the clients loop, call `retryDelayMs` after a failed attempt, and
 * stop when it returns undefined. The total time spent waiting is capped, and a `Retry-After` the server sends is
 * honoured only while it fits into that cap, so a request can never hang for an hour because a header said so.
 */

export interface RetryPolicy {
  /** Attempts in total, the first one included (default 5). */
  maxAttempts: number;
  /** First backoff wait; each further attempt doubles it (default 1 s). */
  baseDelayMs: number;
  /** Longest single wait (default 30 s). */
  maxDelayMs: number;
  /** Longest total wait across all attempts of one request (default 120 s). */
  maxTotalWaitMs: number;
  /** Injected in tests. */
  sleep: (ms: number) => Promise<void>;
  /** Injected in tests; `Retry-After` dates are measured against it. */
  now: () => number;
}

export const defaultSleep = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

export const DEFAULT_RETRY_POLICY: RetryPolicy = {
  maxAttempts: 5,
  baseDelayMs: 1_000,
  maxDelayMs: 30_000,
  maxTotalWaitMs: 120_000,
  sleep: defaultSleep,
  now: () => Date.now(),
};

export function retryPolicy(over: Partial<RetryPolicy> = {}): RetryPolicy {
  return { ...DEFAULT_RETRY_POLICY, ...over };
}

/** Statuses worth another attempt: rate limits and server-side failures. Every 4xx but 429 is final. */
export function isRetryableStatus(status: number): boolean {
  return status === 429 || status === 500 || status === 502 || status === 503 || status === 504;
}

/**
 * `Retry-After` as milliseconds: a delay in seconds ("30") or an HTTP-date ("Wed, 21 Oct 2026 07:28:00 GMT").
 * Anything else — including a date in the past — is undefined, never NaN, so callers fall back to backoff.
 */
export function parseRetryAfterMs(value: string | null | undefined, now = Date.now()): number | undefined {
  const text = value?.trim();
  if (!text) return undefined;
  if (/^\d+$/.test(text)) return Number(text) * 1000;
  const at = Date.parse(text);
  if (!Number.isFinite(at)) return undefined;
  return Math.max(0, at - now);
}

/** Exponential backoff for the attempt just failed (1-based), capped at `maxDelayMs`. */
export function backoffMs(attempt: number, policy: Pick<RetryPolicy, 'baseDelayMs' | 'maxDelayMs'>): number {
  return Math.min(policy.maxDelayMs, policy.baseDelayMs * 2 ** Math.max(0, attempt - 1));
}

export interface RetryState {
  /** The attempt that just failed, 1-based. */
  attempt: number;
  /** Milliseconds already spent waiting for this request. */
  waitedMs: number;
  /** The failed response's `Retry-After` header, when there was one. */
  retryAfter?: string | null;
}

/**
 * How long to wait before the next attempt, or undefined when no further attempt is allowed: the attempts are used
 * up, or the wait — the server's `Retry-After` or the backoff — would push the total past `maxTotalWaitMs`.
 */
export function retryDelayMs(state: RetryState, policy: RetryPolicy): number | undefined {
  if (state.attempt >= policy.maxAttempts) return undefined;
  const delay = parseRetryAfterMs(state.retryAfter, policy.now()) ?? backoffMs(state.attempt, policy);
  if (!Number.isFinite(delay) || delay < 0) return undefined;
  if (state.waitedMs + delay > policy.maxTotalWaitMs) return undefined;
  return delay;
}

/** `attempt 2/5` style suffix for log lines. */
export function attemptLabel(attempt: number, policy: Pick<RetryPolicy, 'maxAttempts'>): string {
  return `attempt ${attempt}/${policy.maxAttempts}`;
}

import { createHash } from 'node:crypto';
import { basename } from 'node:path';
import { attemptLabel, defaultSleep, isRetryableStatus, retryDelayMs, retryPolicy, type RetryPolicy } from './retry.js';
import { log } from '@vitrin/core';

export { defaultSleep } from './retry.js';

/** components.schemas.UploadOperation (ASC API 4.5.1). */
export interface UploadOperation {
  method: string;
  url: string;
  offset: number;
  length: number;
  requestHeaders?: Array<{ name: string; value: string }>;
}

export interface PollOptions {
  /** Interval between GETs (default 5 s). */
  intervalMs?: number;
  /** Give up waiting after this long; the caller decides whether that is an error. */
  timeoutMs?: number;
  /** Injected in tests. */
  sleep?: (ms: number) => Promise<void>;
}

/**
 * Sends each part of a reserved asset to the URL App Store Connect returned (`uploadOperations`), with exactly the
 * headers it named. The URLs are pre-signed: no Authorization header is sent. A part whose PUT gets no response, a
 * 429 or a 5xx is sent again with backoff within the retry policy; any other status is final. Parts are independent
 * PUTs of fixed byte ranges, so repeating one is safe.
 */
export async function performUploadOperations(ops: UploadOperation[], bytes: Buffer<ArrayBuffer>, file: string, fetchImpl: typeof fetch = fetch, retry: Partial<RetryPolicy> = {}): Promise<void> {
  if (!ops.length) throw new Error(`No uploadOperations returned for ${basename(file)}.`);
  const policy = retryPolicy(retry);
  for (const op of ops) {
    const headers = Object.fromEntries((op.requestHeaders ?? []).map((h) => [h.name, h.value]));
    const part = `part of ${basename(file)} @${op.offset}`;
    let waitedMs = 0;
    for (let attempt = 1; ; attempt++) {
      let failure: { message: string; retryable: boolean; retryAfter?: string | null };
      try {
        const r = await fetchImpl(op.url, { method: op.method, headers, body: bytes.subarray(op.offset, op.offset + op.length) });
        if (r.ok) break;
        failure = { message: `Could not upload ${part} (${r.status})`, retryable: isRetryableStatus(r.status), retryAfter: r.headers.get('retry-after') };
      } catch (err) {
        failure = { message: `Could not upload ${part}: no response (${(err as Error).message})`, retryable: true };
      }
      const delay = failure.retryable ? retryDelayMs({ attempt, waitedMs, retryAfter: failure.retryAfter }, policy) : undefined;
      if (delay === undefined) throw new Error(`${failure.message}${attempt > 1 ? ` after ${attempt} attempts` : ''}.`);
      log.dim(`${failure.message}; retrying in ${Math.round(delay / 1000)} s (${attemptLabel(attempt, policy)})`);
      await policy.sleep(delay);
      waitedMs += delay;
    }
  }
}

/** MD5 hex digest: `sourceFileChecksum` of appScreenshots/appPreviews commits. */
export function md5(bytes: Uint8Array): string {
  return createHash('md5').update(bytes).digest('hex');
}

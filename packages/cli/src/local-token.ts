import { randomBytes, timingSafeEqual } from 'node:crypto';

/**
 * The session token of a local server (`vitrin studio`, `vitrin review --serve`).
 *
 * The server mints one token per run and hands it only to the page it serves itself (a `<meta>` tag in the
 * Studio's index.html or in report.html). Every request that changes something — a job, a file, an approval, a
 * Claude run — must carry it in the `x-vitrin-token` header. Pages the server serves from `metadata/` (Claude's HTML
 * screens, bespoke layouts, the store preview) never get it: they run sandboxed, in an opaque origin, so a script
 * in one of them can neither read the Studio's page nor call the API. The token is not a defence against other
 * processes on the same machine, which can already read the project's files.
 */

export const TOKEN_HEADER = 'x-vitrin-token';
export const TOKEN_META = 'vitrin-token';

/** Pages served from metadata/ run sandboxed: scripts allowed, but no origin, no storage and no access to the API. */
export const SANDBOX_CSP = 'sandbox allow-scripts allow-forms allow-popups allow-modals';

export function newSessionToken(): string {
  return randomBytes(24).toString('base64url');
}

export function tokenMatches(given: string | string[] | undefined, token: string): boolean {
  const g = Array.isArray(given) ? given[0] : given;
  if (typeof g !== 'string' || g.length !== token.length) return false;
  return timingSafeEqual(Buffer.from(g), Buffer.from(token));
}

/** Puts the token into a page the server renders itself (never into a file from metadata/). */
export function withSessionToken(html: string, token: string): string {
  const tag = `<meta name="${TOKEN_META}" content="${token}">`;
  return html.includes('</head>') ? html.replace('</head>', `${tag}</head>`) : `${tag}\n${html}`;
}

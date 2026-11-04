import { existsSync, readFileSync, watch } from 'node:fs';
import { mkdir, rm } from 'node:fs/promises';
import { createServer, request, type IncomingMessage, type Server, type ServerResponse } from 'node:http';
import type { AddressInfo } from 'node:net';
import { randomBytes, randomUUID, timingSafeEqual } from 'node:crypto';
import { basename, join, resolve } from 'node:path';
import { log, vitrinVersion } from '@vitrin/core';
import { appSupport, KeyStore, ProjectList, writePrivate, type StoredProject } from './store.js';
import { adsKeyPair, installTool, runAsc, which } from './tools.js';
import { Studios, type StudioEvent } from './studios.js';
import { WebSession } from './web.js';

/** Bump on a change the phone must know about; `/v1/status` reports it. */
export const HUB_API = 1;
/** Largest text one response carries: the phone's channel takes about 4 MB per message. */
const PART_BYTES = 3_000_000;
const MAX_BODY = 4_000_000;

export interface HubOptions {
  port?: number;
  support?: string;
  /** The CLI's entry point, for the Studios the hub starts. */
  bin?: string;
  idleMs?: number;
}

export interface Hub {
  url: string;
  port: number;
  token: string;
  controlFile: string;
  close: () => Promise<void>;
}

function send(res: ServerResponse, status: number, body: unknown): void {
  const data = JSON.stringify(body);
  res.writeHead(status, { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store', 'content-length': Buffer.byteLength(data) });
  res.end(data);
}

async function readBody(req: IncomingMessage): Promise<Record<string, unknown>> {
  const chunks: Buffer[] = [];
  let size = 0;
  for await (const chunk of req) {
    size += (chunk as Buffer).length;
    if (size > MAX_BODY) throw Object.assign(new Error('Request body too large.'), { status: 413 });
    chunks.push(chunk as Buffer);
  }
  if (!size) return {};
  try {
    return JSON.parse(Buffer.concat(chunks).toString('utf8')) as Record<string, unknown>;
  } catch {
    throw Object.assign(new Error('Invalid JSON.'), { status: 400 });
  }
}

const authorized = (given: string | undefined, token: string): boolean => {
  const expected = `Bearer ${token}`;
  return given?.length === expected.length && timingSafeEqual(Buffer.from(given), Buffer.from(expected));
};

const strings = (v: unknown): string[] | undefined => (Array.isArray(v) && v.every((x) => typeof x === 'string') ? (v as string[]) : undefined);

/** A project row: what the list shows before any Studio runs. */
async function describe(project: StoredProject, running: boolean) {
  const config = join(project.path, 'vitrin.config.yaml');
  const initialized = existsSync(config);
  let bundleId: string | undefined;
  if (initialized) {
    try {
      bundleId = /^\s*bundleId:\s*['"]?([\w.-]+)/m.exec(readFileSync(config, 'utf8'))?.[1];
    } catch {
      /* unreadable config: the Studio explains it */
    }
  }
  return { id: project.id, path: project.path, name: basename(project.path), exists: existsSync(project.path), initialized, bundleId, running };
}

/**
 * The local control API of Vitrin: everything a program on this Mac needs to run Vitrin for someone who is not at it,
 * such as Remote Code for the phone. It serves 127.0.0.1 only, behind a bearer token in a file only this user can read,
 * and is documented in docs/HUB_API.md.
 */
export async function startHub(opts: HubOptions = {}): Promise<Hub> {
  const base = opts.support ?? appSupport();
  await mkdir(base, { recursive: true, mode: 0o700 });
  const projects = new ProjectList(base);
  const keys = new KeyStore(base);
  const web = new WebSession(base, () => keys.get());
  const token = randomBytes(32).toString('base64url');
  const clients = new Set<ServerResponse>();
  const parts = new Map<string, string>();

  const broadcast = (event: string, data: unknown) => {
    const text = `event: ${event}\ndata: ${JSON.stringify(data)}\n\n`;
    for (const c of clients) c.write(text);
  };
  const studios = new Studios(opts.bin ?? process.argv[1]!, () => keys.get(), (e: StudioEvent) => broadcast('studio', e), opts.idleMs);
  const heartbeat = setInterval(() => broadcast('ping', {}), 25_000);
  heartbeat.unref();
  // The Mac app writes the same file: the phone hears about its changes too. Writers rename into place, so the folder is watched.
  let settle: NodeJS.Timeout | undefined;
  const listWatcher = watch(base, (_, name) => {
    if (name !== 'projects.json') return;
    clearTimeout(settle);
    settle = setTimeout(() => broadcast('projects', {}), 100);
  });
  listWatcher.unref();

  const project = (id: string): StoredProject => {
    const p = projects.find(id);
    if (!p) throw Object.assign(new Error('No such project.'), { status: 404 });
    return p;
  };

  async function connection() {
    const key = keys.get();
    const asc = await which('asc');
    if (key) return { state: 'vitrinKey', keyId: key.keyId, asc: Boolean(asc) };
    if (!asc) return { state: 'missingCLI', asc: false };
    const r = await runAsc(['auth', 'status', '--output', 'json'], undefined, { timeoutMs: 20_000 });
    try {
      const creds = (JSON.parse(r.stdout) as { credentials?: Array<{ name?: string; keyId?: string; isDefault?: boolean }> }).credentials ?? [];
      const pick = creds.find((c) => c.isDefault) ?? creds[0];
      if (pick) return { state: 'ascLogin', name: pick.name ?? 'asc', keyId: pick.keyId ?? '', asc: true };
    } catch {
      /* no usable login */
    }
    return { state: 'none', asc: true };
  }

  /** Passes a request to the project's Studio, with the session token only the hub holds. */
  async function proxy(req: IncomingMessage, res: ServerResponse, id: string, path: string): Promise<void> {
    const studio = await studios.open(project(id));
    const headers: Record<string, string> = { host: `127.0.0.1:${studio.port}`, 'x-vitrin-token': studio.token };
    for (const h of ['content-type', 'range', 'accept', 'if-none-match']) {
      const v = req.headers[h];
      if (typeof v === 'string') headers[h] = v;
    }
    await new Promise<void>((ok) => {
      const upstream = request({ host: '127.0.0.1', port: studio.port, path, method: req.method, headers }, (r) => {
        res.writeHead(r.statusCode ?? 502, r.headers);
        r.pipe(res);
        r.on('end', ok);
      });
      upstream.on('error', (e) => {
        if (!res.headersSent) send(res, 502, { error: e.message });
        else res.destroy();
        ok();
      });
      req.pipe(upstream);
    });
  }

  async function route(req: IncomingMessage, res: ServerResponse, url: URL): Promise<void> {
    const path = url.pathname;
    const method = req.method ?? 'GET';

    if (path === '/v1/status' && method === 'GET') {
      const tools = Object.fromEntries(await Promise.all(['node', 'claude', 'asc', 'ffmpeg', 'brew'].map(async (t) => [t, Boolean(await which(t))] as const)));
      return send(res, 200, { api: HUB_API, version: vitrinVersion(), tools, connection: await connection() });
    }
    if (path === '/v1/events' && method === 'GET') {
      res.writeHead(200, { 'content-type': 'text/event-stream', 'cache-control': 'no-store', connection: 'keep-alive' });
      res.write(`event: hello\ndata: ${JSON.stringify({ api: HUB_API })}\n\n`);
      clients.add(res);
      req.on('close', () => clients.delete(res));
      return;
    }
    if (path === '/v1/projects') {
      if (method === 'GET') return send(res, 200, await Promise.all(projects.all().map((p) => describe(p, studios.isRunning(p.id)))));
      if (method === 'POST') {
        const body = await readBody(req);
        if (typeof body.path !== 'string' || !body.path.startsWith('/')) return send(res, 400, { error: 'A project needs an absolute path.' });
        if (!existsSync(body.path)) return send(res, 404, { error: 'That folder does not exist.' });
        const added = await projects.add(body.path);
        broadcast('projects', {});
        return send(res, 200, await describe(added, studios.isRunning(added.id)));
      }
    }
    const match = /^\/v1\/projects\/([\w-]+)(\/.*)?$/.exec(path);
    if (match) {
      const id = match[1]!;
      const rest = match[2] ?? '';
      if (rest === '' && method === 'DELETE') {
        studios.stop(id);
        const removed = await projects.remove(id);
        broadcast('projects', {});
        return send(res, removed ? 200 : 404, removed ? { ok: true } : { error: 'No such project.' });
      }
      if (rest === '/open' && method === 'POST') {
        await studios.open(project(id));
        await new Promise((ok) => setTimeout(ok, 150));
        return send(res, 200, { hello: studios.hello(id) ?? null });
      }
      if (rest === '/close' && method === 'POST') {
        studios.touch(id);
        return send(res, 200, { ok: true });
      }
      if (rest.startsWith('/studio/')) return proxy(req, res, id, rest.slice('/studio'.length) + url.search);
    }
    if (path === '/v1/asc' && method === 'POST') {
      const body = await readBody(req);
      const args = strings(body.args);
      if (!args) return send(res, 400, { error: 'args must be a list of strings.' });
      const timeoutMs = Math.min(Number(body.timeout ?? 180), 900) * 1000;
      const r = await runAsc(args, keys.get(), { write: body.write === true, timeoutMs });
      if (Buffer.byteLength(r.stdout) <= PART_BYTES) return send(res, 200, r);
      const id = randomUUID();
      parts.set(id, r.stdout);
      setTimeout(() => parts.delete(id), 10 * 60_000).unref();
      return send(res, 200, { code: r.code, stderr: r.stderr, stdout: '', part: { id, length: r.stdout.length } });
    }
    const part = /^\/v1\/asc\/part\/([\w-]+)$/.exec(path);
    if (part && method === 'GET') {
      const text = parts.get(part[1]!);
      if (text === undefined) return send(res, 404, { error: 'That result has expired.' });
      const offset = Number(url.searchParams.get('offset') ?? 0);
      // Characters, not bytes, so a part never splits one; the worst case still fits in a message.
      return send(res, 200, { text: text.slice(offset, offset + PART_BYTES / 3) });
    }
    if (path === '/v1/asc/key') {
      if (method === 'GET') {
        const key = keys.get();
        return send(res, 200, key ? { keyId: key.keyId, issuerId: key.issuerId } : null);
      }
      if (method === 'POST') {
        const body = await readBody(req);
        // A key `asc web api-keys create` left on this Mac comes by path: asc never prints it.
        const p8 = typeof body.p8Path === 'string' && body.p8Path.endsWith('.p8') ? readFileSync(body.p8Path, 'utf8') : String(body.p8 ?? '');
        const key = await keys.save(String(body.keyId ?? ''), String(body.issuerId ?? ''), p8);
        broadcast('connection', {});
        return send(res, 200, { keyId: key.keyId, issuerId: key.issuerId });
      }
      if (method === 'DELETE') {
        await keys.clear();
        broadcast('connection', {});
        return send(res, 200, { ok: true });
      }
    }
    if (path === '/v1/ads/keypair' && method === 'POST') return send(res, 200, await adsKeyPair(base));
    if (path === '/v1/asc/web' && method === 'GET') return send(res, 200, web.state());
    if (path === '/v1/asc/web' && method === 'POST') {
      const body = await readBody(req);
      const args = strings(body.args);
      if (!args) return send(res, 400, { error: 'args must be a list of strings.' });
      await web.start(args, typeof body.password === 'string' ? body.password : undefined);
      return send(res, 200, web.state());
    }
    if (path === '/v1/asc/web/code' && method === 'POST') {
      await web.code(String((await readBody(req)).code ?? ''));
      return send(res, 200, web.state());
    }
    if (path === '/v1/tools/install' && method === 'POST') {
      const r = await installTool(String((await readBody(req)).tool ?? ''));
      broadcast('connection', {});
      return send(res, r.code === 0 ? 200 : 500, r.code === 0 ? { ok: true } : { error: r.stderr.trim().slice(-400) || 'The install failed.' });
    }
    return send(res, 404, { error: 'Not found.' });
  }

  const server: Server = createServer((req, res) => {
    const handle = async () => {
      if (!authorized(req.headers.authorization, token)) return send(res, 401, { error: 'Unauthorized.' });
      await route(req, res, new URL(req.url ?? '/', 'http://127.0.0.1'));
    };
    handle().catch((err: Error & { status?: number }) => {
      if (!res.headersSent) send(res, err.status ?? 500, { error: err.message });
      else res.destroy();
    });
  });
  await new Promise<void>((ok, fail) => {
    server.once('error', fail);
    server.listen(opts.port ?? 0, '127.0.0.1', () => ok());
  });
  const port = (server.address() as AddressInfo).port;
  const controlFile = join(base, 'control.json');
  await writePrivate(controlFile, JSON.stringify({ version: HUB_API, port, token, pid: process.pid, vitrin: vitrinVersion() }));

  return {
    url: `http://127.0.0.1:${port}`,
    port,
    token,
    controlFile,
    close: async () => {
      clearInterval(heartbeat);
      clearTimeout(settle);
      listWatcher.close();
      studios.stopAll();
      for (const c of clients) c.end();
      server.closeAllConnections?.();
      await new Promise<void>((ok) => server.close(() => ok()));
      await rm(controlFile, { force: true });
    },
  };
}

/** `vitrin hub`: runs until it is stopped, or until the program that started it is gone. */
export async function hubCommand(opts: { port?: number; attached?: boolean }): Promise<number> {
  const hub = await startHub({ port: opts.port, bin: resolve(process.argv[1]!) });
  log.ok(`Vitrin hub on ${hub.url} (127.0.0.1 only; the token is in ${hub.controlFile})`);
  await new Promise<void>((ok) => {
    process.once('SIGINT', () => ok());
    process.once('SIGTERM', () => ok());
    if (opts.attached) {
      const parent = process.ppid;
      setInterval(() => {
        if (process.ppid !== parent) ok();
      }, 2000).unref();
    }
  });
  await hub.close();
  return 0;
}


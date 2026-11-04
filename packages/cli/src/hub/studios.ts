import { randomUUID } from 'node:crypto';
import { spawn, type ChildProcess } from 'node:child_process';
import { existsSync, readFileSync, rmSync } from 'node:fs';
import { get, type ClientRequest, type IncomingMessage } from 'node:http';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { dotenvNames, type StoredKey, type StoredProject } from './store.js';
import { shellEnv } from './tools.js';

interface Handshake {
  url: string;
  port: number;
  token: string;
}

export interface StudioEvent {
  project: string;
  event: string;
  data: string;
}

interface Running extends Handshake {
  child: ChildProcess;
  events?: ClientRequest;
  hello?: string;
  usedAt: number;
}

/** One `vitrin studio` per open project, started on first use and stopped after it has sat idle. */
export class Studios {
  private readonly running = new Map<string, Running>();
  private readonly starting = new Map<string, Promise<Running>>();
  private readonly sweep: NodeJS.Timeout;

  constructor(
    private readonly bin: string,
    private readonly key: () => StoredKey | undefined,
    private readonly emit: (event: StudioEvent) => void,
    private readonly idleMs = 30 * 60_000,
  ) {
    this.sweep = setInterval(() => void this.stopIdle(), Math.min(60_000, Math.max(idleMs / 4, 50)));
    this.sweep.unref();
  }

  isRunning(id: string): boolean {
    return this.running.has(id);
  }

  async open(project: StoredProject): Promise<Handshake> {
    const open = this.running.get(project.id);
    if (open) {
      open.usedAt = Date.now();
      return open;
    }
    let pending = this.starting.get(project.id);
    if (!pending) {
      pending = this.start(project).finally(() => this.starting.delete(project.id));
      this.starting.set(project.id, pending);
    }
    return pending;
  }

  private async start(project: StoredProject): Promise<Running> {
    const file = join(tmpdir(), `vitrin-hub-studio-${randomUUID()}.json`);
    const key = this.key();
    const usesOwnKey = dotenvNames(join(project.path, '.env')).has('ASC_KEY_ID');
    const env = { ...(await shellEnv()), ...(key && !usesOwnKey ? { ASC_KEY_ID: key.keyId, ASC_ISSUER_ID: key.issuerId, ASC_KEY_PATH: key.keyPath } : {}) };
    const child = spawn(process.execPath, [this.bin, '--cwd', project.path, 'studio', '--no-open', '--port', '0', '--token-file', file], { env, cwd: project.path, stdio: ['ignore', 'ignore', 'pipe'] });
    let stderr = '';
    child.stderr?.on('data', (d: Buffer) => {
      stderr = (stderr + d.toString('utf8')).slice(-600);
    });
    const handshake = await new Promise<Handshake>((ok, fail) => {
      const started = Date.now();
      const timer = setInterval(() => {
        if (existsSync(file)) {
          try {
            ok(JSON.parse(readFileSync(file, 'utf8')) as Handshake);
            clearInterval(timer);
          } catch {
            /* being written */
          }
        } else if (child.exitCode !== null || Date.now() - started > 45_000) {
          clearInterval(timer);
          child.kill();
          fail(Object.assign(new Error(stderr.trim() || 'The Studio did not start.'), { status: 502 }));
        }
      }, 60);
    });
    const running: Running = { ...handshake, child, usedAt: Date.now() };
    this.running.set(project.id, running);
    child.once('exit', () => {
      rmSync(file, { force: true });
      running.events?.destroy();
      if (this.running.get(project.id) === running) this.running.delete(project.id);
    });
    this.follow(project.id, running);
    return running;
  }

  /** Reads the Studio's events for as long as it runs, and passes them on with the project they came from. */
  private follow(id: string, running: Running): void {
    running.events = get({ host: '127.0.0.1', port: running.port, path: '/api/events', headers: { host: `127.0.0.1:${running.port}` } }, (res) => {
      parseEvents(res, (event, data) => {
        if (event === 'hello') running.hello = data;
        this.emit({ project: id, event, data });
      });
    });
    running.events.on('error', () => undefined);
  }

  /** The event a new listener would get first: what is running now. */
  hello(id: string): string | undefined {
    return this.running.get(id)?.hello;
  }

  touch(id: string): void {
    const open = this.running.get(id);
    if (open) open.usedAt = Date.now();
  }

  private async stopIdle(): Promise<void> {
    for (const [, s] of this.running) {
      if (Date.now() - s.usedAt < this.idleMs) continue;
      if (await busy(s)) {
        s.usedAt = Date.now();
        continue;
      }
      s.child.kill('SIGTERM');
    }
  }

  stop(id: string): void {
    this.running.get(id)?.child.kill('SIGTERM');
  }

  stopAll(): void {
    clearInterval(this.sweep);
    for (const s of this.running.values()) s.child.kill('SIGTERM');
  }
}

/** A running job or Claude run keeps the Studio alive however long nobody looks. */
async function busy(s: Handshake): Promise<boolean> {
  try {
    const res = await fetch(`${s.url}api/overview`, { signal: AbortSignal.timeout(5000) });
    const overview = (await res.json()) as { job?: unknown; claude?: { running?: unknown } };
    return Boolean(overview.job) || Boolean(overview.claude?.running);
  } catch {
    return false;
  }
}

/** Server-sent events, one `event:` and one `data:` line per block. */
export function parseEvents(res: IncomingMessage, on: (event: string, data: string) => void): void {
  let buffer = '';
  res.setEncoding('utf8');
  res.on('data', (chunk: string) => {
    buffer += chunk;
    let end: number;
    while ((end = buffer.indexOf('\n\n')) >= 0) {
      const block = buffer.slice(0, end);
      buffer = buffer.slice(end + 2);
      let event = 'message';
      let data = '';
      for (const line of block.split('\n')) {
        if (line.startsWith('event:')) event = line.slice(6).trim();
        else if (line.startsWith('data:')) data += line.slice(5).trim();
      }
      if (data) on(event, data);
    }
  });
}

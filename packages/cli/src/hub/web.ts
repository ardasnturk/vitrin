import { mkdir, rm, writeFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { runAsc, type RunResult } from './tools.js';
import { type StoredKey, writePrivate } from './store.js';

/**
 * `asc web …` runs need the Apple Account password and may ask for a two-factor code part way through. asc reads the
 * code from a command: this one waits for a file, and the phone answers through `/v1/asc/web/code` (the Mac app's
 * AppleWebSession). A run outlives any one request, so the phone starts it and reads its state.
 */
export class WebSession {
  private current?: { needsCode: boolean; result?: RunResult };
  private watcher?: NodeJS.Timeout;

  constructor(private readonly base: string, private readonly key: () => StoredKey | undefined) {}

  private get folder(): string {
    return join(this.base, 'web-2fa-hub');
  }

  state(): { running: boolean; needsCode: boolean; result?: RunResult } {
    return { running: Boolean(this.current && !this.current.result), needsCode: this.current?.needsCode ?? false, result: this.current?.result };
  }

  async code(code: string): Promise<void> {
    const digits = code.replace(/\D/g, '');
    if (digits) await writePrivate(join(this.folder, 'code'), digits);
    if (this.current) this.current.needsCode = false;
  }

  async start(args: string[], password?: string): Promise<void> {
    if (this.state().running) throw Object.assign(new Error('Another Apple Account step is running.'), { status: 409 });
    await rm(this.folder, { recursive: true, force: true });
    await mkdir(this.folder, { recursive: true, mode: 0o700 });
    const script = join(this.folder, 'code.sh');
    await writeFile(script, `#!/bin/sh\nd='${this.folder}'\n: > "$d/asked"\ni=0\nwhile [ ! -s "$d/code" ] && [ "$i" -lt 580 ]; do sleep 0.5; i=$((i+1)); done\n[ -s "$d/code" ] || exit 1\ncat "$d/code"\nrm -f "$d/code"\n`, { mode: 0o700 });
    const session = { needsCode: false } as { needsCode: boolean; result?: RunResult };
    this.current = session;
    this.watcher = setInterval(() => {
      if (existsSync(join(this.folder, 'asked'))) {
        session.needsCode = true;
        void rm(join(this.folder, 'asked'), { force: true });
      }
    }, 300);
    const env: NodeJS.ProcessEnv = { ASC_WEB_2FA_CODE_COMMAND: script, ...(password ? { ASC_WEB_PASSWORD: password } : {}) };
    void runAsc(args, this.key(), { write: true, timeoutMs: 320_000, env })
      .then((result) => {
        session.result = result;
        session.needsCode = false;
      })
      .finally(() => {
        clearInterval(this.watcher);
        void rm(this.folder, { recursive: true, force: true });
      });
  }
}

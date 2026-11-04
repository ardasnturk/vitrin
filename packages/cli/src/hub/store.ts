import { randomUUID } from 'node:crypto';
import { existsSync, readFileSync } from 'node:fs';
import { chmod, mkdir, rename, rm, writeFile } from 'node:fs/promises';
import { homedir } from 'node:os';
import { basename, join, resolve } from 'node:path';

/**
 * The files the hub shares with Vitrin for Mac: ~/Library/Application Support/Vitrin (`VITRIN_APP_SUPPORT` names
 * another folder), holding the project list, the App Store Connect key and the hub's own control file.
 */
export function appSupport(): string {
  return process.env.VITRIN_APP_SUPPORT ?? join(homedir(), 'Library', 'Application Support', 'Vitrin');
}

/** Writes through a temporary file and a rename, owner-only: a reader never sees half a file. */
export async function writePrivate(file: string, text: string): Promise<void> {
  const tmp = `${file}.${process.pid}.tmp`;
  await writeFile(tmp, text, { encoding: 'utf8', mode: 0o600 });
  await rename(tmp, file);
}

/** Swift's default `Date` encoding: seconds since 2001-01-01. */
const SWIFT_EPOCH = 978_307_200;

export interface StoredProject {
  id: string;
  path: string;
  addedAt: number;
}

/** projects.json, the same file and format as the Mac app's ProjectStore. */
export class ProjectList {
  constructor(private readonly base: string) {}

  private get file(): string {
    return join(this.base, 'projects.json');
  }

  all(): StoredProject[] {
    try {
      const list = JSON.parse(readFileSync(this.file, 'utf8')) as unknown;
      return Array.isArray(list) ? (list as StoredProject[]) : [];
    } catch {
      return [];
    }
  }

  find(id: string): StoredProject | undefined {
    return this.all().find((p) => p.id === id);
  }

  async add(path: string): Promise<StoredProject> {
    const standard = resolve(path);
    const list = this.all();
    const existing = list.find((p) => p.path === standard);
    if (existing) return existing;
    const project = { id: randomUUID().toUpperCase(), path: standard, addedAt: Date.now() / 1000 - SWIFT_EPOCH };
    await this.save([...list, project]);
    return project;
  }

  async remove(id: string): Promise<boolean> {
    const list = this.all();
    const rest = list.filter((p) => p.id !== id);
    if (rest.length === list.length) return false;
    await this.save(rest);
    return true;
  }

  private async save(list: StoredProject[]): Promise<void> {
    await mkdir(this.base, { recursive: true, mode: 0o700 });
    await writePrivate(this.file, `${JSON.stringify(list, null, 2)}\n`);
  }
}

export interface StoredKey {
  keyId: string;
  issuerId: string;
  keyPath: string;
}

/** The App Store Connect key Vitrin holds once for every project, as the Mac app's ASCCredentials stores it. */
export class KeyStore {
  constructor(private readonly base: string) {}

  private get file(): string {
    return join(this.base, 'credentials.json');
  }

  get(): StoredKey | undefined {
    try {
      const key = JSON.parse(readFileSync(this.file, 'utf8')) as StoredKey;
      return key.keyId && key.issuerId && existsSync(key.keyPath) ? key : undefined;
    } catch {
      return undefined;
    }
  }

  async save(keyId: string, issuerId: string, p8: string): Promise<StoredKey> {
    const id = keyId.trim();
    const issuer = issuerId.trim();
    const pem = p8.trim();
    if (!/^[A-Z0-9]{6,20}$/i.test(id)) throw Object.assign(new Error('That Key ID does not look right.'), { status: 400 });
    if (!/^[0-9a-f-]{20,}$/i.test(issuer)) throw Object.assign(new Error('That Issuer ID does not look right.'), { status: 400 });
    if (!pem.includes('BEGIN PRIVATE KEY') || !pem.includes('END PRIVATE KEY')) throw Object.assign(new Error('That is not a .p8 private key.'), { status: 400 });
    const folder = join(this.base, 'keys');
    await mkdir(folder, { recursive: true, mode: 0o700 });
    const keyPath = join(folder, `AuthKey_${basename(id)}.p8`);
    await writePrivate(keyPath, `${pem}\n`);
    const key = { keyId: id, issuerId: issuer, keyPath };
    await writePrivate(this.file, JSON.stringify(key));
    await chmod(this.file, 0o600);
    return key;
  }

  async clear(): Promise<void> {
    const key = this.get();
    if (key) await rm(key.keyPath, { force: true });
    await rm(this.file, { force: true });
  }
}

/** The names a `.env` file sets to a non-empty value (`KEY=value`, `export KEY=value`). */
export function dotenvNames(file: string): Set<string> {
  const names = new Set<string>();
  let text: string;
  try {
    text = readFileSync(file, 'utf8');
  } catch {
    return names;
  }
  for (const raw of text.split('\n')) {
    const line = raw.trim().replace(/^export\s+/, '');
    if (!line || line.startsWith('#')) continue;
    const eq = line.indexOf('=');
    if (eq <= 0) continue;
    const value = line.slice(eq + 1).trim().replace(/^(["'])(.*)\1$/, '$2');
    if (value) names.add(line.slice(0, eq).trim());
  }
  return names;
}

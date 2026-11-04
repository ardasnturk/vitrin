import { androidEntriesOf, legacyUploaderOf, VitrinConfig } from '@vitrin/schemas';
import { parse as parseDotenv } from 'dotenv';
import { existsSync, readFileSync } from 'node:fs';
import { dirname, isAbsolute, resolve } from 'node:path';
import { parse as parseYaml } from 'yaml';
import { parseWith } from './fsx.js';
import { log, registerEnvSecrets } from './logger.js';

export function loadConfig(file: string): VitrinConfig {
  if (!existsSync(file)) {
    throw new Error(`vitrin.config.yaml not found (${file}). Run \`vitrin init\` first.`);
  }
  const data = parseYaml(readFileSync(file, 'utf8')) ?? {};
  const config = parseWith(file, data, VitrinConfig);
  const android = androidEntriesOf(data);
  if (android.length && !warnedAndroid.has(file)) {
    warnedAndroid.add(file);
    log.warn(`vitrin.config.yaml still names Android (${android.join(', ')}): Vitrin is for Apple platforms only now, so these entries are ignored. Delete them from the file.`);
  }
  const legacy = legacyUploaderOf(config);
  if (legacy && !warnedLegacyUploader.has(file)) {
    // Once per config file and process: the Studio re-reads the config on every request.
    warnedLegacyUploader.add(file);
    log.warn(`upload.uploader: ${legacy} was removed; App Store uploads always use the asc CLI now (brew install asc). Delete the line from vitrin.config.yaml.`);
  }
  return config;
}

const warnedLegacyUploader = new Set<string>();
const warnedAndroid = new Set<string>();

/**
 * Loads `.env` without overriding variables already set in the process environment,
 * and registers every secret for log masking. Returns the merged view.
 */
export function loadEnv(file: string): NodeJS.ProcessEnv {
  if (existsSync(file)) {
    const parsed = parseDotenv(readFileSync(file));
    for (const [k, v] of Object.entries(parsed)) {
      if (process.env[k] === undefined || process.env[k] === '') process.env[k] = v;
    }
  }
  // Relative key paths in .env are relative to the app repo, not to the shell's working directory.
  for (const k of ['ASC_KEY_PATH', 'APPLE_ADS_PRIVATE_KEY_PATH']) {
    const v = process.env[k]?.trim();
    if (v && !isAbsolute(v)) process.env[k] = resolve(dirname(file), v);
  }
  registerEnvSecrets(process.env);
  return process.env;
}

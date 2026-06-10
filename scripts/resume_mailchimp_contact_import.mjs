#!/usr/bin/env node

import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const DEFAULT_FUNCTION_NAME = 'mailchimp-contact-sync';

function loadEnvFile(path) {
  if (!existsSync(path)) return;

  const contents = readFileSync(path, 'utf8');
  for (const line of contents.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;

    const match = trimmed.match(/^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$/);
    if (!match) continue;

    const [, key, rawValue] = match;
    if (process.env[key] !== undefined) continue;

    let value = rawValue.trim();
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }
    process.env[key] = value;
  }
}

function parseArgs(argv) {
  const args = {};
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (!arg.startsWith('--')) continue;
    const key = arg.slice(2);
    const next = argv[index + 1];
    if (!next || next.startsWith('--')) {
      args[key] = true;
      continue;
    }
    args[key] = next;
    index += 1;
  }
  return args;
}

function numberArg(args, key, fallback) {
  const value = args[key] ?? process.env[`MAILCHIMP_IMPORT_${key.replaceAll('-', '_').toUpperCase()}`];
  if (value === undefined) return fallback;
  const number = Number(value);
  if (!Number.isFinite(number)) {
    throw new Error(`Invalid --${key}: ${value}`);
  }
  return number;
}

function requiredString(value, message) {
  if (!value || !String(value).trim()) {
    throw new Error(message);
  }
  return String(value).trim();
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function invokeBatch({ endpoint, authToken, apiKey, listId, limit, offset, dryRun }) {
  const headers = {
    Authorization: `Bearer ${authToken}`,
    'Content-Type': 'application/json',
  };
  if (apiKey) headers.apikey = apiKey;

  const response = await fetch(endpoint, {
    method: 'POST',
    headers,
    body: JSON.stringify({
      action: 'import',
      list_id: listId,
      limit,
      offset,
      dry_run: dryRun,
    }),
  });

  const text = await response.text();
  let payload;
  try {
    payload = text ? JSON.parse(text) : {};
  } catch {
    payload = { raw: text };
  }

  if (!response.ok || payload?.error) {
    const details = typeof payload?.error === 'string' ? payload.error : JSON.stringify(payload);
    throw new Error(`Batch offset=${offset} limit=${limit} failed: HTTP ${response.status} ${details}`);
  }

  return payload;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const envFiles = [
    args['env-file'] ? resolve(String(args['env-file'])) : null,
    resolve(process.cwd(), '.env'),
    resolve(process.cwd(), '.env.local'),
    resolve(process.cwd(), '..', '.env'),
  ].filter(Boolean);

  for (const envFile of envFiles) {
    loadEnvFile(envFile);
  }

  const supabaseUrl = requiredString(
    args['supabase-url'] ?? process.env.SUPABASE_URL ?? process.env.VITE_SUPABASE_URL,
    'Set SUPABASE_URL or pass --supabase-url',
  ).replace(/\/$/, '');
  const listId = requiredString(
    args['list-id'] ?? process.env.MAILCHIMP_LIST_ID,
    'Set MAILCHIMP_LIST_ID or pass --list-id',
  );
  const authToken = requiredString(
    args['auth-token'] ?? process.env.SUPABASE_FUNCTION_AUTH_TOKEN ?? process.env.SUPABASE_SERVICE_ROLE_KEY,
    'Set SUPABASE_FUNCTION_AUTH_TOKEN/SUPABASE_SERVICE_ROLE_KEY or pass --auth-token',
  );

  const apiKey = args.apikey ?? process.env.SUPABASE_ANON_KEY ?? process.env.VITE_SUPABASE_PUBLISHABLE_KEY ?? '';
  const functionName = args.function ?? DEFAULT_FUNCTION_NAME;
  const endpoint = `${supabaseUrl}/functions/v1/${functionName}`;
  const batchSize = Math.max(1, Math.min(numberArg(args, 'batch-size', 50), 1000));
  const startOffset = Math.max(0, numberArg(args, 'start-offset', 0));
  const stopOffset = Math.max(startOffset, numberArg(args, 'stop-offset', Number.MAX_SAFE_INTEGER));
  const delayMs = Math.max(0, numberArg(args, 'delay-ms', 750));
  const dryRun = Boolean(args['dry-run']);

  console.log(JSON.stringify({
    endpoint,
    listId,
    batchSize,
    startOffset,
    stopOffset: stopOffset === Number.MAX_SAFE_INTEGER ? null : stopOffset,
    delayMs,
    dryRun,
  }, null, 2));

  let offset = startOffset;
  const totals = {
    scanned: 0,
    created: 0,
    updated: 0,
    linked: 0,
    skipped: 0,
    errors: 0,
  };

  while (offset < stopOffset) {
    const limit = Math.min(batchSize, stopOffset - offset);
    const payload = await invokeBatch({ endpoint, authToken, apiKey, listId, limit, offset, dryRun });
    const stats = payload?.stats?.import ?? {};

    for (const key of Object.keys(totals)) {
      totals[key] += Number(stats[key] ?? 0);
    }

    console.log([
      `offset=${offset}`,
      `scanned=${stats.scanned ?? 0}`,
      `created=${stats.created ?? 0}`,
      `updated=${stats.updated ?? 0}`,
      `linked=${stats.linked ?? 0}`,
      `skipped=${stats.skipped ?? 0}`,
      `errors=${stats.errors ?? 0}`,
      `run=${payload.run_id ?? '-'}`,
    ].join(' '));

    const scanned = Number(stats.scanned ?? 0);
    if (scanned < limit) break;
    offset += limit;
    if (delayMs > 0 && offset < stopOffset) await sleep(delayMs);
  }

  console.log(`done next_offset=${offset}`);
  console.log(JSON.stringify(totals, null, 2));
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
});

// Token acquisition for the AI smoke harness.
//
// Precedence:
//   1. AI_SMOKE_TOKEN env var (use a token you already have)
//   2. Mint a fresh JWT via `rails runner mint_token.rb` for a seeded user
//      (AI_SMOKE_USER, default admin@powernode.org)
//
// The token is returned to the caller in memory and is NEVER written to logs
// or the findings report (crypto-safety: no credential material in output).

import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const SERVER_DIR = path.resolve(HERE, '../../server');
const MINT_SCRIPT = path.join(HERE, 'mint_token.rb');

/**
 * @param {{ user?: string }} [opts]
 * @returns {string} bearer token (raw JWT, no "Bearer " prefix)
 */
export function getToken({ user } = {}) {
  if (process.env.AI_SMOKE_TOKEN) {
    return process.env.AI_SMOKE_TOKEN.trim();
  }

  const env = { ...process.env };
  if (user) env.AI_SMOKE_USER = user;

  let out;
  try {
    out = execFileSync('bundle', ['exec', 'rails', 'runner', MINT_SCRIPT], {
      cwd: SERVER_DIR,
      env,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
      timeout: 180000,
    });
  } catch (err) {
    const stderr = (err.stderr || '').toString();
    if (stderr.includes('AI_SMOKE_NO_USER')) {
      throw new Error(
        `Seeded user "${user || 'admin@powernode.org'}" not found. ` +
          'Set AI_SMOKE_USER to an existing user or run `cd server && rails db:seed`.',
      );
    }
    const tail = stderr.split('\n').filter(Boolean).slice(-6).join('\n');
    throw new Error(`Failed to mint token via rails runner: ${err.message}\n${tail}`);
  }

  const line = out.split('\n').find((l) => l.startsWith('TOKEN:'));
  if (!line) {
    throw new Error('Token minting produced no TOKEN: line — is the backend environment healthy?');
  }
  return line.slice('TOKEN:'.length).trim();
}

'use strict';

/**
 * Per-run E2E login provisioner.
 *
 * Establishes known passwords for the seeded test users WITHOUT any credentials
 * file on disk. It:
 *   1. mints a short-lived admin JWT via `rails runner` (e2e_login_ids.rb),
 *   2. calls the real production endpoint POST /api/v1/users/:id/reset_password
 *      for each user (permission-gated, audit-logged; returns a compliant
 *      temporary_password), capturing each password IN MEMORY only.
 *
 * Returns { [role]: { email, password } } for demo/admin/manager/billing/member.
 *
 * Parallel/CI safety: if E2E_LOGINS (JSON) is already set in the environment,
 * it is used verbatim and NOTHING is re-provisioned — so a wrapper can provision
 * once and share the result across cypress-split workers (each worker running a
 * fresh reset would otherwise invalidate the others' cached logins). The CLI
 * entrypoint prints that JSON so a wrapper can do:
 *   export E2E_LOGINS="$(node scripts/e2e/provision-test-logins.cjs)"
 *
 * No secret (JWT or password) is ever logged by this module.
 */

const { execFileSync } = require('child_process');
const http = require('http');
const https = require('https');
const path = require('path');

const API_BASE = process.env.E2E_API_URL || 'http://localhost:3000';
const SERVER_DIR = path.resolve(__dirname, '..', '..', 'server');
const ROLES = ['demo', 'admin', 'manager', 'billing', 'member'];

function mintTokenAndIds() {
  const out = execFileSync(
    'bundle',
    ['exec', 'rails', 'runner', path.join(__dirname, 'e2e_login_ids.rb')],
    { cwd: SERVER_DIR, encoding: 'utf-8', stdio: ['ignore', 'pipe', 'inherit'] }
  );
  let token = null;
  const users = {};
  for (const line of out.split('\n')) {
    if (line.startsWith('TOKEN:')) {
      token = line.slice('TOKEN:'.length).trim();
    } else if (line.startsWith('USER:')) {
      const parts = line.slice('USER:'.length).split(':');
      const role = parts[0];
      const id = parts[1];
      const email = parts.slice(2).join(':');
      if (role && id && email) users[role] = { id, email };
    }
  }
  if (!token) throw new Error('provision-test-logins: failed to mint admin token (backend/env?)');
  return { token, users };
}

function resetPassword(token, id) {
  return new Promise((resolve, reject) => {
    const url = new URL(`${API_BASE}/api/v1/users/${id}/reset_password`);
    const client = url.protocol === 'https:' ? https : http;
    const req = client.request(
      {
        method: 'POST',
        hostname: url.hostname,
        port: url.port || (url.protocol === 'https:' ? 443 : 80),
        path: url.pathname,
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/json',
          'Content-Length': 2,
        },
        rejectUnauthorized: false, // local/self-signed E2E backends
      },
      (res) => {
        let body = '';
        res.on('data', (c) => (body += c));
        res.on('end', () => {
          let pw;
          try {
            pw = JSON.parse(body)?.data?.temporary_password;
          } catch (_e) {
            /* fall through to status check */
          }
          if (res.statusCode === 200 && pw) resolve(pw);
          else reject(new Error(`reset_password ${id} -> HTTP ${res.statusCode}`));
        });
      }
    );
    req.on('error', reject);
    req.end('{}');
  });
}

async function provisionTestLogins() {
  if (process.env.E2E_LOGINS) {
    try {
      return JSON.parse(process.env.E2E_LOGINS);
    } catch (_e) {
      /* malformed → provision fresh below */
    }
  }

  const { token, users } = mintTokenAndIds();
  const logins = {};
  for (const role of ROLES) {
    const u = users[role];
    if (!u) continue;
    // eslint-disable-next-line no-await-in-loop
    const password = await resetPassword(token, u.id);
    logins[role] = { email: u.email, password };
  }
  if (Object.keys(logins).length === 0) {
    throw new Error('provision-test-logins: no test users found (seed demo users first)');
  }
  return logins;
}

module.exports = { provisionTestLogins };

if (require.main === module) {
  provisionTestLogins()
    .then((logins) => process.stdout.write(JSON.stringify(logins)))
    .catch((err) => {
      process.stderr.write(`${(err && err.message) || err}\n`);
      process.exit(1);
    });
}

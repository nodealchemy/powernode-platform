#!/usr/bin/env node
// AI frontend-actions smoke harness.
//
// Replays the requests the React frontend makes against every core AI domain,
// classifies the responses, and writes a severity-ranked findings report. It is
// non-destructive by construction: reads of pre-existing data, and full
// create->edit->delete lifecycles only on namespaced fixtures it owns.
//
// Usage:
//   node scripts/ai-smoke/run.mjs [--phase read|write|all] [--domain a,b,c]
//       [--base-url URL] [--user EMAIL] [--no-cleanup] [--timeout MS]
//       [--md PATH] [--json PATH] [--quiet]
//
// Exit code is the number of findings (0 = clean), capped at 250.

import { getToken } from './auth.mjs';
import { buildManifest } from './manifest.mjs';
import { writeReport } from './report.mjs';

// ----------------------------------------------------------------- arg parsing
function parseArgs(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (!a.startsWith('--')) continue;
    const key = a.slice(2);
    if (key.startsWith('no-')) { out[key.slice(3)] = false; continue; }
    const next = argv[i + 1];
    if (next === undefined || next.startsWith('--')) { out[key] = true; }
    else { out[key] = next; i++; }
  }
  return out;
}

const args = parseArgs(process.argv.slice(2));
const BASE_URL = (args['base-url'] || process.env.AI_SMOKE_BASE_URL || 'http://localhost:3000/api/v1').replace(/\/$/, '');
const PHASE = args.phase || 'read'; // read | write | all
const ONLY = args.domain ? String(args.domain).split(',').map((s) => s.trim()) : null;
const CLEANUP = args.cleanup !== false; // --no-cleanup disables
const TIMEOUT = Number(args.timeout || 20000);
const QUIET = !!args.quiet;
const RUN_ID = `${Date.now().toString(36)}${Math.floor(Math.random() * 1e4).toString(36)}`;

const log = (...a) => { if (!QUIET) process.stderr.write(a.join(' ') + '\n'); };

// --------------------------------------------------------------- http + helpers
const results = [];

function isOk(status, expect) {
  if (Array.isArray(expect) && expect.includes(status)) return true;
  return status >= 200 && status < 300;
}

async function call(domain, action, method, path, body, expect) {
  const url = `${BASE_URL}${path}`;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TIMEOUT);
  const started = Date.now();
  const rec = { domain, action, method, path };
  try {
    const res = await fetch(url, {
      method,
      headers: {
        Authorization: `Bearer ${TOKEN}`,
        'Content-Type': 'application/json',
        Accept: 'application/json',
      },
      body: body !== undefined ? JSON.stringify(body) : undefined,
      signal: controller.signal,
    });
    const text = await res.text();
    rec.status = res.status;
    rec.ms = Date.now() - started;
    rec.ok = isOk(res.status, expect);
    let json;
    try { json = text ? JSON.parse(text) : undefined; } catch { /* non-json */ }
    rec.json = json;
    if (!rec.ok) rec.body = (text || '').slice(0, 800);
    results.push(rec);
    return rec;
  } catch (err) {
    rec.status = 0;
    rec.ms = Date.now() - started;
    rec.ok = false;
    rec.body = err.name === 'AbortError' ? `timeout after ${TIMEOUT}ms` : String(err.message || err);
    results.push(rec);
    return rec;
  } finally {
    clearTimeout(timer);
  }
}

function getPath(obj, keys) {
  return keys.reduce((acc, k) => (acc == null ? acc : acc[k]), obj);
}

// Find the first record id/slug from a list response of unknown shape.
function extractId(json) {
  if (!json) return null;
  const payload = json.data ?? json;
  const candidates = [];
  if (Array.isArray(payload)) candidates.push(payload);
  if (payload && typeof payload === 'object') {
    if (Array.isArray(payload.items)) candidates.push(payload.items);
    for (const v of Object.values(payload)) if (Array.isArray(v)) candidates.push(v);
  }
  for (const arr of candidates) {
    const first = arr.find((x) => x && typeof x === 'object' && (x.id || x.slug));
    if (first) return first.id || first.slug;
  }
  return null;
}

// ------------------------------------------------------------------- main flow
let TOKEN;
try {
  log(`# ai-smoke run ${RUN_ID} | phase=${PHASE} | base=${BASE_URL}`);
  log('# acquiring token…');
  TOKEN = getToken({ user: args.user });
} catch (err) {
  process.stderr.write(`\nAUTH ERROR: ${err.message}\n`);
  process.exit(255);
}

const manifest = buildManifest(RUN_ID);

for (const [key, dom] of Object.entries(manifest)) {
  if (ONLY && !ONLY.includes(key)) continue;
  log(`\n## ${dom.label} (${key})`);

  // READ ------------------------------------------------------------------
  for (const a of dom.read || []) {
    const r = await call(key, a.id, a.method, a.path, undefined, a.expect);
    log(`  read ${a.id.padEnd(20)} ${r.status} ${r.ok ? 'ok' : 'FAIL'}`);
  }

  // SAMPLE ----------------------------------------------------------------
  if (dom.sample) {
    const listRes = await call(key, 'sample.list', 'GET', dom.sample.listPath);
    const id = listRes.ok ? extractId(listRes.json) : null;
    if (!id) {
      results.push({ domain: key, action: 'sample', method: 'GET', path: dom.sample.listPath, status: listRes.status, ok: true, skipped: true, note: listRes.ok ? 'no records to sample' : 'list failed' });
      log(`  sample ${' '.padEnd(19)} skipped (${listRes.ok ? 'empty list' : 'list failed'})`);
    } else {
      for (const s of dom.sample.steps(id)) {
        const r = await call(key, `sample.${s.id}`, s.method, s.path, s.body, s.expect);
        log(`  sample ${s.id.padEnd(18)} ${r.status} ${r.ok ? 'ok' : 'FAIL'}`);
      }
    }
  }

  // WRITE LIFECYCLE -------------------------------------------------------
  if ((PHASE === 'write' || PHASE === 'all') && dom.lifecycle) {
    const c = dom.lifecycle.create;
    // create.body may be a function when the fixture needs a runtime dependency
    // (e.g. an agent needs an existing provider id). It receives a `firstId`
    // helper that GETs a list path and returns the first record's id.
    let createBody = c.body;
    if (typeof createBody === 'function') {
      const helpers = { firstId: async (p) => extractId((await call(key, `lifecycle.resolve ${p}`, 'GET', p)).json) };
      createBody = await createBody(helpers);
    }
    const created = await call(key, 'lifecycle.create', c.method, c.path, createBody, c.expect);
    const newId = created.ok ? getPath(created.json?.data ?? created.json, c.idPath) : null;
    log(`  write  ${'create'.padEnd(18)} ${created.status} ${created.ok ? 'ok' : 'FAIL'}`);
    if (newId) {
      try {
        for (const s of dom.lifecycle.steps(newId)) {
          const r = await call(key, `lifecycle.${s.id}`, s.method, typeof s.path === 'function' ? s.path(newId) : s.path, s.body, s.expect);
          log(`  write  ${s.id.padEnd(18)} ${r.status} ${r.ok ? 'ok' : 'FAIL'}`);
        }
      } finally {
        if (CLEANUP && dom.lifecycle.destroy) {
          const d = dom.lifecycle.destroy;
          const r = await call(key, 'lifecycle.destroy', d.method, typeof d.path === 'function' ? d.path(newId) : d.path, d.body, d.expect);
          log(`  write  ${'destroy'.padEnd(18)} ${r.status} ${r.ok ? 'ok' : 'FAIL'}${CLEANUP ? '' : ' (kept)'}`);
        } else if (!CLEANUP) {
          log(`  write  fixture kept: ${key} ${newId}`);
        }
      }
    }
  }
}

// ----------------------------------------------------------------- reporting
const summary = writeReport(results, {
  runId: RUN_ID,
  baseUrl: BASE_URL,
  phase: PHASE,
  domains: ONLY || Object.keys(manifest),
  mdPath: args.md,
  jsonPath: args.json,
});

process.stderr.write(
  `\n# done: ${summary.total} calls | ${summary.passed} ok | ${summary.skipped} skipped | ${summary.findings} findings` +
    `\n# report: ${summary.mdPath}\n`,
);
if (summary.findings > 0) {
  process.stderr.write('# severity: ' + JSON.stringify(summary.bySeverity) + '\n');
}

process.exit(Math.min(summary.findings, 250));

#!/usr/bin/env node
// UI smoke crawler — the browser twin of scripts/ai-smoke/.
//
// Logs in via the UI (the access token lives in Redux, not localStorage, so we
// can't inject it), BFS-crawls every reachable /app route headless, and reports
// per route:
//   - frontend errors: uncaught JS (pageerror) + console.error
//   - backend errors:  any 4xx/5xx HTTP response triggered by the page
// Writes a severity-ranked report (md + json). Exit 1 if any critical/high.
//
// Usage:
//   UI_SMOKE_PASSWORD=... node scripts/ui-smoke/crawl.mjs
//   UI_SMOKE_BASE_URL=https://dev.powernode.org UI_SMOKE_EMAIL=admin@powernode.org \
//     UI_SMOKE_PASSWORD=... node scripts/ui-smoke/crawl.mjs --max 150 --md /tmp/ui.md
//
// Browser binaries are already cached (~/.cache/ms-playwright). Requires
// @playwright/test (a devDependency of frontend/).

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(HERE, '..', '..');
// @playwright/test is a frontend/ devDependency; this script lives under
// scripts/ (no node_modules of its own), so resolve it from frontend/.
const { chromium } = createRequire(path.join(HERE, '..', '..', 'frontend', 'package.json'))('@playwright/test');
const arg = (flag) => { const i = process.argv.indexOf(flag); return i >= 0 ? process.argv[i + 1] : null; };

const BASE = (process.env.UI_SMOKE_BASE_URL || 'https://dev.powernode.org').replace(/\/$/, '');
const EMAIL = process.env.UI_SMOKE_EMAIL || 'admin@powernode.org';
const PASSWORD = process.env.UI_SMOKE_PASSWORD;
const MAX_ROUTES = Number(arg('--max') || 200);
const NAV_TIMEOUT = Number(arg('--timeout') || 20000);
const DETAIL_SAMPLE = Number(arg('--detail-sample') || 2); // max …/<uuid> pages crawled per listing
const MD_PATH = arg('--md') || path.join(HERE, 'last-report.md');
const JSON_PATH = arg('--json') || MD_PATH.replace(/\.md$/, '.json');

if (!PASSWORD) {
  console.error('UI_SMOKE_PASSWORD is required (the crawler logs in via the UI).');
  process.exit(2);
}

// Tolerable noise — not a real finding.
const IGNORE = [
  /favicon/i,
  /Failed to load resource/i,        // the generic browser line; the real status is captured separately
  /ResizeObserver loop/i,
  /\/api\/v1\/baas\//,               // BaaS 401 is expected when no tenant is provisioned
  /web-vitals|analytics|hotjar/i,
];
const ignored = (s) => IGNORE.some((re) => re.test(String(s)));

function severityOf(e) {
  if (e.http.some((h) => h.status >= 500)) return 'critical';   // backend 500
  if (e.pageerrors.length) return 'high';                       // uncaught JS exception
  if (e.http.some((h) => h.status >= 400)) return 'medium';     // 4xx (auth/not-found/validation)
  if (e.consoleErrors.length) return 'low';                     // console.error only
  return null;
}

async function login(page) {
  await page.goto(`${BASE}/login`, { waitUntil: 'domcontentloaded', timeout: NAV_TIMEOUT });
  await page.getByTestId('email-input').fill(EMAIL);
  await page.getByTestId('password-input').fill(PASSWORD);
  await Promise.all([
    page.waitForURL(/\/app(\/|$)/, { timeout: NAV_TIMEOUT }).catch(() => {}),
    page.getByTestId('login-submit-btn').click(),
  ]);
  if (!/\/app(\/|$)/.test(page.url())) {
    throw new Error(`login failed — still at ${page.url()} (check UI_SMOKE_EMAIL/PASSWORD)`);
  }
}

const collectLinks = (page) =>
  page.$$eval('a[href^="/app"]', (as) =>
    Array.from(new Set(as.map((a) => a.getAttribute('href')).filter(Boolean)))
      .map((h) => h.split('#')[0].replace(/\/$/, '') || '/app'),
  );

// The sidebar is a collapsed accordion, so post-login DOM scraping only finds
// the section headers — not the leaf routes. Seed the queue deterministically
// from the nav config instead: core navigation.tsx + every extension's
// register.* (globbed generically — no extension named). BFS then discovers the
// in-page PathTabs / SubNavRail sub-routes once each page is actually visited.
function seedRoutes() {
  const files = [path.join(REPO_ROOT, 'frontend/src/shared/utils/navigation.tsx')];
  const extDir = path.join(REPO_ROOT, 'extensions');
  for (const name of safeReaddir(extDir)) {
    for (const f of ['register.ts', 'register.tsx']) {
      const p = path.join(extDir, name, 'frontend/src', f);
      if (fs.existsSync(p)) files.push(p);
    }
  }
  const routes = new Set(['/app']);
  for (const f of files) {
    let src = '';
    try { src = fs.readFileSync(f, 'utf8'); } catch { continue; }
    for (const m of src.matchAll(/(?:href|to|path):\s*['"`](\/app[^'"`]*)['"`]/g)) {
      const r = m[1].split('#')[0].replace(/\/$/, '');
      if (r && !r.includes(':') && !r.includes('*')) routes.add(r); // drop :param / wildcard templates
    }
  }
  return [...routes];
}

function safeReaddir(dir) {
  try { return fs.readdirSync(dir, { withFileTypes: true }).filter((d) => d.isDirectory()).map((d) => d.name); }
  catch { return []; }
}

async function run() {
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({ ignoreHTTPSErrors: true, viewport: { width: 1680, height: 1000 } });
  const page = await context.newPage();

  await login(page);
  await page.waitForTimeout(1200);

  // BFS over /app routes: seed from the nav config, discover tab sub-routes live.
  const seen = new Set();
  const seeds = seedRoutes();
  const queue = [];
  const findings = [];

  // Detail pages (…/<uuid>) discovered off listing pages are repetitive — sample
  // a few per parent listing rather than letting them devour the route budget.
  const UUID = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i;
  const detailPerParent = {};
  let detailDropped = 0;
  const enqueue = (l) => {
    if (!l || seen.has(l) || queue.includes(l)) return;
    if (UUID.test(l)) {
      const parent = l.slice(0, l.search(UUID));
      detailPerParent[parent] = (detailPerParent[parent] || 0) + 1;
      if (detailPerParent[parent] > DETAIL_SAMPLE) { detailDropped++; return; }
    }
    queue.push(l);
  };
  for (const l of [...seeds, ...(await collectLinks(page))]) enqueue(l);
  process.stderr.write(`seeded ${seeds.length} routes from nav config\n`);

  while (queue.length && seen.size < MAX_ROUTES) {
    const route = queue.shift();
    if (!route || seen.has(route)) continue;
    seen.add(route);

    const errs = { route, pageerrors: [], consoleErrors: [], http: [] };
    const onPageError = (e) => { if (!ignored(e.message)) errs.pageerrors.push(e.message); };
    const onConsole = (m) => { if (m.type() === 'error' && !ignored(m.text())) errs.consoleErrors.push(m.text()); };
    const onResponse = (r) => {
      const s = r.status();
      if (s >= 400 && !ignored(r.url())) errs.http.push({ status: s, url: r.url().replace(BASE, '') });
    };
    page.on('pageerror', onPageError);
    page.on('console', onConsole);
    page.on('response', onResponse);

    try {
      await page.goto(`${BASE}${route}`, { waitUntil: 'domcontentloaded', timeout: NAV_TIMEOUT });
      // Best-effort settle so API calls fire; WebSocket/polling pages never reach
      // 'networkidle', so cap the wait and fall through to a fixed dwell.
      await page.waitForLoadState('networkidle', { timeout: 4000 }).catch(() => {});
      await page.waitForTimeout(1200);
      for (const l of await collectLinks(page)) enqueue(l);
    } catch (e) {
      errs.pageerrors.push(`navigation: ${e.message}`);
    }

    page.off('pageerror', onPageError);
    page.off('console', onConsole);
    page.off('response', onResponse);

    const severity = severityOf(errs);
    if (severity) findings.push({ ...errs, severity });
    process.stderr.write(`${severity ? `[${severity}]`.padEnd(11) : 'ok'.padEnd(11)}${route}\n`);
  }

  await browser.close();
  if (detailDropped) process.stderr.write(`(sampled detail pages: dropped ${detailDropped} …/<uuid> routes beyond ${DETAIL_SAMPLE}/listing)\n`);
  writeReport([...seen], findings, { detail_pages_dropped: detailDropped });
}

function writeReport(routes, findings, extra = {}) {
  const rank = { critical: 0, high: 1, medium: 2, low: 3 };
  findings.sort((a, b) => rank[a.severity] - rank[b.severity] || a.route.localeCompare(b.route));
  const by_severity = findings.reduce((m, f) => ((m[f.severity] = (m[f.severity] || 0) + 1), m), {});
  const summary = { base: BASE, routes_crawled: routes.length, routes_with_findings: findings.length, by_severity, ...extra };

  fs.writeFileSync(JSON_PATH, JSON.stringify({ summary, findings }, null, 2));

  let md = `# UI smoke report\n\n- base: \`${BASE}\`\n- routes crawled: ${routes.length}\n`;
  md += `- routes with findings: ${findings.length}\n- by severity: ${JSON.stringify(by_severity)}\n`;
  if (extra.detail_pages_dropped) md += `- detail pages sampled (dropped ${extra.detail_pages_dropped} \`…/<uuid>\` beyond ${DETAIL_SAMPLE}/listing)\n`;
  md += '\n';
  for (const f of findings) {
    md += `## [${f.severity}] \`${f.route}\`\n`;
    for (const h of f.http) md += `- HTTP ${h.status} \`${h.url}\`\n`;
    for (const e of f.pageerrors) md += `- uncaught: ${e}\n`;
    for (const e of f.consoleErrors) md += `- console.error: ${e}\n`;
    md += '\n';
  }
  fs.writeFileSync(MD_PATH, md);

  console.log(`\nReport: ${MD_PATH}\n${JSON.stringify(summary, null, 2)}`);
  process.exit(findings.some((f) => f.severity === 'critical' || f.severity === 'high') ? 1 : 0);
}

run().catch((e) => {
  console.error(`ui-smoke failed: ${e.message}`);
  process.exit(1);
});

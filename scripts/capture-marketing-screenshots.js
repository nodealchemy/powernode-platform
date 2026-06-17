#!/usr/bin/env node
/* eslint-disable no-console */
// Captures still-image screenshots for the public marketing site
// (HomePage, FeaturesPage, PricingPage) plus operator-UX surfaces
// (Fleet Dashboard, Template Composer, AI Concierge, Knowledge Graph
// visualizer) referenced by the marketing pages.
//
// Output: frontend/public/screenshots/<slug>.png at 1920x1080.
// Marketing pages reference via URL `/screenshots/<slug>.png`.
//
// Usage:
//   cd <repo-root>
//   node scripts/capture-marketing-screenshots.js
//
// Pre-reqs:
//   - Frontend dev server reachable at http://localhost:3001
//   - Backend reachable at http://localhost:3000
//   - Admin user exists with the credentials below

const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');

const BASE = process.env.POWERNODE_BASE_URL || 'http://localhost:3001';
const SCREENSHOTS_DIR = path.join(__dirname, '..', 'frontend', 'public', 'screenshots');
const VIEWPORT = { width: 1920, height: 1080 };

const ADMIN_EMAIL = process.env.POWERNODE_ADMIN_EMAIL || 'admin@powernode.org';
const ADMIN_PASSWORD = process.env.POWERNODE_ADMIN_PASSWORD || 'Fwhf7j-v5z92HL0OZqPRVq_1';

// Demo Company user — used for KG + AI Agents captures because the dev
// admin account has private-extension data that would leak into the
// public marketing site per feedback_no_private_extension_names_in_public_docs.
// Demo Company is a clean account seeded by
// extensions/marketing/server/db/seeds/marketing_demo_data_seed.rb.
const DEMO_EMAIL = process.env.POWERNODE_DEMO_EMAIL || 'demo@powernode.org';
const DEMO_PASSWORD = process.env.POWERNODE_DEMO_PASSWORD || 'Fwhf7j-v5z92HL0OZqPRVq_1';

// Marketing pages first (no auth, SPA-navigated — see notes), then
// operator UX (auth required, full page.goto)
//
// IMPORTANT: marketing public routes (/, /features, /pricing, /docs) are
// registered async by the marketing extension's frontend register(). On a
// fresh page.goto(), App.tsx renders before extensions register, so the
// catch-all `*` route redirects unknown paths through / → /welcome
// (WelcomePage). To avoid that, we warm up with one page.goto('/') to
// trigger the async extension load, then SPA-navigate to each marketing
// URL via history.pushState + popstate event so React Router resolves
// against the freshly-populated featureRegistry without remounting.
const CAPTURES = [
  { slug: 'marketing-homepage', url: '/', settle: 3000, spa: true },
  { slug: 'marketing-features', url: '/features', settle: 2000, spa: true },
  { slug: 'marketing-pricing', url: '/pricing', settle: 2000, spa: true },
  { slug: 'fleet-dashboard', url: '/app/system/fleet', auth: 'admin', settle: 3000 },
  { slug: 'template-composer', url: '/app/system/templates/compose', auth: 'admin', settle: 3000 },
  { slug: 'sdwan-overview', url: '/app/system/sdwan', auth: 'admin', settle: 3000 },
  // Demo Company captures (clean account, no private-extension leak) for
  // the AI operator UX surfaces. Captured AFTER admin captures since each
  // login uses the current page context.
  { slug: 'ai-agents', url: '/app/ai/agents', auth: 'demo', settle: 3000 },
  { slug: 'ai-knowledge', url: '/app/ai/knowledge', auth: 'demo', settle: 3000 },
];

async function login(page, asUser /* 'admin' | 'demo' */) {
  const creds = asUser === 'demo'
    ? { email: DEMO_EMAIL, password: DEMO_PASSWORD }
    : { email: ADMIN_EMAIL, password: ADMIN_PASSWORD };
  console.log(`  → logging in as ${creds.email}`);

  // First log out to be safe if we're switching users
  await page.goto(`${BASE}/login`);
  await page.waitForLoadState('networkidle', { timeout: 15000 }).catch(() => {});

  // If already logged in, /login may redirect away — go again with explicit logout
  if (!page.url().includes('/login')) {
    console.log(`  → already authenticated; clearing session for switch`);
    await page.context().clearCookies();
    await page.evaluate(() => {
      try { localStorage.clear(); sessionStorage.clear(); } catch (_) {}
    });
    await page.goto(`${BASE}/login`);
    await page.waitForLoadState('networkidle', { timeout: 15000 }).catch(() => {});
  }

  const emailSel = 'input[type="email"], input[name="email"]';
  const passSel = 'input[type="password"], input[name="password"]';
  await page.waitForSelector(emailSel, { timeout: 10000 });
  await page.fill(emailSel, creds.email);
  await page.fill(passSel, creds.password);

  await page.click('button[type="submit"]');
  await page.waitForFunction(() => !window.location.pathname.startsWith('/login'),
    { timeout: 20000 }).catch(() => {});
  await page.waitForLoadState('networkidle', { timeout: 15000 }).catch(() => {});
  console.log(`  → login complete; now at ${page.url()}`);
}

(async () => {
  fs.mkdirSync(SCREENSHOTS_DIR, { recursive: true });
  console.log(`Output dir: ${SCREENSHOTS_DIR}`);
  console.log(`Base URL: ${BASE}`);
  console.log(`Viewport: ${VIEWPORT.width}x${VIEWPORT.height}`);

  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({
    viewport: VIEWPORT,
    deviceScaleFactor: 2, // retina-quality
  });
  const page = await context.newPage();

  // Warm-up: navigate to / so the extension loader runs and marketing
  // public routes register. The URL will end up at /welcome (catch-all
  // → / → /welcome before extensions register), but the extensions
  // finish loading during the wait, so subsequent SPA navigations
  // (pushState + popstate) will resolve against the populated registry.
  console.log('Warm-up: hitting / to trigger extension loading...');
  await page.goto(`${BASE}/`, { waitUntil: 'networkidle', timeout: 30000 }).catch(() => {});
  // Wait until a marketing-extension-registered link is visible,
  // signalling that the registry is populated.
  await page.waitForSelector('a[href="/features"], a[href="/pricing"]', { timeout: 20000 })
    .catch(() => console.log('  (warm-up: marketing link not detected — proceeding anyway)'));
  await page.waitForTimeout(2000);

  let currentUser = null;
  const results = [];

  for (const c of CAPTURES) {
    try {
      if (c.auth && c.auth !== currentUser) {
        await login(page, c.auth);
        currentUser = c.auth;
      }

      const target = `${BASE}${c.url}`;
      console.log(`Capturing ${c.slug} ← ${target}`);

      if (c.spa) {
        // SPA navigation — change URL without remounting App.tsx
        await page.evaluate((path) => {
          window.history.pushState({}, '', path);
          window.dispatchEvent(new PopStateEvent('popstate'));
        }, c.url);
        await page.waitForLoadState('networkidle', { timeout: 20000 }).catch(() => {});
        await page.waitForTimeout(c.settle || 2000);
      } else {
        await page.goto(target, { waitUntil: 'domcontentloaded', timeout: 30000 });
        await page.waitForLoadState('networkidle', { timeout: 20000 }).catch(() => {});
        await page.waitForTimeout(c.settle || 2000);

        // Defensive: if the catch-all redirected us off the target path,
        // navigate again now that extensions should be loaded.
        const landedUrl = new URL(page.url());
        const targetPath = c.url.split('?')[0];
        if (landedUrl.pathname !== targetPath) {
          console.log(`  ↻ landed on ${landedUrl.pathname} (expected ${targetPath}) — retrying`);
          await page.goto(target, { waitUntil: 'domcontentloaded', timeout: 30000 });
          await page.waitForLoadState('networkidle', { timeout: 20000 }).catch(() => {});
          await page.waitForTimeout(c.settle || 2000);
        }
      }

      const outPath = path.join(SCREENSHOTS_DIR, `${c.slug}.png`);
      await page.screenshot({ path: outPath, fullPage: false });
      const size = fs.statSync(outPath).size;
      console.log(`  ✓ saved ${(size / 1024).toFixed(0)} KB`);
      results.push({ slug: c.slug, status: 'ok', bytes: size });
    } catch (err) {
      console.error(`  ✗ failed: ${err.message}`);
      results.push({ slug: c.slug, status: 'failed', error: err.message });
    }
  }

  await browser.close();

  console.log('\n=== summary ===');
  for (const r of results) {
    console.log(`  ${r.status === 'ok' ? '✓' : '✗'} ${r.slug}${r.bytes ? ` (${(r.bytes / 1024).toFixed(0)} KB)` : ''}${r.error ? ` — ${r.error}` : ''}`);
  }
  const failed = results.filter(r => r.status !== 'ok').length;
  console.log(`\n${results.length - failed} of ${results.length} captured successfully`);
  process.exit(failed > 0 ? 1 : 0);
})().catch(err => {
  console.error('Fatal:', err);
  process.exit(2);
});

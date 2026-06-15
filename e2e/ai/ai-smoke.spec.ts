import { test, expect, Page, BrowserContext } from '@playwright/test';
import { execFileSync } from 'node:child_process';
import path from 'node:path';
import { ProvidersPage } from '../pages/ai/providers.page';
import { AgentsPage } from '../pages/ai/agents.page';
import { ConversationsPage } from '../pages/ai/conversations.page';
import { ROUTES } from '../fixtures/test-data';

/**
 * AI frontend interactive smoke — the browser-layer companion to the API-replay
 * harness (scripts/ai-smoke). The API harness catches backend contract bugs; this
 * catches the render/JS-error layer it can't see — e.g. a component that throws
 * when an endpoint returns an unexpected shape.
 *
 * Auth: rather than depend on the password login in e2e/global-setup.ts (whose
 * test-credentials.json passwords go stale after every db:seed), we mint a fresh
 * refresh-token cookie for a seeded user via `rails runner` — the same JWT
 * approach scripts/ai-smoke/auth.mjs uses. The token is never asserted/logged.
 */

function mintRefreshToken(): string {
  const serverDir = path.resolve(__dirname, '../../server');
  const code =
    'u = User.find_by(email: ENV["AI_SMOKE_USER"] || "admin@powernode.org"); ' +
    'abort("NO_USER") unless u; ' +
    'puts "RT:#{Security::JwtService.generate_user_tokens(u)[:refresh_token]}"';
  const out = execFileSync('bundle', ['exec', 'rails', 'runner', code], {
    cwd: serverDir,
    encoding: 'utf8',
    timeout: 180000,
  });
  const line = out.split('\n').find((l) => l.startsWith('RT:'));
  if (!line) throw new Error('Failed to mint refresh token for AI smoke spec');
  return line.slice(3).trim();
}

async function injectAuth(context: BrowserContext, refreshToken: string) {
  await context.addCookies([
    {
      name: 'refresh_token',
      value: refreshToken,
      domain: 'localhost',
      path: '/api/v1/auth',
      httpOnly: true,
      secure: false,
      sameSite: 'Strict',
    },
  ]);
}

// Collect uncaught exceptions + React error-boundary console errors for a page.
function trackErrors(page: Page): string[] {
  const errors: string[] = [];
  page.on('pageerror', (e) => errors.push(`pageerror: ${e.message}`));
  page.on('console', (m) => {
    if (m.type() === 'error') {
      const t = m.text();
      // Ignore benign network/console noise; keep real React/runtime errors.
      if (/the above error occurred|React will try to recreate|Uncaught|is not a function|cannot read prop/i.test(t)) {
        errors.push(`console: ${t}`);
      }
    }
  });
  return errors;
}

let refreshToken: string;
test.beforeAll(() => {
  refreshToken = mintRefreshToken();
});

test.describe('AI pages — interactive smoke', () => {
  test.beforeEach(async ({ context }) => {
    await injectAuth(context, refreshToken);
  });

  test('Providers page renders without uncaught JS errors', async ({ page }) => {
    const errors = trackErrors(page);
    const providers = new ProvidersPage(page);
    await providers.goto();
    await providers.waitForReady();
    await expect(page.locator('body')).toBeVisible();
    expect(page.url()).not.toContain('/login');
    expect(errors, errors.join(' | ')).toHaveLength(0);
  });

  test('Providers edit modal opens (the supported_models 422 flow)', async ({ page }) => {
    const errors = trackErrors(page);
    const providers = new ProvidersPage(page);
    await providers.goto();
    await providers.waitForReady();
    // Only if there is at least one provider card to edit.
    if ((await providers.getProviderCount()) > 0) {
      const editButton = page.locator('button:has-text("Edit"), [aria-label*="edit" i], [data-testid*="edit" i]').first();
      if ((await editButton.count()) > 0) {
        await editButton.click();
        await expect(page.locator('[role="dialog"], [class*="modal" i]').first()).toBeVisible({ timeout: 10000 });
      }
    }
    expect(errors, errors.join(' | ')).toHaveLength(0);
  });

  test('Agents page renders and create modal opens', async ({ page }) => {
    const errors = trackErrors(page);
    const agents = new AgentsPage(page);
    await agents.goto();
    await agents.waitForReady();
    await expect(page.locator('body')).toBeVisible();
    expect(page.url()).not.toContain('/login');
    if ((await agents.createAgentButton.count()) > 0) {
      await agents.clickCreateAgent();
      await expect(page.locator('[role="dialog"], [class*="modal" i]').first()).toBeVisible({ timeout: 10000 });
    }
    expect(errors, errors.join(' | ')).toHaveLength(0);
  });

  test('Conversations page renders without uncaught JS errors', async ({ page }) => {
    const errors = trackErrors(page);
    const conversations = new ConversationsPage(page);
    await conversations.goto();
    await conversations.waitForReady();
    await expect(page.locator('body')).toBeVisible();
    expect(page.url()).not.toContain('/login');
    expect(errors, errors.join(' | ')).toHaveLength(0);
  });

  // Render-smoke for the remaining AI pages — each must mount with no uncaught
  // JS errors. Routes come from the shared ROUTES fixture. The dashboards here
  // (analytics/monitoring/governance) consume the endpoints recently fixed, so
  // this is also a render-level regression guard for those views.
  const PAGE_ROUTES: Array<[string, string]> = [
    ['Analytics', ROUTES.analytics],
    ['Monitoring', ROUTES.monitoring],
    ['Governance', ROUTES.governance],
    ['Agent Teams', ROUTES.agentTeams],
    ['Knowledge', ROUTES.knowledge],
    ['Ralph Loops', ROUTES.ralphLoops],
    ['MCP', ROUTES.mcp],
    ['Memory', ROUTES.memory],
    ['Chat Channels', ROUTES.chatChannels],
    ['Model Router', ROUTES.modelRouter],
  ];

  for (const [name, route] of PAGE_ROUTES) {
    test(`${name} page renders without uncaught JS errors`, async ({ page }) => {
      const errors = trackErrors(page);
      await page.goto(route);
      await page.waitForLoadState('networkidle');
      await expect(page.locator('body')).toBeVisible();
      expect(page.url(), `redirected away from ${route}`).not.toContain('/login');
      expect(errors, errors.join(' | ')).toHaveLength(0);
    });
  }
});

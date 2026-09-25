import { test, expect, Page } from '@playwright/test';
import { ROUTES } from '../fixtures/test-data';

/**
 * AI → Control E2E Tests
 *
 * One page for what the Autonomy dashboard, the Governance page, the Security
 * and Audit dashboards and Approval Chains used to split: a rail of seven
 * leaves, each leaf with at most one row of path tabs, every view a URL.
 * Assertions target what ControlPage actually renders (its rail, tab links,
 * section headings), and every visit must mount without an uncaught error.
 */

const LEAVES = ['Approvals', 'Policies', 'Budgets', 'Safety', 'Trust & Lineage', 'Goals', 'Compliance Audit'];

async function open(page: Page, route: string) {
  await page.goto(route);
  await page.waitForLoadState('networkidle');
  await page.waitForSelector('main, [role="main"]', { timeout: 10000 });
}

const rail = (page: Page) => page.getByRole('navigation', { name: 'Control navigation' });

test.describe('AI Control', () => {
  let pageErrors: string[];

  test.beforeEach(async ({ page }) => {
    pageErrors = [];
    page.on('pageerror', (err) => pageErrors.push(err.message));
  });

  test.afterEach(() => {
    expect(pageErrors).toEqual([]);
  });

  test.describe('Page and rail', () => {
    test('opens on the first leaf the operator can use', async ({ page }) => {
      await open(page, ROUTES.control);
      await expect(page.getByRole('heading', { name: 'Control' })).toBeVisible();
      expect(page.url()).toMatch(/\/app\/ai\/control\/[a-z-]+/);
    });

    test('lists only Control leaves, in order', async ({ page }) => {
      await open(page, ROUTES.control);
      const labels = (await rail(page).getByRole('link').allTextContents()).map((t) => t.trim());
      expect(labels.length).toBeGreaterThan(0);
      expect(LEAVES.filter((l) => labels.includes(l))).toEqual(labels);
    });

    test('moves the URL when a leaf is chosen', async ({ page }) => {
      await open(page, ROUTES.control);
      const budgets = rail(page).getByRole('link', { name: 'Budgets' });
      if (await budgets.count() > 0) {
        await budgets.click();
        await expect(page).toHaveURL(/\/app\/ai\/control\/budgets$/);
        await expect(page.getByText('Agent Budgets')).toBeVisible();
      }
    });
  });

  test.describe('Approvals', () => {
    test('shows the queue tab at its own URL', async ({ page }) => {
      await open(page, ROUTES.controlApprovals);
      await expect(page).toHaveURL(/\/approvals\/queue/);
      await expect(page.getByRole('link', { name: 'Queue' })).toBeVisible();
    });
  });

  test.describe('Policies → Compliance rules', () => {
    test('shows compliance policies, violations and security events', async ({ page }) => {
      await open(page, ROUTES.controlComplianceRules);
      for (const section of ['Compliance policies', 'Violations', 'Security events']) {
        await expect(page.getByRole('region', { name: section })).toBeVisible();
      }
    });

    test('offers the security-event filters the server accepts', async ({ page }) => {
      await open(page, ROUTES.controlComplianceRules);
      const risk = page.getByRole('group', { name: 'Risk filter' });
      await expect(risk.getByRole('button')).toHaveText(['All', 'critical', 'high', 'medium', 'low']);
    });
  });

  test.describe('Safety', () => {
    test('points at Observability for circuit breakers instead of showing them', async ({ page }) => {
      await open(page, ROUTES.controlSafety);
      await expect(page.getByText('Circuit breakers live in Observability → Circuit Breakers.')).toBeVisible();
      await expect(page.getByRole('link', { name: /circuit/i })).toHaveCount(0);
    });

    test('shows agent identities and quarantine', async ({ page }) => {
      await open(page, ROUTES.controlIdentities);
      await expect(page.getByRole('region', { name: 'Agent identities' })).toBeVisible();
      await expect(page.getByRole('region', { name: 'Quarantine' })).toBeVisible();
    });
  });

  test.describe('Trust & Lineage', () => {
    test('shows trust scores or their empty state', async ({ page }) => {
      await open(page, ROUTES.controlTrust);
      await expect(page.getByRole('link', { name: 'Trust' })).toBeVisible();
      await expect(page.locator('body')).toContainText(/trust score|No trust scores available/i);
    });
  });

  test.describe('Compliance Audit', () => {
    test('shows the audit log with its date filter', async ({ page }) => {
      await open(page, ROUTES.controlAuditLog);
      await expect(page.getByLabel('Start date')).toBeVisible();
      await expect(page.getByLabel('End date')).toBeVisible();
    });

    test('shows the ASI compliance matrix', async ({ page }) => {
      await open(page, ROUTES.controlAsiCompliance);
      await expect(page.getByRole('link', { name: 'ASI compliance' })).toBeVisible();
    });
  });

  test.describe('Responsive Design', () => {
    test('renders on a mobile viewport', async ({ page }) => {
      await page.setViewportSize({ width: 375, height: 667 });
      await open(page, ROUTES.control);
      await expect(page.getByRole('heading', { name: 'Control' })).toBeVisible();
    });
  });
});

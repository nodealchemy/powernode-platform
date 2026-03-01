import { test as base, expect } from '@playwright/test';

/**
 * Auth fixture for Playwright tests
 *
 * Provides authenticated page context for tests that require login.
 * Uses stored auth state from global-setup.ts
 */

export interface TestFixtures {
  authenticatedPage: ReturnType<typeof base.extend>;
}

/**
 * Extended test with authentication
 */
export const test = base.extend<TestFixtures>({
  // Placeholder for future auth fixtures if needed
});

export { expect };

/**
 * Test user permissions required for AI tests
 */
export const AI_PERMISSIONS = [
  'ai.providers.view',
  'ai.providers.manage',
  'ai.agents.view',
  'ai.agents.create',
  'ai.agents.execute',
  'ai.agents.delete',
  'ai.workflows.view',
  'ai.workflows.create',
  'ai.workflows.execute',
  'ai.workflows.delete',
  'ai.conversations.view',
  'ai.conversations.create',
  'ai.conversations.delete',
  'ai.contexts.view',
  'ai.contexts.manage',
  'ai.analytics.view',
] as const;

/**
 * Wait for page to be ready after navigation
 */
export async function waitForPageReady(page: ReturnType<typeof base.extend>['page']) {
  // Wait for network to be idle
  await page.waitForLoadState('networkidle');

  // Wait for main content to be visible
  await page.waitForSelector('main, [role="main"], .main-content, #root', { timeout: 10000 });
}

/**
 * Assert page contains any of the given texts
 */
export async function assertContainsAny(page: ReturnType<typeof base.extend>['page'], texts: string[]) {
  const bodyText = await page.locator('body').textContent() || '';
  const found = texts.some(text => bodyText.toLowerCase().includes(text.toLowerCase()));
  expect(found, `Expected page to contain one of: ${texts.join(', ')}`).toBeTruthy();
}

/**
 * Assert page has any of the given elements
 */
export async function assertHasElement(page: ReturnType<typeof base.extend>['page'], selectors: string[]) {
  for (const selector of selectors) {
    const count = await page.locator(selector).count();
    if (count > 0) {
      return; // Found at least one element
    }
  }
  throw new Error(`Expected page to have one of: ${selectors.join(', ')}`);
}

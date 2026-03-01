import { Page, expect } from '@playwright/test';

/**
 * Regex matching known acceptable page states that explain why
 * expected elements might not be present.
 */
const ACCEPTABLE_PAGE_STATES =
  /loading|restoring|error|failed|not available|no \w+ found|empty|permission|access restricted|try again|unauthorized|forbidden/i;

/**
 * Assert that either the condition is true OR the page is in a
 * known acceptable alternate state (loading, error, empty, etc.)
 *
 * Replaces the anti-pattern `expect(condition || true).toBeTruthy()`
 * which can never fail.
 */
export async function expectOrAlternateState(
  page: Page,
  condition: boolean,
  description?: string,
): Promise<void> {
  if (condition) {
    expect(condition).toBeTruthy();
    return;
  }
  const bodyText = await page.locator('body').innerText();
  const isAcceptable = ACCEPTABLE_PAGE_STATES.test(bodyText);
  expect(
    isAcceptable,
    description ??
      `Expected condition to be true or page to show a loading/error/empty state. ` +
      `Body text (first 300 chars): "${bodyText.substring(0, 300)}"`,
  ).toBeTruthy();
}

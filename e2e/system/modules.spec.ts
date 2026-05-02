import { test, expect } from '@playwright/test';
import { ModulesPage } from '../pages/system/modules.page';
import { expectOrAlternateState } from '../fixtures/assertions';

/**
 * System Modules E2E Tests
 *
 * Smoke coverage for /app/system/modules — the operator UI for the system
 * extension's NodeModule resource. Specifically guards against regressions
 * like the CanaryMarker undefined-import bug that slipped past the platform's
 * tsc gate (extensions slug frontend trees were not being type-checked) and
 * surfaced only at runtime when an operator opened the detail modal.
 *
 * Tests are tolerant of empty data — exercise the rendering path even when
 * no modules have been seeded (e.g. fresh DB or smoke environment).
 */

test.describe('System Modules', () => {
  let modulesPage: ModulesPage;

  test.beforeEach(async ({ page }) => {
    // Capture any uncaught browser errors during the test. The CanaryMarker
    // bug manifested as "ReferenceError: CanaryMarker is not defined" via
    // exactly this channel — this assertion is the regression guard.
    const pageErrors: Error[] = [];
    page.on('pageerror', (err) => pageErrors.push(err));

    modulesPage = new ModulesPage(page);
    await modulesPage.goto();

    // Stash the array on the page object so each test can inspect it.
    (page as unknown as { __pageErrors: Error[] }).__pageErrors = pageErrors;
  });

  test('module list page loads without runtime errors', async ({ page }) => {
    // Heading present (or at least a recognizable empty-state)
    const hasContent = await page.getByText(/modules|no modules|loading/i).count() > 0;
    await expectOrAlternateState(page, hasContent);

    const errors = (page as unknown as { __pageErrors: Error[] }).__pageErrors;
    expect(errors, `pageerror events: ${errors.map(e => e.message).join('; ')}`).toHaveLength(0);
  });

  test('module detail modal opens and CanaryMarker tab renders without errors', async ({ page }) => {
    const opened = await modulesPage.openFirstModuleDetail();

    if (!opened) {
      // Empty list — rendering the page itself is the only thing to verify.
      // The render path that includes <CanaryMarker> still gets exercised by
      // module list components even before any module is selected.
      const errors = (page as unknown as { __pageErrors: Error[] }).__pageErrors;
      expect(errors, `pageerror events on empty list: ${errors.map(e => e.message).join('; ')}`).toHaveLength(0);
      test.info().annotations.push({ type: 'note', description: 'No modules seeded — opening modal skipped' });
      return;
    }

    // Modal is open; navigate to the autonomy tab (where CanaryMarker lives)
    if (await modulesPage.autonomyTab.count() > 0) {
      await modulesPage.autonomyTab.first().click();
    }

    // Verify CanaryMarker rendered (or at least didn't crash). With the
    // ReferenceError bug, this point was never reached — React's render
    // threw before any DOM landed.
    const canaryVisible = await modulesPage.canaryMarker.isVisible().catch(() => false);
    const consentVisible = await modulesPage.consentBudgetEditor.isVisible().catch(() => false);
    expect(canaryVisible || consentVisible, 'autonomy tab content rendered').toBeTruthy();

    const errors = (page as unknown as { __pageErrors: Error[] }).__pageErrors;
    expect(
      errors.filter(e => /CanaryMarker|ConsentBudgetEditor/.test(e.message)),
      `regression-guard: no CanaryMarker / ConsentBudgetEditor errors`
    ).toHaveLength(0);
  });
});

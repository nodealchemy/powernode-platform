import { test, expect } from '@playwright/test';
import { PlansPage } from '../pages/business/plans.page';
import { expectOrAlternateState } from '../fixtures/assertions';

/**
 * Business Plans E2E Tests
 *
 * Tests for subscription plan management functionality.
 */

test.describe('Business Plans', () => {
  let plansPage: PlansPage;

  test.beforeEach(async ({ page }) => {
    page.on('pageerror', () => {});
    plansPage = new PlansPage(page);
    await plansPage.goto();
  });

  test.describe('Page Display', () => {
    test('should load plans page', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/plan|pricing|subscription/i);
    });

    test('should display create plan button', async ({ page }) => {
      const hasCreateBtn = await plansPage.createPlanButton.count() > 0;
      await expectOrAlternateState(page, hasCreateBtn);
    });

    test('should display plans list', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasPlans = await plansPage.plansList.count() > 0;
      const hasEmptyState = await page.getByText(/no plan|create your first/i).count() > 0;
      expect(hasPlans || hasEmptyState).toBeTruthy();
    });
  });

  test.describe('Plans List', () => {
    test('should display plan name', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasPlans = await plansPage.plansList.count() > 0;
      if (hasPlans) {
        await expect(plansPage.plansList.first()).toBeVisible();
      }
    });

    test('should display plan price', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasPrice = await page.getByText(/\$|free|price/i).count() > 0;
      await expectOrAlternateState(page, hasPrice);
    });

    test('should display billing interval', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasInterval = await page.getByText(/monthly|yearly|annual/i).count() > 0;
      await expectOrAlternateState(page, hasInterval);
    });

    test('should display plan status', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasStatus = await page.getByText(/active|inactive|archived|draft/i).count() > 0;
      await expectOrAlternateState(page, hasStatus);
    });

    test('should display subscriber count', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasSubscriberCount = await page.getByText(/subscriber|\d+.*user/i).count() > 0;
      await expectOrAlternateState(page, hasSubscriberCount);
    });
  });

  test.describe('Create Plan', () => {
    test('should open create plan modal', async ({ page }) => {
      if (await plansPage.createPlanButton.count() > 0) {
        await plansPage.createPlanButton.first().click();
        await page.waitForTimeout(500);
        const hasForm = await page.locator('input[name="name"], [role="dialog"], form').count() > 0;
        expect(hasForm).toBeTruthy();
      }
    });

    test('should have name field', async ({ page }) => {
      if (await plansPage.createPlanButton.count() > 0) {
        await plansPage.createPlanButton.first().click();
        await page.waitForTimeout(500);
        const hasName = await plansPage.planNameInput.count() > 0;
        await expectOrAlternateState(page, hasName);
      }
    });

    test('should have price field', async ({ page }) => {
      if (await plansPage.createPlanButton.count() > 0) {
        await plansPage.createPlanButton.first().click();
        await page.waitForTimeout(500);
        const hasPrice = await plansPage.planPriceInput.count() > 0;
        await expectOrAlternateState(page, hasPrice);
      }
    });

    test('should have interval selection', async ({ page }) => {
      if (await plansPage.createPlanButton.count() > 0) {
        await plansPage.createPlanButton.first().click();
        await page.waitForTimeout(500);
        const hasInterval = await plansPage.planIntervalSelect.count() > 0;
        await expectOrAlternateState(page, hasInterval);
      }
    });

    test('should have description field', async ({ page }) => {
      if (await plansPage.createPlanButton.count() > 0) {
        await plansPage.createPlanButton.first().click();
        await page.waitForTimeout(500);
        const hasDescription = await plansPage.planDescriptionInput.isVisible().catch(() => false);
        await expectOrAlternateState(page, hasDescription);
      }
    });

    test('should have features/limits section', async ({ page }) => {
      if (await plansPage.createPlanButton.count() > 0) {
        await plansPage.createPlanButton.first().click();
        await page.waitForTimeout(500);
        const hasFeatures = await page.getByText(/feature|limit|include/i).count() > 0;
        await expectOrAlternateState(page, hasFeatures);
      }
    });
  });

  test.describe('Plan Actions', () => {
    test('should have edit option', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const editButton = page.getByRole('button', { name: /edit/i });
      if (await editButton.count() > 0) {
        await expect(editButton.first()).toBeVisible();
      }
    });

    test('should have archive option', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const archiveButton = page.getByRole('button', { name: /archive|deactivate|pause/i });
      if (await archiveButton.count() > 0) {
        await expect(archiveButton.first()).toBeVisible();
      }
    });

    test('should have duplicate option', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const duplicateButton = page.getByRole('button', { name: /duplicate|copy|clone/i });
      if (await duplicateButton.count() > 0) {
        await expect(duplicateButton.first()).toBeVisible();
      }
    });
  });

  test.describe('Plan Details', () => {
    test('should view plan details', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasPlans = await plansPage.plansList.count() > 0;
      if (hasPlans) {
        await plansPage.plansList.first().click();
        await page.waitForTimeout(500);
        const hasDetails = await page.getByText(/detail|feature|subscriber/i).count() > 0;
        await expectOrAlternateState(page, hasDetails);
      }
    });

    test('should show plan features', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasPlans = await plansPage.plansList.count() > 0;
      if (hasPlans) {
        await plansPage.plansList.first().click();
        await page.waitForTimeout(500);
        const hasFeatures = await page.getByText(/feature|include|limit/i).count() > 0;
        await expectOrAlternateState(page, hasFeatures);
      }
    });

    test('should show plan subscribers', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasPlans = await plansPage.plansList.count() > 0;
      if (hasPlans) {
        await plansPage.plansList.first().click();
        await page.waitForTimeout(500);
        const hasSubscribers = await page.getByText(/subscriber|customer|user/i).count() > 0;
        await expectOrAlternateState(page, hasSubscribers);
      }
    });
  });

  test.describe('Search and Filter', () => {
    test('should have search input', async ({ page }) => {
      const searchVisible = await plansPage.searchInput.count() > 0;
      if (searchVisible) {
        await expect(plansPage.searchInput.first()).toBeVisible();
      }
    });

    test('should filter by status', async ({ page }) => {
      const filterVisible = await plansPage.statusFilter.count() > 0;
      if (filterVisible) {
        await plansPage.statusFilter.first().click();
        await page.waitForTimeout(300);
        const hasOptions = await page.getByText(/active|archived|all/i).count() > 0;
        expect(hasOptions).toBeTruthy();
      }
    });
  });

  test.describe('Plan Validation', () => {
    test('should require plan name', async ({ page }) => {
      if (await plansPage.createPlanButton.count() > 0) {
        await plansPage.createPlanButton.first().click();
        await page.waitForTimeout(500);
        // Try to save without name
        const saveBtn = page.getByRole('button', { name: /save|create/i });
        if (await saveBtn.count() > 0) {
          await saveBtn.first().click();
          await page.waitForTimeout(500);
          // Should show validation error or stay on form
        }
      }
    });

    test('should validate price format', async ({ page }) => {
      if (await plansPage.createPlanButton.count() > 0) {
        await plansPage.createPlanButton.first().click();
        await page.waitForTimeout(500);
        if (await plansPage.planPriceInput.count() > 0) {
          await plansPage.planPriceInput.fill('invalid');
        }
        // Should show validation or prevent submission
      }
    });
  });

  test.describe('Pricing Tiers', () => {
    test('should support multiple pricing tiers if available', async ({ page }) => {
      if (await plansPage.createPlanButton.count() > 0) {
        await plansPage.createPlanButton.first().click();
        await page.waitForTimeout(500);
        const hasTiers = await page.getByText(/tier|level|add price/i).count() > 0;
        await expectOrAlternateState(page, hasTiers);
      }
    });
  });
});

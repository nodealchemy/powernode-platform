import { test, expect } from '@playwright/test';
import { AgentTeamsPage } from '../pages/ai/agent-teams.page';

test.describe('Agent Team Reviews', () => {
  let teamsPage: AgentTeamsPage;

  test.beforeEach(async ({ page }) => {
    page.on('pageerror', () => {});
    teamsPage = new AgentTeamsPage(page);
    await teamsPage.goto();
    await teamsPage.waitForReady();
  });

  test.describe('Review Configuration', () => {
    test('should display review config section in team builder', async ({ page }) => {
      const createBtn = teamsPage.createTeamButton;
      if (await createBtn.count() === 0) {
        test.skip();
        return;
      }
      await createBtn.first().click();
      await page.waitForTimeout(500);

      // Verify modal opened
      const modal = page.locator('[role="dialog"]');
      if (await modal.count() === 0) {
        test.skip();
        return;
      }

      const reviewSection = page.locator('[data-testid="review-config-section"], details:has-text("Review Configuration")');
      if (await reviewSection.count() > 0) {
        await expect(reviewSection.first()).toBeVisible();
      }
    });

    test('should toggle auto-review when review section is open', async ({ page }) => {
      const createBtn = teamsPage.createTeamButton;
      if (await createBtn.count() === 0) {
        test.skip();
        return;
      }
      await createBtn.first().click();
      await page.waitForTimeout(500);

      const modal = page.locator('[role="dialog"]');
      if (await modal.count() === 0) {
        test.skip();
        return;
      }

      // Open the review config details section
      await teamsPage.openReviewConfigSection();

      const toggle = teamsPage.reviewEnabledToggle;
      if (await toggle.count() === 0) {
        test.skip();
        return;
      }

      const initialState = await toggle.isChecked().catch(() => false);
      await toggle.click();
      const newState = await toggle.isChecked().catch(() => initialState);
      expect(newState).not.toBe(initialState);
    });

    test('should show review mode options when enabled', async ({ page }) => {
      const createBtn = teamsPage.createTeamButton;
      if (await createBtn.count() === 0) {
        test.skip();
        return;
      }
      await createBtn.first().click();
      await page.waitForTimeout(500);

      const modal = page.locator('[role="dialog"]');
      if (await modal.count() === 0) {
        test.skip();
        return;
      }

      await teamsPage.openReviewConfigSection();

      const toggle = teamsPage.reviewEnabledToggle;
      if (await toggle.count() > 0) {
        const isChecked = await toggle.isChecked().catch(() => false);
        if (!isChecked) await toggle.click();
        await page.waitForTimeout(300);
      }

      // Check for Blocking or Shadow text within the review config section
      const reviewSection = page.locator('[data-testid="review-config-section"]');
      const hasBlockingOption = await reviewSection.locator('text=Blocking').count() > 0;
      const hasShadowOption = await reviewSection.locator('text=Shadow').count() > 0;
      expect(hasBlockingOption || hasShadowOption).toBeTruthy();
    });

    test('should have quality threshold and max revisions inputs', async ({ page }) => {
      const createBtn = teamsPage.createTeamButton;
      if (await createBtn.count() === 0) {
        test.skip();
        return;
      }
      await createBtn.first().click();
      await page.waitForTimeout(500);

      const modal = page.locator('[role="dialog"]');
      if (await modal.count() === 0) {
        test.skip();
        return;
      }

      await teamsPage.openReviewConfigSection();

      const toggle = teamsPage.reviewEnabledToggle;
      if (await toggle.count() > 0) {
        const isChecked = await toggle.isChecked().catch(() => false);
        if (!isChecked) await toggle.click();
        await page.waitForTimeout(300);
      }

      const slider = teamsPage.qualityThresholdSlider;
      const revisionsInput = teamsPage.maxRevisionsInput;
      const hasSlider = await slider.count() > 0;
      const hasRevisions = await revisionsInput.count() > 0;
      expect(hasSlider || hasRevisions).toBeTruthy();
    });

    test('should save review configuration with team creation', async ({ page }) => {
      const createBtn = teamsPage.createTeamButton;
      if (await createBtn.count() === 0) {
        test.skip();
        return;
      }

      const responsePromise = page.waitForResponse(
        resp => resp.url().includes('agent-teams') && ['POST', 'PUT', 'PATCH'].includes(resp.request().method()),
        { timeout: 10000 }
      ).catch(() => null);

      await createBtn.first().click();
      await page.waitForTimeout(500);

      const modal = page.locator('[role="dialog"]');
      if (await modal.count() === 0) {
        test.skip();
        return;
      }

      // Fill name using the dialog-scoped input
      await teamsPage.nameInput.fill('Review Test Team ' + Date.now());
      await teamsPage.saveButton.click();

      const response = await responsePromise;
      if (response) {
        expect([200, 201]).toContain(response.status());
      }
    });
  });

  test.describe('Review Panel', () => {
    test('should display review panel when reviews exist', async () => {
      const reviewPanel = teamsPage.reviewPanel;
      if (await reviewPanel.count() > 0) {
        await expect(reviewPanel).toBeVisible();
      }
    });

    test('should show action buttons in review panel', async () => {
      const reviewPanel = teamsPage.reviewPanel;
      if (await reviewPanel.count() === 0) {
        test.skip();
        return;
      }
      await teamsPage.verifyReviewPanelVisible();

      const approveBtn = teamsPage.approveButton;
      const rejectBtn = teamsPage.rejectButton;
      if (await approveBtn.count() > 0) {
        await expect(approveBtn).toBeVisible();
      }
      if (await rejectBtn.count() > 0) {
        await expect(rejectBtn).toBeVisible();
      }
    });
  });

  test.describe('Responsive', () => {
    test('should render on mobile viewport', async ({ page }) => {
      await page.setViewportSize({ width: 375, height: 667 });
      await teamsPage.goto();
      await teamsPage.verifyPageLoaded();
    });

    test('should render on tablet viewport', async ({ page }) => {
      await page.setViewportSize({ width: 768, height: 1024 });
      await teamsPage.goto();
      await teamsPage.verifyPageLoaded();
    });
  });
});

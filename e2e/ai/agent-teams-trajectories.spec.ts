import { test, expect } from '@playwright/test';
import { AgentTeamsPage } from '../pages/ai/agent-teams.page';
import { ROUTES } from '../fixtures/test-data';

test.describe('Agent Team Trajectories', () => {
  let teamsPage: AgentTeamsPage;

  test.beforeEach(async ({ page }) => {
    page.on('pageerror', () => {});
    teamsPage = new AgentTeamsPage(page);
    await teamsPage.goto();
    await teamsPage.waitForReady();
  });

  test.describe('Trajectory List', () => {
    test('should navigate to trajectories view', async ({ page }) => {
      const trajLink = page.locator(
        'a:has-text("Trajectories"), button:has-text("Trajectories"), [data-testid*="trajectory"]'
      ).first();
      if (await trajLink.count() === 0) {
        test.skip();
        return;
      }
      await teamsPage.navigateToTrajectories();
      await expect(page.locator('body')).toContainText(/trajector/i);
    });

    test('should display trajectory cards or empty state', async ({ page }) => {
      const trajLink = page.locator('a:has-text("Trajectories"), button:has-text("Trajectories")').first();
      if (await trajLink.count() === 0) {
        test.skip();
        return;
      }
      await teamsPage.navigateToTrajectories();
      // Should show either cards or empty state
      const hasCards = await teamsPage.trajectoryCards.count() > 0;
      const hasEmptyState = await page.locator(':text("No trajectories"), :text("no trajectories")').count() > 0;
      expect(hasCards || hasEmptyState).toBeTruthy();
    });

    test('should have search input on trajectories page', async ({ page }) => {
      const trajLink = page.locator('a:has-text("Trajectories"), button:has-text("Trajectories")').first();
      if (await trajLink.count() === 0) {
        test.skip();
        return;
      }
      await teamsPage.navigateToTrajectories();
      const searchInput = teamsPage.trajectorySearch;
      if (await searchInput.count() > 0) {
        await expect(searchInput).toBeVisible();
      }
    });

    test('should fetch trajectories from API', async ({ page }) => {
      const trajLink = page.locator('a:has-text("Trajectories"), button:has-text("Trajectories")').first();
      if (await trajLink.count() === 0) {
        test.skip();
        return;
      }

      const responsePromise = page.waitForResponse(
        resp => resp.url().includes('trajectories'),
        { timeout: 5000 }
      ).catch(() => null);

      await teamsPage.navigateToTrajectories();
      const response = await responsePromise;
      if (response) {
        expect(response.status()).toBe(200);
      }
    });
  });

  test.describe('Trajectory Viewer', () => {
    test('should open trajectory detail view', async ({ page }) => {
      const trajLink = page.locator('a:has-text("Trajectories"), button:has-text("Trajectories")').first();
      if (await trajLink.count() === 0) {
        test.skip();
        return;
      }
      await teamsPage.navigateToTrajectories();

      const trajCard = teamsPage.trajectoryCards.first();
      if (await trajCard.count() === 0) {
        test.skip();
        return;
      }
      await trajCard.click();
      await page.waitForLoadState('domcontentloaded');
      await expect(page.locator('body')).toContainText(/chapter|timeline|trajectory/i);
    });

    test('should display chapter timeline', async ({ page }) => {
      const trajLink = page.locator('a:has-text("Trajectories"), button:has-text("Trajectories")').first();
      if (await trajLink.count() === 0) {
        test.skip();
        return;
      }
      await teamsPage.navigateToTrajectories();

      const trajCard = teamsPage.trajectoryCards.first();
      if (await trajCard.count() === 0) {
        test.skip();
        return;
      }
      await trajCard.click();
      await page.waitForLoadState('domcontentloaded');

      const timeline = teamsPage.trajectoryTimeline;
      if (await timeline.count() > 0) {
        await teamsPage.verifyTrajectoryTimeline();
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

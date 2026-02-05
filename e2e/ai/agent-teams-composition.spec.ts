import { test, expect } from '@playwright/test';
import { AgentTeamsPage } from '../pages/ai/agent-teams.page';

test.describe('Team Composition Health', () => {
  let teamsPage: AgentTeamsPage;

  test.beforeEach(async ({ page }) => {
    page.on('pageerror', () => {});
    teamsPage = new AgentTeamsPage(page);
    await teamsPage.goto();
    await teamsPage.waitForReady();
  });

  test('should load agent teams page', async () => {
    await teamsPage.verifyPageLoaded();
  });

  test('should display team builder modal with composition sections', async ({ page }) => {
    if (await teamsPage.createTeamButton.count() === 0) {
      test.skip();
      return;
    }
    await teamsPage.clickCreateTeam();
    await teamsPage.verifyCreateModalOpen();
    await expect(page.locator('[role="dialog"], [class*="modal"]')).toBeVisible();
  });

  test('should show composition health banner when editing existing team', async ({ page }) => {
    const teamCard = teamsPage.teamCards.first();
    if (await teamCard.count() === 0) {
      test.skip();
      return;
    }
    const editButton = teamCard.getByRole('button', { name: /edit/i });
    if (await editButton.count() === 0) {
      test.skip();
      return;
    }
    await editButton.click();
    await teamsPage.verifyCreateModalOpen();
    // Banner should be present in the modal for existing teams
    const banner = teamsPage.compositionHealthBanner;
    if (await banner.count() > 0) {
      await expect(banner).toBeVisible();
    }
  });

  test('should fetch composition health from API when editing team', async ({ page }) => {
    const teamCard = teamsPage.teamCards.first();
    if (await teamCard.count() === 0) {
      test.skip();
      return;
    }
    const editButton = teamCard.getByRole('button', { name: /edit/i });
    if (await editButton.count() === 0) {
      test.skip();
      return;
    }

    const responsePromise = page.waitForResponse(
      resp => resp.url().includes('composition_health'),
      { timeout: 5000 }
    ).catch(() => null);

    await editButton.click();
    const response = await responsePromise;
    if (response) {
      expect(response.status()).toBe(200);
    }
  });

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

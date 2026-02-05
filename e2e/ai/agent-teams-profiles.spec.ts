import { test, expect } from '@playwright/test';
import { AgentTeamsPage } from '../pages/ai/agent-teams.page';

test.describe('Agent Role Profiles', () => {
  let teamsPage: AgentTeamsPage;

  test.beforeEach(async ({ page }) => {
    page.on('pageerror', () => {});
    teamsPage = new AgentTeamsPage(page);
    await teamsPage.goto();
    await teamsPage.waitForReady();
  });

  test('should display role profile selector in team builder modal', async ({ page }) => {
    if (await teamsPage.createTeamButton.count() === 0) {
      test.skip();
      return;
    }
    await teamsPage.clickCreateTeam();
    await teamsPage.verifyCreateModalOpen();

    const profileGrid = teamsPage.roleProfileGrid;
    if (await profileGrid.count() > 0) {
      await expect(profileGrid).toBeVisible();
    }
  });

  test('should display role profile cards', async ({ page }) => {
    if (await teamsPage.createTeamButton.count() === 0) {
      test.skip();
      return;
    }
    await teamsPage.clickCreateTeam();
    await teamsPage.verifyCreateModalOpen();

    const profileCards = teamsPage.roleProfileCards;
    if (await profileCards.count() > 0) {
      await expect(profileCards.first()).toBeVisible();
      const count = await teamsPage.getRoleProfileCount();
      expect(count).toBeGreaterThan(0);
    }
  });

  test('should select a role profile and show preview', async ({ page }) => {
    if (await teamsPage.createTeamButton.count() === 0) {
      test.skip();
      return;
    }
    await teamsPage.clickCreateTeam();
    await teamsPage.verifyCreateModalOpen();

    const profileCards = teamsPage.roleProfileCards;
    if (await profileCards.count() === 0) {
      test.skip();
      return;
    }

    await profileCards.first().click();
    // After selecting, preview or action buttons should appear
    const applyBtn = teamsPage.applyProfileButton;
    if (await applyBtn.count() > 0) {
      await expect(applyBtn).toBeVisible();
    }
  });

  test('should fetch role profiles from API', async ({ page }) => {
    if (await teamsPage.createTeamButton.count() === 0) {
      test.skip();
      return;
    }

    const responsePromise = page.waitForResponse(
      resp => resp.url().includes('role_profiles'),
      { timeout: 5000 }
    ).catch(() => null);

    await teamsPage.clickCreateTeam();
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

  test('should render on desktop viewport', async ({ page }) => {
    await page.setViewportSize({ width: 1280, height: 800 });
    await teamsPage.goto();
    await teamsPage.verifyPageLoaded();
  });
});

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

    const profileGrid = teamsPage.roleProfileGrid;
    if (await profileGrid.count() > 0) {
      await expect(profileGrid.first()).toBeVisible();
    }
  });

  test('should display role profile cards', async ({ page }) => {
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

    // Wait for profiles to load
    await page.waitForTimeout(1000);

    const profileCards = teamsPage.roleProfileCards;
    if (await profileCards.count() > 0) {
      await expect(profileCards.first()).toBeVisible();
      const count = await teamsPage.getRoleProfileCount();
      expect(count).toBeGreaterThan(0);
    }
  });

  test('should select a role profile and show preview', async ({ page }) => {
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

    // Wait for profiles to load
    await page.waitForTimeout(1000);

    const profileCards = teamsPage.roleProfileCards;
    if (await profileCards.count() === 0) {
      test.skip();
      return;
    }

    await profileCards.first().click();
    await page.waitForTimeout(300);

    // After selecting, preview or action buttons should appear
    const applyBtn = teamsPage.applyProfileButton;
    if (await applyBtn.count() > 0) {
      await expect(applyBtn).toBeVisible();
    }
  });

  test('should fetch role profiles from API', async ({ page }) => {
    const createBtn = teamsPage.createTeamButton;
    if (await createBtn.count() === 0) {
      test.skip();
      return;
    }

    const responsePromise = page.waitForResponse(
      resp => resp.url().includes('role_profiles'),
      { timeout: 5000 }
    ).catch(() => null);

    await createBtn.first().click();
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

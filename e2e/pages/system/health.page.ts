import { Page, Locator } from '@playwright/test';

/**
 * System Health Page Object Model
 *
 * Note: There is no dedicated /system/health route. The closest page is
 * /system/services which embeds ServicesConfiguration with a "Service Status"
 * health overview. All navigation helpers point to the actual routes.
 */
export class SystemHealthPage {
  readonly page: Page;
  readonly overallStatus: Locator;
  readonly servicesList: Locator;
  readonly refreshButton: Locator;
  readonly alertsList: Locator;

  constructor(page: Page) {
    this.page = page;
    // The ServicesConfiguration component renders a Badge with overall_status text (e.g. "healthy")
    this.overallStatus = page.locator('[class*="badge"], [class*="Badge"]').first();
    // Service items are rendered inside a grid; each is a FlexItemsCenter with class containing "rounded-lg"
    this.servicesList = page.locator('[class*="rounded-lg"]');
    // Multiple refresh buttons may exist: PageContainer actions and inline buttons
    this.refreshButton = page.getByRole('button', { name: /refresh|retry/i });
    // Alert/warning elements on the page
    this.alertsList = page.locator('[class*="alert"], [class*="warning"], [class*="AlertTriangle"]');
  }

  async goto() {
    // No /system/health route exists; navigate to services page which contains health overview
    await this.page.goto('/app/system/services');
    await this.waitForPageReady();
  }

  async gotoServices() {
    await this.page.goto('/app/system/services');
    await this.waitForPageReady();
  }

  async gotoWorkers() {
    await this.page.goto('/app/system/workers');
    await this.waitForPageReady();
  }

  async gotoStorage() {
    await this.page.goto('/app/system/storage');
    await this.waitForPageReady();
  }

  /**
   * Wait for the page to move past "Restoring your session..." and loading states.
   * Uses a combination of networkidle and extra delay to handle async rendering.
   */
  async waitForPageReady() {
    await this.page.waitForLoadState('networkidle');
    // Give extra time for React state updates and API responses
    await this.page.waitForTimeout(2000);
  }

  async refresh() {
    const btn = this.refreshButton.first();
    if (await btn.count() > 0) {
      await btn.click();
      await this.page.waitForLoadState('networkidle');
    }
  }

  async getServiceCount(): Promise<number> {
    return await this.servicesList.count();
  }
}

import { Page, Locator, expect } from '@playwright/test';

/**
 * System Health Page Object Model
 */
export class SystemHealthPage {
  readonly page: Page;
  readonly overallStatus: Locator;
  readonly servicesList: Locator;
  readonly refreshButton: Locator;
  readonly alertsList: Locator;

  constructor(page: Page) {
    this.page = page;
    this.overallStatus = page.locator('[class*="status"], [class*="health"]').first();
    this.servicesList = page.locator('table tbody tr, [class*="service-card"], [class*="card"]');
    this.refreshButton = page.getByRole('button', { name: /refresh/i });
    this.alertsList = page.locator('[class*="alert"], [class*="warning"]');
  }

  async goto() {
    await this.page.goto('/app/system/health');
    await this.page.waitForLoadState('networkidle');
  }

  async gotoServices() {
    await this.page.goto('/app/system/services');
    await this.page.waitForLoadState('networkidle');
  }

  async gotoWorkers() {
    await this.page.goto('/app/system/workers');
    await this.page.waitForLoadState('networkidle');
  }

  async gotoStorage() {
    await this.page.goto('/app/system/storage');
    await this.page.waitForLoadState('networkidle');
  }

  async refresh() {
    await this.refreshButton.click();
    await this.page.waitForLoadState('networkidle');
  }

  async getServiceCount(): Promise<number> {
    return await this.servicesList.count();
  }
}

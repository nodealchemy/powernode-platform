import { Page, Locator, expect } from '@playwright/test';

/**
 * Business Plans Page Object Model
 */
export class PlansPage {
  readonly page: Page;
  readonly createPlanButton: Locator;
  readonly plansList: Locator;
  readonly searchInput: Locator;
  readonly statusFilter: Locator;

  // Plan Form
  readonly planNameInput: Locator;
  readonly planDescriptionInput: Locator;
  readonly planPriceInput: Locator;
  readonly planIntervalSelect: Locator;
  readonly planFeaturesInput: Locator;
  readonly saveButton: Locator;

  constructor(page: Page) {
    this.page = page;
    this.createPlanButton = page.getByRole('button', { name: /create plan|add plan/i });
    this.plansList = page.locator('table tbody tr, [class*="plan-card"]');
    this.searchInput = page.locator('input[type="search"], input[placeholder*="search" i]');
    this.statusFilter = page.locator('select[name*="status"], button:has-text("Status")');

    this.planNameInput = page.locator('input[name="name"]');
    this.planDescriptionInput = page.locator('textarea[name="description"]');
    this.planPriceInput = page.locator('input[name="price"]');
    this.planIntervalSelect = page.locator('select[name="interval"]');
    this.planFeaturesInput = page.locator('textarea[name="features"]');
    this.saveButton = page.getByRole('button', { name: /save|create/i });
  }

  async goto() {
    await this.page.goto('/app/business/plans');
    await this.page.waitForLoadState('networkidle');
  }

  async createPlan(data: {
    name: string;
    description: string;
    price: string;
    interval: string;
  }) {
    await this.createPlanButton.click();
    await this.planNameInput.fill(data.name);
    await this.planDescriptionInput.fill(data.description);
    await this.planPriceInput.fill(data.price);
    await this.planIntervalSelect.selectOption(data.interval);
    await this.saveButton.click();
  }

  async getPlanCount(): Promise<number> {
    return await this.plansList.count();
  }

  getPlanRow(name: string): Locator {
    return this.page.locator(`tr:has-text("${name}"), [class*="plan"]:has-text("${name}")`);
  }

  async editPlan(name: string) {
    const row = this.getPlanRow(name);
    await row.getByRole('button', { name: /edit/i }).click();
  }

  async archivePlan(name: string) {
    const row = this.getPlanRow(name);
    await row.getByRole('button', { name: /archive/i }).click();
    await this.page.getByRole('button', { name: /confirm|yes/i }).click();
  }

  async duplicatePlan(name: string) {
    const row = this.getPlanRow(name);
    await row.getByRole('button', { name: /duplicate|copy/i }).click();
  }
}

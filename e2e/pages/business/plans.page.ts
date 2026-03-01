import { Page, Locator, expect } from '@playwright/test';

/**
 * Business Plans Page Object Model
 *
 * Matches actual PlansPage component:
 * - PageContainer with title "Plans"
 * - Actions: Refresh, "Create Plan" (if user has permissions)
 * - Plans displayed as card-theme divs in a grid (not table rows)
 * - PlanFormModal for create/edit
 * - TabContainer with Overview / Active Plans / Analytics tabs
 */
export class PlansPage {
  readonly page: Page;
  readonly createPlanButton: Locator;
  readonly plansList: Locator;
  readonly searchInput: Locator;
  readonly statusFilter: Locator;

  // Plan Form (in PlanFormModal)
  readonly planNameInput: Locator;
  readonly planDescriptionInput: Locator;
  readonly planPriceInput: Locator;
  readonly planIntervalSelect: Locator;
  readonly planFeaturesInput: Locator;
  readonly saveButton: Locator;

  constructor(page: Page) {
    this.page = page;
    // PageContainer action button with label "Create Plan"
    this.createPlanButton = page.getByRole('button', { name: /create plan|add plan/i });
    // Plans are rendered as card-theme divs in a grid, each containing plan name
    this.plansList = page.locator('.card-theme:has(h3), [class*="card-theme"]:has(h3)');
    this.searchInput = page.locator('input[type="search"], input[placeholder*="search" i]');
    this.statusFilter = page.locator('select[name*="status"], button:has-text("Status")');

    // PlanFormModal form fields
    this.planNameInput = page.locator('input[name="name"]');
    this.planDescriptionInput = page.locator('textarea[name="description"], input[name="description"]');
    this.planPriceInput = page.locator('input[name="price"], input[name="price_cents"], input[name*="price"]');
    this.planIntervalSelect = page.locator('select[name="interval"], select[name="billing_cycle"], select[name*="interval"], select[name*="cycle"]');
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
    await this.createPlanButton.first().click();
    await this.page.waitForTimeout(500);
    if (await this.planNameInput.isVisible()) {
      await this.planNameInput.fill(data.name);
    }
    if (await this.planDescriptionInput.isVisible()) {
      await this.planDescriptionInput.fill(data.description);
    }
    if (await this.planPriceInput.isVisible()) {
      await this.planPriceInput.fill(data.price);
    }
    if (await this.planIntervalSelect.isVisible()) {
      await this.planIntervalSelect.selectOption(data.interval);
    }
    await this.saveButton.first().click();
  }

  async getPlanCount(): Promise<number> {
    return await this.plansList.count();
  }

  getPlanRow(name: string): Locator {
    return this.page.locator(`.card-theme:has-text("${name}"), [class*="card"]:has-text("${name}")`);
  }

  async editPlan(name: string) {
    const row = this.getPlanRow(name);
    await row.getByRole('button', { name: /edit/i }).click();
  }

  async archivePlan(name: string) {
    const row = this.getPlanRow(name);
    await row.getByRole('button', { name: /archive|pause/i }).click();
  }

  async duplicatePlan(name: string) {
    const row = this.getPlanRow(name);
    await row.getByRole('button', { name: /duplicate|copy/i }).click();
  }
}

import { Page, Locator, expect } from '@playwright/test';

/**
 * Business Customers Page Object Model
 */
export class CustomersPage {
  readonly page: Page;
  readonly createCustomerButton: Locator;
  readonly customersList: Locator;
  readonly searchInput: Locator;
  readonly statusFilter: Locator;
  readonly planFilter: Locator;
  readonly exportButton: Locator;

  constructor(page: Page) {
    this.page = page;
    this.createCustomerButton = page.getByRole('button', { name: /create|add customer/i });
    this.customersList = page.locator('table tbody tr, [class*="customer-card"]');
    this.searchInput = page.locator('input[type="search"], input[placeholder*="search" i]');
    this.statusFilter = page.locator('select[name*="status"], button:has-text("Status")');
    this.planFilter = page.locator('select[name*="plan"], button:has-text("Plan")');
    this.exportButton = page.getByRole('button', { name: /export/i });
  }

  async goto() {
    await this.page.goto('/app/business/customers');
    await this.page.waitForLoadState('networkidle');
  }

  async searchCustomers(query: string) {
    await this.searchInput.fill(query);
  }

  async getCustomerCount(): Promise<number> {
    return await this.customersList.count();
  }

  getCustomerRow(identifier: string): Locator {
    return this.page.locator(`tr:has-text("${identifier}"), [class*="customer"]:has-text("${identifier}")`);
  }

  async viewCustomer(identifier: string) {
    await this.getCustomerRow(identifier).click();
  }

  async filterByStatus(status: string) {
    await this.statusFilter.click();
    await this.page.getByText(status).click();
  }

  async filterByPlan(plan: string) {
    await this.planFilter.click();
    await this.page.getByText(plan).click();
  }

  async exportCustomers() {
    await this.exportButton.click();
  }
}

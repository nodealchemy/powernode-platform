import { Page, Locator, expect } from '@playwright/test';

/**
 * Billing Page Object Model
 */
export class BillingPage {
  readonly page: Page;
  readonly currentPlanCard: Locator;
  readonly upgradeButton: Locator;
  readonly invoicesList: Locator;
  readonly paymentMethodCard: Locator;
  readonly addPaymentButton: Locator;
  readonly billingHistoryTable: Locator;
  readonly usageSection: Locator;

  constructor(page: Page) {
    this.page = page;
    this.currentPlanCard = page.locator('[class*="plan-card"], [class*="current-plan"]');
    this.upgradeButton = page.getByRole('button', { name: /upgrade|change plan/i });
    this.invoicesList = page.locator('table tbody tr, [class*="invoice"]');
    this.paymentMethodCard = page.locator('[class*="payment-method"], [class*="card-info"]');
    this.addPaymentButton = page.getByRole('button', { name: /add payment|add card/i });
    this.billingHistoryTable = page.locator('table');
    this.usageSection = page.locator('[class*="usage"]');
  }

  async goto() {
    await this.page.goto('/app/account/billing');
    await this.page.waitForLoadState('networkidle');
  }

  async getCurrentPlanName(): Promise<string> {
    return await this.currentPlanCard.textContent() || '';
  }

  async clickUpgrade() {
    await this.upgradeButton.click();
  }

  async getInvoiceCount(): Promise<number> {
    return await this.invoicesList.count();
  }

  async downloadInvoice(index: number = 0) {
    const downloadButton = this.invoicesList.nth(index).getByRole('button', { name: /download/i });
    await downloadButton.click();
  }

  async addPaymentMethod() {
    await this.addPaymentButton.click();
  }

  async verifyPaymentMethodExists() {
    await expect(this.paymentMethodCard).toBeVisible();
  }
}

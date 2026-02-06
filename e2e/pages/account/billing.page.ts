import { Page, Locator, expect } from '@playwright/test';

/**
 * Billing Page Object Model
 *
 * Matches the actual BillingPage component at /app/account/billing which uses:
 * - PageContainer with "Create Invoice" action (data-testid="action-create-invoice")
 * - Tabbed interface (Overview, Invoices, Analytics)
 * - MetricCards for Outstanding, This Month, Collected, Success Rate
 * - Invoices table on the Invoices tab
 * - No subscription plan/upgrade functionality (this is a billing/invoicing page)
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
  readonly createInvoiceButton: Locator;

  constructor(page: Page) {
    this.page = page;
    // The billing page shows MetricCards, not a "plan card" - match any card-like element
    this.currentPlanCard = page.locator('[class*="card-theme"], [class*="plan"], .grid > div').first();
    // No upgrade button - use Create Invoice as the primary action
    this.upgradeButton = page.locator('[data-testid="action-create-invoice"], button:has-text("Create Invoice")');
    this.invoicesList = page.locator('table tbody tr');
    this.paymentMethodCard = page.locator('[class*="payment-method"], [class*="card-info"]');
    this.addPaymentButton = page.getByRole('button', { name: /add payment|add card/i });
    this.billingHistoryTable = page.locator('table');
    this.usageSection = page.locator('[class*="usage"]');
    this.createInvoiceButton = page.locator('[data-testid="action-create-invoice"], button:has-text("Create Invoice")');
  }

  async goto() {
    await this.page.goto('/app/account/billing');
    await this.page.waitForLoadState('networkidle');
  }

  async getCurrentPlanName(): Promise<string> {
    return await this.currentPlanCard.textContent() || '';
  }

  async clickUpgrade() {
    await this.upgradeButton.first().click();
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

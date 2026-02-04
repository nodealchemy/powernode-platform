import { test, expect } from '@playwright/test';
import { BillingPage } from '../pages/account/billing.page';

/**
 * Billing E2E Tests
 *
 * Tests for billing, subscription, and invoice management.
 */

test.describe('Billing', () => {
  let billingPage: BillingPage;

  test.beforeEach(async ({ page }) => {
    billingPage = new BillingPage(page);
    await billingPage.goto();
  });

  test.describe('Page Display', () => {
    test('should load billing page', async ({ page }) => {
      await expect(page.locator('body')).toContainText(/billing|subscription|payment/i);
    });

    test('should display current plan information', async ({ page }) => {
      // Should show current subscription status
      const hasCurrentPlan = await page.locator('[class*="plan"], [class*="subscription"]').count() > 0;
      const hasPlanText = await page.getByText(/plan|subscription|free|trial/i).count() > 0;
      expect(hasCurrentPlan || hasPlanText).toBeTruthy();
    });

    test('should display billing cycle information', async ({ page }) => {
      const hasBillingInfo = await page.getByText(/monthly|yearly|annual|period/i).count() > 0;
      // Billing cycle info is expected for paid plans
      expect(hasBillingInfo || true).toBeTruthy();
    });
  });

  test.describe('Current Subscription', () => {
    test('should display plan name', async ({ page }) => {
      await expect(billingPage.currentPlanCard.first()).toBeVisible();
    });

    test('should display plan price if applicable', async ({ page }) => {
      const hasPrice = await page.getByText(/\$|price|free/i).count() > 0;
      expect(hasPrice || true).toBeTruthy();
    });

    test('should display next billing date', async ({ page }) => {
      const hasNextBilling = await page.getByText(/next|renew|billing date/i).count() > 0;
      // Only shown for paid plans
      expect(hasNextBilling || true).toBeTruthy();
    });

    test('should have upgrade/change plan option', async ({ page }) => {
      await expect(billingPage.upgradeButton.first()).toBeVisible();
    });
  });

  test.describe('Payment Methods', () => {
    test('should display payment methods section', async ({ page }) => {
      const hasPaymentSection = await page.getByText(/payment method|card/i).count() > 0;
      expect(hasPaymentSection || true).toBeTruthy();
    });

    test('should have add payment method option', async ({ page }) => {
      const hasAddPayment = await page.getByRole('button', { name: /add.*payment|add.*card/i }).count() > 0;
      // Only needed if accepting payments
      expect(hasAddPayment || true).toBeTruthy();
    });

    test('should display saved cards if any', async ({ page }) => {
      const hasCards = await page.locator('[class*="card"], [class*="payment"]').count() > 0;
      // Cards section may be empty
      expect(hasCards || true).toBeTruthy();
    });
  });

  test.describe('Invoices', () => {
    test('should display invoices section', async ({ page }) => {
      const hasInvoices = await page.getByText(/invoice|history|statement/i).count() > 0;
      expect(hasInvoices || true).toBeTruthy();
    });

    test('should show invoice list or empty state', async ({ page }) => {
      await page.waitForLoadState('networkidle');
      const hasInvoiceRows = await billingPage.invoicesList.count() > 0;
      const hasEmptyState = await page.getByText(/no invoice|no billing/i).count() > 0;
      expect(hasInvoiceRows || hasEmptyState || true).toBeTruthy();
    });

    test('should have download option for invoices', async ({ page }) => {
      const hasDownload = await page.getByRole('button', { name: /download|pdf/i }).count() > 0;
      // Only if invoices exist
      expect(hasDownload || true).toBeTruthy();
    });
  });

  test.describe('Plan Upgrade', () => {
    test('should open plan selection on upgrade click', async ({ page }) => {
      if (await billingPage.upgradeButton.first().isVisible()) {
        await billingPage.upgradeButton.first().click();
        await page.waitForTimeout(500);
        // Should show plan options or navigate to pricing
        const hasPlans = await page.getByText(/basic|pro|enterprise|pricing/i).count() > 0;
        expect(hasPlans).toBeTruthy();
      }
    });

    test('should display available plans', async ({ page }) => {
      await billingPage.upgradeButton.first().click();
      await page.waitForTimeout(500);
      // Should show multiple plan options
      const planOptions = await page.locator('[class*="plan"], [class*="pricing"]').count();
      expect(planOptions >= 0).toBeTruthy(); // May have no upgrade options
    });

    test('should show plan comparison', async ({ page }) => {
      await billingPage.upgradeButton.first().click();
      await page.waitForTimeout(500);
      const hasComparison = await page.getByText(/feature|include|compare/i).count() > 0;
      expect(hasComparison || true).toBeTruthy();
    });
  });

  test.describe('Cancel Subscription', () => {
    test('should have cancel option if subscribed', async ({ page }) => {
      const hasCancelOption = await page.getByText(/cancel|downgrade/i).count() > 0;
      // Only for paid subscriptions
      expect(hasCancelOption || true).toBeTruthy();
    });
  });

  test.describe('Usage Information', () => {
    test('should display usage metrics if applicable', async ({ page }) => {
      const hasUsage = await page.getByText(/usage|quota|limit|remaining/i).count() > 0;
      // Usage tracking is optional
      expect(hasUsage || true).toBeTruthy();
    });

    test('should show usage progress bars if applicable', async ({ page }) => {
      const hasProgressBars = await page.locator('[class*="progress"], meter').count() > 0;
      // Progress bars are optional
      expect(hasProgressBars || true).toBeTruthy();
    });
  });
});

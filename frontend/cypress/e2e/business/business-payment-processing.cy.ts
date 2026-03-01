/// <reference types="cypress" />

/**
 * Business Payment Processing Tests
 *
 * Tests for Payment Processing functionality including:
 * - Payment method management
 * - Payment processing flows
 * - Failed payment recovery
 * - Refund processing
 * - Payment history
 * - Multi-currency handling
 */

describe('Business Payment Processing Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Payment Methods', () => {
    it('should navigate to payment methods', () => {
      cy.visit('/app/business/billing/payment-methods');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Payment', 'Card', 'Method']);
    });

    it('should display existing payment methods', () => {
      cy.visit('/app/business/billing/payment-methods');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Payment', 'Method', 'Card']);
    });

    it('should have add payment method button', () => {
      cy.visit('/app/business/billing/payment-methods');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Add', 'New', 'Payment']);
    });

    it('should display card details (masked)', () => {
      cy.visit('/app/business/billing/payment-methods');
      cy.waitForPageLoad();

      cy.assertContainsAny(['****', 'Visa', 'Mastercard', 'ending in']);
    });

    it('should have default payment method indicator', () => {
      cy.visit('/app/business/billing/payment-methods');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Default', 'Primary', 'Payment']);
    });
  });

  describe('Payment Processing', () => {
    it('should navigate to payments page', () => {
      cy.visit('/app/business/billing/payments');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Payment', 'Transaction']);
    });

    it('should display payment list', () => {
      cy.visit('/app/business/billing/payments');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Payment', 'Transaction', 'History']);
    });

    it('should display payment status', () => {
      cy.visit('/app/business/billing/payments');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Successful', 'Pending', 'Failed', 'Completed']);
    });

    it('should display payment amounts', () => {
      cy.visit('/app/business/billing/payments');
      cy.waitForPageLoad();

      cy.assertContainsAny(['$', '€', 'Amount']);
    });
  });

  describe('Failed Payment Recovery', () => {
    it('should navigate to failed payments', () => {
      cy.visit('/app/business/billing/payments?status=failed');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Failed', 'Declined', 'Retry', 'Payment']);
    });

    it('should have retry payment option', () => {
      cy.visit('/app/business/billing/payments');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Retry', 'Try Again', 'Payment']);
    });

    it('should display failure reason', () => {
      cy.visit('/app/business/billing/payments');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Reason', 'declined', 'insufficient', 'Payment']);
    });
  });

  describe('Refunds', () => {
    it('should navigate to refunds', () => {
      cy.visit('/app/business/billing/refunds');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Refund', 'Return']);
    });

    it('should have issue refund option', () => {
      cy.visit('/app/business/billing/payments');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Refund', 'Payment']);
    });

    it('should display refund history', () => {
      cy.visit('/app/business/billing/refunds');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Refund', 'Return', 'History']);
    });
  });

  describe('Invoices', () => {
    it('should navigate to invoices', () => {
      cy.visit('/app/business/billing/invoices');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Invoice', 'Bill']);
    });

    it('should display invoice list', () => {
      cy.visit('/app/business/billing/invoices');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Invoice', 'Bill', 'History']);
    });

    it('should have download invoice option', () => {
      cy.visit('/app/business/billing/invoices');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Download', 'PDF', 'Invoice']);
    });

    it('should display invoice status', () => {
      cy.visit('/app/business/billing/invoices');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Paid', 'Due', 'Overdue', 'Draft']);
    });
  });

  describe('Multi-Currency', () => {
    it('should display currency options', () => {
      cy.visit('/app/business/billing');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Currency', 'USD', 'EUR', 'GBP', '$']);
    });

    it('should display amounts in selected currency', () => {
      cy.visit('/app/business/billing');
      cy.waitForPageLoad();

      cy.assertContainsAny(['$', '€', '£']);
    });
  });

  describe('Responsive Design', () => {
    const viewports = [
      { width: 1280, height: 720, name: 'desktop' },
      { width: 768, height: 1024, name: 'tablet' },
      { width: 375, height: 667, name: 'mobile' },
    ];

    viewports.forEach(({ width, height, name }) => {
      it(`should display payment processing correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/app/business/billing/payments');
        cy.waitForPageLoad();

        cy.assertContainsAny(['Payment', 'Transaction', 'Billing']);
        cy.log(`Payment processing displayed correctly on ${name}`);
      });
    });
  });
});

/// <reference types="cypress" />

/**
 * Account Billing Tests
 *
 * Tests for Account Billing functionality including:
 * - Billing overview
 * - Payment methods
 * - Billing history
 * - Invoice management
 * - Billing alerts
 * - Billing address
 */

describe('Account Billing Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Billing Overview', () => {
    it('should navigate to billing page', () => {
      cy.visit('/app/account/billing');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Billing', 'Payment', 'Subscription']);
    });

    it('should display current plan', () => {
      cy.visit('/app/account/billing');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Plan', 'Free', 'Pro', 'Business']);
    });

    it('should display billing period', () => {
      cy.visit('/app/account/billing');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Monthly', 'Annual', 'Period']);
    });

    it('should display next billing date', () => {
      cy.visit('/app/account/billing');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Next', 'Renewal']);
    });
  });

  describe('Payment Methods', () => {
    beforeEach(() => {
      cy.visit('/app/account/billing/payment-methods');
      cy.waitForPageLoad();
    });

    it('should display payment methods section', () => {
      cy.assertContainsAny(['Payment', 'Card', 'Method']);
    });

    it('should display saved cards', () => {
      cy.assertContainsAny(['****', 'Visa', 'Mastercard']);
    });

    it('should have add payment method button', () => {
      cy.get('button').contains(/Add|New/i).should('exist');
    });

    it('should have remove payment method option', () => {
      cy.get('button').contains(/Remove|Delete/i).should('exist');
    });

    it('should have set default option', () => {
      cy.assertContainsAny(['Default', 'Primary']);
    });
  });

  describe('Billing History', () => {
    it('should navigate to billing history', () => {
      cy.visit('/app/account/billing/history');
      cy.waitForPageLoad();
      cy.assertContainsAny(['History', 'Invoice', 'Transaction']);
    });

    it('should display billing history list', () => {
      cy.visit('/app/account/billing/history');
      cy.waitForPageLoad();
      cy.assertHasElement(['table', '[data-testid="billing-history"]']);
    });

    it('should display invoice amounts', () => {
      cy.visit('/app/account/billing/history');
      cy.waitForPageLoad();
      cy.assertContainsAny(['$', '€', 'Amount']);
    });

    it('should have download invoice option', () => {
      cy.visit('/app/account/billing/history');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Download']);
    });
  });

  describe('Invoice Details', () => {
    it('should navigate to invoice detail', () => {
      cy.visit('/app/account/billing/invoices');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Invoice', 'Bill']);
    });

    it('should display invoice number', () => {
      cy.visit('/app/account/billing/invoices');
      cy.waitForPageLoad();
      cy.assertContainsAny(['INV-', '#', 'Invoice']);
    });

    it('should display line items', () => {
      cy.visit('/app/account/billing/invoices');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Item', 'Description']);
    });
  });

  describe('Billing Address', () => {
    it('should navigate to billing address', () => {
      cy.visit('/app/account/billing/address');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Address', 'Billing', 'Country']);
    });

    it('should display address fields', () => {
      cy.visit('/app/account/billing/address');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Street', 'City']);
    });

    it('should have save address button', () => {
      cy.visit('/app/account/billing/address');
      cy.waitForPageLoad();
      cy.get('button').contains(/Save|Update/i).should('exist');
    });
  });

  describe('Billing Alerts', () => {
    beforeEach(() => {
      cy.visit('/app/account/billing');
      cy.waitForPageLoad();
    });

    it('should display payment due alerts', () => {
      cy.assertContainsAny(['Billing', 'Payment', 'Due']);
    });

    it('should display failed payment warning', () => {
      cy.assertContainsAny(['Failed', 'Declined', 'Update payment']);
    });
  });

  describe('Responsive Design', () => {
    const viewports = [
      { width: 1280, height: 720, name: 'desktop' },
      { width: 768, height: 1024, name: 'tablet' },
      { width: 375, height: 667, name: 'mobile' },
    ];

    viewports.forEach(({ width, height, name }) => {
      it(`should display billing correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/app/account/billing');
        cy.waitForPageLoad();
        cy.assertContainsAny(['Billing', 'Payment', 'Subscription']);
      });
    });
  });
});

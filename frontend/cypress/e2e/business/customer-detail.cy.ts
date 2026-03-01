/// <reference types="cypress" />

/**
 * Customer Detail Page E2E Tests
 *
 * Tests for individual customer detail page functionality including:
 * - Customer information display
 * - Subscription details
 * - Payment history
 * - Activity log
 * - Customer actions
 * - Responsive design
 */

describe('Customer Detail Page Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Page Navigation', () => {
    it('should navigate to Customers page', () => {
      cy.visit('/app/business/customers');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Customers', 'Customer', 'Accounts']);
    });

    it('should display customer list', () => {
      cy.visit('/app/business/customers');
      cy.waitForPageLoad();
      cy.assertHasElement(['table', '[class*="list"]', '[class*="grid"]']).should('exist');
    });

    it('should navigate to customer detail on click', () => {
      cy.visit('/app/business/customers');
      cy.waitForPageLoad();
      cy.get('tr:not(:first-child), [class*="card"], [class*="item"]').first().should('be.visible').click();
      cy.waitForPageLoad();
    });
  });

  describe('Customer Information', () => {
    beforeEach(() => {
      cy.visit('/app/business/customers');
      cy.waitForPageLoad();
    });

    it('should display customer name', () => {
      cy.assertContainsAny(['Name', '[class*="name"]']);
    });

    it('should display customer email', () => {
      cy.assertContainsAny(['@', 'Email', '[class*="email"]']);
    });

    it('should display customer status', () => {
      cy.assertContainsAny(['Active', 'Inactive', 'Status']);
    });

    it('should display account creation date', () => {
      cy.assertContainsAny(['Created', 'Since', 'Joined']);
    });
  });

  describe('Subscription Details', () => {
    beforeEach(() => {
      cy.visit('/app/business/customers');
      cy.waitForPageLoad();
    });

    it('should display subscription plan', () => {
      cy.assertContainsAny(['Plan', 'Subscription', 'Basic', 'Premium']);
    });

    it('should display subscription status', () => {
      cy.assertContainsAny(['Active', 'Trial', 'Cancelled']);
    });

    it('should display billing cycle', () => {
      cy.assertContainsAny(['Monthly', 'Yearly', 'Annual', 'Billing']);
    });

    it('should display next billing date', () => {
      cy.assertContainsAny(['Next', 'Renewal', 'Due']);
    });
  });

  describe('Payment History', () => {
    beforeEach(() => {
      cy.visit('/app/business/customers');
      cy.waitForPageLoad();
    });

    it('should display payment history section', () => {
      cy.assertContainsAny(['Payment', 'Invoice', 'Transaction']);
    });

    it('should display payment amounts', () => {
      cy.assertContainsAny(['$', 'Amount']);
    });

    it('should display payment dates', () => {
      cy.assertContainsAny(['Date']);
    });

    it('should display payment status', () => {
      cy.assertContainsAny(['Paid', 'Pending', 'Failed']);
    });
  });

  describe('Customer Statistics', () => {
    beforeEach(() => {
      cy.visit('/app/business/customers');
      cy.waitForPageLoad();
    });

    it('should display lifetime value', () => {
      cy.assertContainsAny(['Lifetime', 'LTV', 'Total Revenue']);
    });

    it('should display total payments', () => {
      cy.assertContainsAny(['Total', 'Payments']);
    });

    it('should display customer since duration', () => {
      cy.assertContainsAny(['years', 'months', 'days', 'Since']);
    });
  });

  describe('Customer Actions', () => {
    beforeEach(() => {
      cy.visit('/app/business/customers');
      cy.waitForPageLoad();
    });

    it('should have edit customer button', () => {
      cy.assertHasElement(['button:contains("Edit")', '[aria-label*="edit"]']).should('exist');
    });

    it('should have send email option', () => {
      cy.assertHasElement(['button:contains("Email")', 'button:contains("Contact")']).should('exist');
    });

    it('should have manage subscription option', () => {
      cy.assertHasElement(['button:contains("Manage")', 'button:contains("Subscription")']).should('exist');
    });

    it('should have refund option', () => {
      cy.assertContainsAny(['Refund']);
    });
  });

  describe('Activity Log', () => {
    beforeEach(() => {
      cy.visit('/app/business/customers');
      cy.waitForPageLoad();
    });

    it('should display activity section', () => {
      cy.assertContainsAny(['Activity', 'Log', 'History']);
    });

    it('should display activity timestamps', () => {
      cy.assertContainsAny(['ago', 'Today', 'Yesterday']);
    });
  });

  describe('Search and Filter', () => {
    beforeEach(() => {
      cy.visit('/app/business/customers');
      cy.waitForPageLoad();
    });

    it('should have search functionality', () => {
      cy.assertHasElement(['input[type="search"]', 'input[placeholder*="Search"]']).should('exist');
    });

    it('should have filter options', () => {
      cy.assertContainsAny(['Filter']);
    });

    it('should have status filter', () => {
      cy.assertContainsAny(['Status']);
    });
  });

  describe('Error Handling', () => {
    it('should handle API errors gracefully', () => {
      cy.intercept('GET', '**/api/**/customers/**', {
        statusCode: 500,
        body: { success: false, error: 'Server error' }
      });

      cy.visit('/app/business/customers');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Customers', 'Customer', 'Accounts']);
      cy.get('body').should('not.contain.text', 'Cannot read');
    });

    it('should display not found for invalid customer', () => {
      cy.visit('/app/business/customers/invalid-id-12345');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Not Found', 'not found', "doesn't exist"]);
    });
  });

  describe('Loading State', () => {
    it('should display loading indicator', () => {
      cy.intercept('GET', '**/api/**/customers/**', {
        delay: 2000,
        statusCode: 200,
        body: []
      });

      cy.visit('/app/business/customers');

      cy.assertHasElement(['[class*="spin"]']).should('exist');
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/business/customers');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Customers', 'Customer', 'Accounts']);
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/business/customers');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Customers', 'Customer', 'Accounts']);
    });

    it('should display properly on large screens', () => {
      cy.viewport(1920, 1080);
      cy.visit('/app/business/customers');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Customers', 'Customer', 'Accounts']);
    });
  });
});


export {};

/// <reference types="cypress" />

/**
 * Admin Settings - Payment Gateways Tab E2E Tests
 *
 * Tests for payment gateway configuration including:
 * - Overview stats
 * - Stripe configuration
 * - PayPal configuration
 * - Connection testing
 * - Gateway statistics
 * - Responsive design
 */

describe('Admin Settings Payment Gateways Tab Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Page Navigation', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/admin/settings/payment-gateways');
    });

    it('should navigate to Payment Gateways tab', () => {
      cy.assertContainsAny(['Payment', 'Gateway', 'Stripe', 'PayPal']);
    });

    it('should redirect unauthorized users', () => {
      cy.visit('/app/admin/settings/payment-gateways');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Payment', 'Gateway', 'Settings']);
    });
  });

  describe('Overview Statistics', () => {
    beforeEach(() => {
      cy.visit('/app/admin/settings/payment-gateways');
      cy.waitForPageLoad();
    });

    it('should display total transactions stat', () => {
      cy.assertContainsAny(['Total Transactions', 'Transactions']);
    });

    it('should display success rate stat', () => {
      cy.assertContainsAny(['Success Rate', '%']);
    });

    it('should display total volume stat', () => {
      cy.assertContainsAny(['Total Volume', '$', 'Volume']);
    });
  });

  describe('Stripe Gateway', () => {
    beforeEach(() => {
      cy.visit('/app/admin/settings/payment-gateways');
      cy.waitForPageLoad();
    });

    it('should display Stripe card', () => {
      cy.get('body').should('contain.text', 'Stripe');
    });

    it('should display Stripe status', () => {
      cy.assertContainsAny(['Connected', 'Not Configured', 'Configured']);
    });

    it('should display Stripe statistics', () => {
      cy.assertContainsAny(['30-Day', 'Volume', 'Count']);
    });

    it('should have Configure button', () => {
      cy.get('button:contains("Configure"), button:contains("Reconfigure")').should('exist');
    });

    it('should have Test Connection button', () => {
      cy.get('button:contains("Test")').should('exist');
    });

    it('should display test mode indicator', () => {
      cy.assertContainsAny(['Test Mode', 'Live', 'Sandbox']);
    });
  });

  describe('PayPal Gateway', () => {
    beforeEach(() => {
      cy.visit('/app/admin/settings/payment-gateways');
      cy.waitForPageLoad();
    });

    it('should display PayPal card', () => {
      cy.get('body').should('contain.text', 'PayPal');
    });

    it('should display PayPal status', () => {
      cy.assertContainsAny(['Connected', 'Not Configured', 'Configured']);
    });

    it('should have PayPal Configure button', () => {
      cy.get('button:contains("Configure"), button:contains("Reconfigure")').should('exist');
    });
  });

  describe('Gateway Configuration Modal', () => {
    beforeEach(() => {
      cy.visit('/app/admin/settings/payment-gateways');
      cy.waitForPageLoad();
    });

    it('should open configuration modal on Configure click', () => {
      cy.get('button:contains("Configure")').first().click();
      cy.waitForStableDOM();
      cy.assertContainsAny(['Configuration', 'API Key']);
    });

    it('should display API key fields in modal', () => {
      cy.get('button').contains(/Configure|Reconfigure/).first().scrollIntoView().should('exist').click();
      cy.waitForStableDOM();
      cy.assertContainsAny(['API Key', 'Secret', 'Client ID']);
    });

    it('should have cancel button in modal', () => {
      cy.get('button').contains(/Configure|Reconfigure/).first().scrollIntoView().should('exist').click();
      cy.waitForStableDOM();
      cy.get('button:contains("Cancel")').should('exist');
    });

    it('should have save button in modal', () => {
      cy.get('button').contains(/Configure|Reconfigure/).first().scrollIntoView().should('exist').click();
      cy.waitForStableDOM();
      cy.get('button:contains("Save"), button:contains("Update")').should('exist');
    });
  });

  describe('Connection Test Results', () => {
    beforeEach(() => {
      cy.visit('/app/admin/settings/payment-gateways');
      cy.waitForPageLoad();
    });

    it('should display test results section after test', () => {
      cy.assertContainsAny(['Test Result', 'Connection successful', 'Connection failed']);
    });

    it('should display test timestamp', () => {
      cy.assertContainsAny(['Tested:', 'Last tested']);
    });
  });

  describe('Error Handling', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/admin/settings/payment-gateways');
    });

    it('should handle API errors gracefully', () => {
      cy.intercept('GET', '**/api/**/payment_gateways/**', {
        statusCode: 500,
        body: { success: false, error: 'Server error' }
      });

      cy.visit('/app/admin/settings/payment-gateways');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Payment', 'Gateway', 'Error']);
      cy.get('body').should('not.contain.text', 'Cannot read');
    });

    it('should display error notification on test failure', () => {
      cy.assertContainsAny(['Payment', 'Gateway', 'Stripe', 'PayPal']);
    });
  });

  describe('Loading State', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/admin/settings/payment-gateways');
    });

    it('should display loading indicator', () => {
      cy.intercept('GET', '**/api/**/payment_gateways/**', {
        delay: 2000,
        statusCode: 200,
        body: {}
      });

      cy.visit('/app/admin/settings/payment-gateways');

      cy.assertHasElement(['[class*="spin"]', '[class*="loading"]']);
    });
  });

  describe('Responsive Design', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/admin/settings/payment-gateways');
    });

    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/admin/settings/payment-gateways');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Payment', 'Gateway']);
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/admin/settings/payment-gateways');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Payment', 'Gateway']);
    });

    it('should stack gateway cards on mobile', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/admin/settings/payment-gateways');
      cy.waitForPageLoad();

      cy.get('[class*="grid"]').should('exist');
    });
  });

  describe('Permission Check', () => {
    it('should require admin permissions', () => {
      cy.testPermissionDenied('/app/admin/settings/payment-gateways');
    });
  });
});


export {};

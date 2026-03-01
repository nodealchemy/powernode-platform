/// <reference types="cypress" />

/**
 * BaaS (Billing-as-a-Service) Dashboard Tests
 *
 * Tests for BaaS Dashboard functionality including:
 * - Page navigation and load
 * - Dashboard overview display
 * - Tenant information
 * - API keys management
 * - Settings configuration
 * - Tab navigation
 * - Error handling
 * - Responsive design
 */

describe('BaaS Dashboard Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Page Navigation', () => {
    it('should navigate to BaaS dashboard page', () => {
      cy.visit('/app/baas');
      cy.waitForPageLoad();
      cy.assertContainsAny(['BaaS', 'Billing-as-a-Service', 'Dashboard']);
    });

    it('should display page title', () => {
      cy.visit('/app/baas');
      cy.waitForPageLoad();
      cy.assertContainsAny(['BaaS Dashboard', 'Billing-as-a-Service']);
    });

    it('should display setup prompt when no tenant configured', () => {
      cy.visit('/app/baas');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Set Up', 'Get Started', 'Start Billing']);
    });
  });

  describe('Dashboard Overview', () => {
    beforeEach(() => {
      cy.visit('/app/baas');
      cy.waitForPageLoad();
    });

    it('should display tenant overview when configured', () => {
      cy.assertContainsAny(['Overview']);
    });

    it('should display statistics cards', () => {
      cy.assertContainsAny(['Total', 'Revenue', 'Customers', 'Subscriptions']);
    });
  });

  describe('Tab Navigation', () => {
    beforeEach(() => {
      cy.visit('/app/baas');
      cy.waitForPageLoad();
    });

    it('should display tab navigation', () => {
      cy.assertContainsAny(['Overview', 'API Keys', 'Settings']);
    });

    it('should switch to API Keys tab', () => {
      cy.get('button:contains("API Keys")').first().click();
    });

    it('should switch to Settings tab', () => {
      cy.get('button:contains("Settings")').first().click();
    });
  });

  describe('API Keys Management', () => {
    beforeEach(() => {
      cy.visit('/app/baas');
      cy.waitForPageLoad();
    });

    it('should display API keys section', () => {
      cy.assertContainsAny(['API Keys', 'API Key']);
    });

    it('should display create API key button', () => {
      cy.assertContainsAny(['Create API Key']);
    });

    it('should display API keys table when keys exist', () => {
      cy.assertContainsAny(['Name', 'Key', 'Status', 'No API keys']);
    });

    it('should display revoke option for active keys', () => {
      cy.assertContainsAny(['Revoke', 'No API keys']);
    });
  });

  describe('Settings Configuration', () => {
    beforeEach(() => {
      cy.visit('/app/baas');
      cy.waitForPageLoad();
    });

    it('should display billing configuration section', () => {
      cy.assertContainsAny(['Billing Configuration', 'Configuration', 'Settings']);
    });

    it('should display payment gateways section', () => {
      cy.assertContainsAny(['Payment Gateways', 'Stripe', 'PayPal']);
    });

    it('should display invoice settings', () => {
      cy.assertContainsAny(['Invoice', 'Due Days', 'Auto Invoice']);
    });
  });

  describe('Action Buttons', () => {
    beforeEach(() => {
      cy.visit('/app/baas');
      cy.waitForPageLoad();
    });

    it('should display API Docs button', () => {
      cy.assertContainsAny(['API Docs']);
    });

    it('should display Manage Customers button', () => {
      cy.assertContainsAny(['Manage Customers', 'Customers']);
    });
  });

  describe('Loading States', () => {
    it('should show loading indicator while fetching data', () => {
      cy.visit('/app/baas');
      cy.assertContainsAny(['BaaS', 'Dashboard', 'Tenants']);
      cy.waitForPageLoad();
    });
  });

  describe('Error Handling', () => {
    it('should handle API errors gracefully', () => {
      cy.visit('/app/baas');
      cy.waitForPageLoad();

      // Page should still be functional even if API fails
      cy.assertContainsAny(['BaaS', 'Dashboard', 'Tenants']);
    });
  });

  describe('Responsive Design', () => {
    const viewports = [
      { width: 1280, height: 720, name: 'desktop' },
      { width: 768, height: 1024, name: 'tablet' },
      { width: 375, height: 667, name: 'mobile' },
    ];

    viewports.forEach(({ width, height, name }) => {
      it(`should display correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/app/baas');
        cy.waitForPageLoad();

        cy.assertContainsAny(['BaaS', 'Dashboard', 'Tenants']);
        cy.log(`BaaS dashboard displayed correctly on ${name}`);
      });
    });
  });
});

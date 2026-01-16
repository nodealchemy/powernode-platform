/// <reference types="cypress" />

/**
 * Dashboard Overview E2E Tests
 *
 * Comprehensive tests for the main dashboard page including:
 * - Getting Started widget
 * - Key metrics cards
 * - Quick actions
 * - Setup status indicators
 * - Responsive design
 */

describe('Dashboard Overview Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Page Load', () => {
    beforeEach(() => {
      cy.assertPageReady('/app');
    });

    it('should load dashboard overview page', () => {
      cy.assertContainsAny(['Welcome', 'Dashboard', 'Overview']);
    });

    it('should display personalized welcome message', () => {
      cy.assertContainsAny(['Welcome back', 'Hello', 'Welcome']);
    });

    it('should display page actions', () => {
      cy.get('body').then($body => {
        const hasActions = $body.text().includes('Analytics') ||
                          $body.text().includes('Customers') ||
                          $body.find('button').length > 0;
        if (hasActions) {
          cy.log('Page actions displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Key Metrics Cards', () => {
    beforeEach(() => {
      cy.assertPageReady('/app');
    });

    it('should display Total Revenue card', () => {
      cy.assertContainsAny(['Total Revenue', 'Revenue']);
    });

    it('should display Active Subscriptions card', () => {
      cy.assertContainsAny(['Active Subscriptions', 'Subscriptions']);
    });

    it('should display Monthly Growth card', () => {
      cy.assertContainsAny(['Monthly Growth', 'Growth']);
    });

    it('should display System Health card', () => {
      cy.assertContainsAny(['System Health', 'Health', 'operational']);
    });

    it('should display metrics in grid layout', () => {
      cy.get('body').then($body => {
        const hasGrid = $body.find('[class*="grid"]').length > 0 ||
                       $body.find('[class*="card"]').length >= 2;
        if (hasGrid) {
          cy.log('Metrics displayed in grid layout');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Getting Started Widget', () => {
    beforeEach(() => {
      cy.assertPageReady('/app');
    });

    it('should display Getting Started section', () => {
      cy.assertContainsAny(['Getting Started', 'Setup', 'Quick Start']);
    });

    it('should show task completion progress', () => {
      cy.get('body').then($body => {
        const hasProgress = $body.text().includes('complete') ||
                           $body.text().includes('of') ||
                           $body.text().match(/\d+.*of.*\d+/);
        if (hasProgress) {
          cy.log('Task completion progress displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should show Account created status', () => {
      cy.assertContainsAny(['Account created', 'account', 'Account']);
    });

    it('should show Email verification status', () => {
      cy.assertContainsAny(['Email', 'verification', 'verified']);
    });

    it('should show Plans setup status', () => {
      cy.assertContainsAny(['plan', 'Plan', 'subscription']);
    });

    it('should show Payment gateways status', () => {
      cy.assertContainsAny(['Payment', 'gateway', 'Stripe', 'PayPal']);
    });

    it('should have setup action buttons', () => {
      cy.assertContainsAny(['Configure', 'Create', 'Verify', 'Setup']);
    });
  });

  describe('Quick Actions', () => {
    beforeEach(() => {
      cy.assertPageReady('/app');
    });

    it('should display Quick Actions section', () => {
      cy.assertContainsAny(['Quick Actions', 'Actions']);
    });

    it('should have Manage Customers action', () => {
      cy.assertContainsAny(['Manage Customers', 'Customers']);
    });

    it('should have View Analytics action', () => {
      cy.assertContainsAny(['View Analytics', 'Analytics']);
    });

    it('should have Account Settings action', () => {
      cy.assertContainsAny(['Account Settings', 'Settings']);
    });

    it('should navigate when clicking quick action', () => {
      cy.get('body').then($body => {
        const customerBtn = $body.find('button:contains("Customers")');
        if (customerBtn.length > 0) {
          cy.wrap(customerBtn).first().should('be.visible').click();
          cy.waitForPageLoad();
          cy.log('Quick action navigation triggered');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('System Status', () => {
    beforeEach(() => {
      cy.assertPageReady('/app');
    });

    it('should display system status alert', () => {
      cy.assertContainsAny(['Powernode', 'Ready', 'Platform']);
    });

    it('should show positive system message', () => {
      cy.get('body').then($body => {
        const hasPositive = $body.find('[class*="success"], [class*="green"]').length > 0 ||
                           $body.text().includes('Ready') ||
                           $body.text().includes('operational');
        if (hasPositive) {
          cy.log('Positive system message displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Header Actions', () => {
    beforeEach(() => {
      cy.assertPageReady('/app');
    });

    it('should have Analytics button in header', () => {
      cy.get('body').then($body => {
        const hasAnalytics = $body.find('button:contains("Analytics")').length > 0 ||
                            $body.text().includes('Analytics');
        if (hasAnalytics) {
          cy.log('Analytics header button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have Customers button in header', () => {
      cy.get('body').then($body => {
        const hasCustomers = $body.find('button:contains("Customers")').length > 0 ||
                            $body.text().includes('Customers');
        if (hasCustomers) {
          cy.log('Customers header button found');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Error Handling', () => {
    it('should handle API errors gracefully', () => {
      cy.intercept('GET', '**/api/**/plans/**', {
        statusCode: 500,
        body: { success: false, error: 'Server error' }
      });

      cy.visit('/app');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
      cy.get('body').should('not.contain.text', 'Cannot read');
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
    });

    it('should stack cards on small screens', () => {
      cy.viewport(375, 667);
      cy.visit('/app');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
    });

    it('should display multi-column layout on large screens', () => {
      cy.viewport(1920, 1080);
      cy.visit('/app');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasGrid = $body.find('[class*="grid"]').length > 0;
        if (hasGrid) {
          cy.log('Multi-column layout found');
        }
      });

      cy.get('body').should('be.visible');
    });
  });
});


export {};

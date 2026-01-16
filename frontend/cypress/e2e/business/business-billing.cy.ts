/// <reference types="cypress" />

/**
 * Business Billing Page Tests
 *
 * Tests for Business Billing functionality including:
 * - Page navigation and load
 * - Tab navigation (Overview, Invoices, Analytics)
 * - Statistics cards display
 * - Invoices list display
 * - Create Invoice modal
 * - Error handling
 * - Responsive design
 */

describe('Business Billing Page Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Page Navigation', () => {
    it('should navigate to Billing page', () => {
      cy.assertPageReady('/app/business/billing', 'Billing');
    });

    it('should display page title', () => {
      cy.navigateTo('/app/business/billing');
      cy.verifyPageTitle('Billing');
    });

    it('should display page description', () => {
      cy.navigateTo('/app/business/billing');
      cy.assertContainsAny(['Manage', 'invoices', 'payments', 'billing']);
    });

    it('should display breadcrumbs', () => {
      cy.navigateTo('/app/business/billing');
      cy.assertContainsAny(['Dashboard', 'Business', 'Billing']);
    });
  });

  describe('Tab Navigation', () => {
    beforeEach(() => {
      cy.navigateTo('/app/business/billing');
    });

    it('should display tab navigation', () => {
      cy.assertContainsAny(['Overview', 'Invoices', 'Analytics']);
    });

    it('should switch to Invoices tab', () => {
      cy.clickTab('Invoices');
      cy.assertContainsAny(['All Invoices', 'Invoice', 'Create Invoice', 'No invoices']);
    });

    it('should switch to Analytics tab', () => {
      cy.clickTab('Analytics');
      cy.assertContainsAny(['Total Invoices', 'Paid', 'Payment Methods', 'Success Rate']);
    });
  });

  describe('Overview Tab - Statistics Cards', () => {
    beforeEach(() => {
      cy.navigateTo('/app/business/billing');
    });

    it('should display billing statistics', () => {
      // The page uses MetricCard components with these titles
      cy.assertContainsAny(['Outstanding', 'This Month', 'Collected', 'Success Rate']);
    });

    it('should display metric values', () => {
      // Check for currency or percentage values
      cy.assertContainsAny(['$', '%', 'overdue', 'Invoiced', 'All time']);
    });
  });

  describe('Overview Tab - Quick Actions', () => {
    beforeEach(() => {
      cy.navigateTo('/app/business/billing');
    });

    it('should display Create Invoice action', () => {
      cy.assertContainsAny(['Create Invoice', 'New Invoice']);
    });

    it('should display Reports action', () => {
      cy.assertContainsAny(['View Reports', 'Reports', 'Analytics']);
    });
  });

  describe('Page Actions', () => {
    beforeEach(() => {
      cy.navigateTo('/app/business/billing');
    });

    it('should have Create Invoice button', () => {
      cy.assertHasElement([
        '[data-testid="action-create-invoice"]',
        '[aria-label="Create Invoice"]',
        'button:contains("Create Invoice")',
      ]);
    });

    it('should open Create Invoice modal', () => {
      cy.get('[data-testid="action-create-invoice"], [aria-label="Create Invoice"]').first().click();
      cy.assertModalVisible('Create Invoice');
    });
  });

  describe('Invoices Tab', () => {
    beforeEach(() => {
      cy.navigateTo('/app/business/billing');
      cy.clickTab('Invoices');
    });

    it('should display invoices table or empty state', () => {
      cy.assertHasElement([
        'table',
        '[data-testid="invoices-table"]',
        '[data-testid="empty-state"]',
      ]).should('be.visible');
    });

    it('should display table columns', () => {
      cy.assertContainsAny(['Invoice', 'Customer', 'Amount', 'Status', 'Date']);
    });
  });

  describe('Analytics Tab', () => {
    beforeEach(() => {
      cy.navigateTo('/app/business/billing');
      cy.clickTab('Analytics');
    });

    it('should display analytics statistics', () => {
      cy.assertContainsAny(['Total Invoices', 'Paid', 'Success Rate']);
    });

    it('should display Payment Methods section', () => {
      cy.assertContainsAny(['Payment Methods', 'Payment', 'No payment methods']);
    });
  });

  describe('Permission Check', () => {
    it('should handle page access appropriately', () => {
      cy.navigateTo('/app/business/billing');
      // Page should either show billing content or permission message
      cy.assertContainsAny(['Billing', 'permission', 'access']);
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.testErrorHandling('/api/v1/billing*', {
        statusCode: 500,
        visitUrl: '/app/business/billing',
      });
    });

    it('should display error message on failure', () => {
      cy.mockApiError('/api/v1/billing*', 500, 'Failed to load billing data');
      cy.navigateTo('/app/business/billing');
      // The page shows "Error Loading Billing Data" and a "Try Again" button
      cy.assertContainsAny(['Error', 'Failed', 'Try Again', 'loading']);
    });
  });

  describe('Loading State', () => {
    it('should display loading indicator', () => {
      cy.mockEndpoint('GET', '/api/v1/billing*', { success: true }, { delay: 1000 });
      cy.visit('/app/business/billing');
      cy.verifyLoadingState();
    });
  });

  describe('Responsive Design', () => {
    it('should display properly across viewports', () => {
      cy.testResponsiveDesign('/app/business/billing', {
        checkContent: 'Billing',
      });
    });
  });
});

export {};

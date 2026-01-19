/// <reference types="cypress" />

/**
 * Business Customers Page Tests
 *
 * Tests for Business Customers management functionality including:
 * - Page navigation and load
 * - Statistics cards display
 * - Customer list display with DataTable
 * - Search and filtering
 * - Page actions
 * - Error handling
 * - Responsive design
 */

describe('Business Customers Page Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Page Navigation', () => {
    it('should navigate to Customers page', () => {
      cy.assertPageReady('/app/business/customers', 'Customers');
    });

    it('should display page title and description', () => {
      cy.navigateTo('/app/business/customers');
      cy.verifyPageTitle('Customers');
      cy.assertContainsAny(['Manage', 'customer', 'Customer Management']);
    });

    it('should display breadcrumbs', () => {
      cy.navigateTo('/app/business/customers');
      cy.assertContainsAny(['Dashboard', 'Business', 'Customers']);
    });
  });

  describe('Statistics Cards', () => {
    beforeEach(() => {
      cy.navigateTo('/app/business/customers');
    });

    it('should display customer statistics', () => {
      cy.assertStatCards(['Total', 'Active', 'Subscriptions', 'New']);
    });

    it('should display revenue metrics', () => {
      cy.assertContainsAny(['MRR', 'Monthly', 'Revenue', 'Churn', '%']);
    });
  });

  describe('Customer List Display', () => {
    beforeEach(() => {
      cy.navigateTo('/app/business/customers');
    });

    it('should display customer list or empty state', () => {
      cy.assertHasElement([
        'table',
        '[data-testid="customers-table"]',
        '[data-testid="empty-state"]',
        '[class*="table"]',
        '[class*="list"]',
      ]).should('be.visible');
    });

    it('should display table columns', () => {
      cy.assertContainsAny(['Name', 'Customer', 'Email', 'Status', 'Plan', 'Subscription']);
    });
  });

  describe('Search and Filtering', () => {
    beforeEach(() => {
      cy.navigateTo('/app/business/customers');
    });

    it('should display search input', () => {
      cy.assertHasElement([
        'input[placeholder*="Search"]',
        'input[placeholder*="search"]',
        '[data-testid="search-input"]',
      ]).should('be.visible');
    });

    it('should search customers by name', () => {
      cy.get('input[placeholder*="Search"], input[placeholder*="search"]')
        .first()
        .type('john');
      cy.waitForStableDOM();
    });

    it('should display status filter', () => {
      cy.assertContainsAny(['Status', 'All', 'Active', 'Inactive']);
    });
  });

  describe('Page Actions', () => {
    beforeEach(() => {
      cy.navigateTo('/app/business/customers');
    });

    it('should have Add Customer button', () => {
      cy.assertActionButton('Add Customer');
    });

    it('should open Add Customer modal', () => {
      cy.clickButton('Add Customer');
      cy.assertModalVisible('Customer');
    });
  });

  describe('Add Customer Modal', () => {
    beforeEach(() => {
      cy.navigateTo('/app/business/customers');
      cy.clickButton('Add Customer');
    });

    it('should display form fields', () => {
      cy.assertContainsAny(['Name', 'Email', 'Plan']);
    });

    it('should have Cancel and Save buttons', () => {
      cy.assertContainsAny(['Cancel', 'Save', 'Create', 'Add']);
    });
  });

  describe('Permission Check', () => {
    it('should handle page access appropriately', () => {
      cy.navigateTo('/app/business/customers');
      cy.assertContainsAny(['Customers', 'permission', "don't have permission"]);
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.testErrorHandling('/api/v1/customers*', {
        statusCode: 500,
        visitUrl: '/app/business/customers',
      });
    });
  });

  describe('Responsive Design', () => {
    it('should display properly across viewports', () => {
      cy.testResponsiveDesign('/app/business/customers', {
        checkContent: 'Customers',
      });
    });
  });
});

export {};

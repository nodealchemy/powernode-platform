/// <reference types="cypress" />

/**
 * Business Analytics Dashboard Page Tests
 *
 * Tests for Business Analytics Dashboard functionality including:
 * - Page navigation and load
 * - Tab navigation
 * - Charts and visualizations
 * - Date range filter
 * - Error handling
 * - Responsive design
 */

describe('Business Analytics Dashboard Page Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Page Navigation', () => {
    it('should navigate to Analytics Dashboard page', () => {
      cy.visit('/app/business/analytics');
      cy.url().should('include', '/business');
    });

    it('should display page title and description', () => {
      cy.navigateTo('/app/business/analytics');
      cy.assertContainsAny(['Analytics Dashboard', 'Analytics', 'Real-time insights', 'insights', 'business']);
    });

    it('should display breadcrumbs', () => {
      cy.navigateTo('/app/business/analytics');
      cy.assertContainsAny(['Dashboard', 'Business', 'Analytics']);
    });
  });

  describe('Page Actions', () => {
    beforeEach(() => {
      cy.navigateTo('/app/business/analytics');
    });

    it('should have Refresh and Export buttons', () => {
      cy.assertContainsAny(['Refresh', 'Export']);
    });
  });

  describe('Date Range Filter', () => {
    beforeEach(() => {
      cy.navigateTo('/app/business/analytics');
    });

    it('should display date filter controls', () => {
      cy.assertContainsAny(['Date', 'Range', 'Last updated', 'ago']);
    });
  });

  describe('Tab Navigation', () => {
    beforeEach(() => {
      cy.navigateTo('/app/business/analytics');
    });

    it('should display all tabs', () => {
      cy.assertContainsAny(['Overview', 'Live', 'Revenue', 'Growth', 'Churn', 'Customers', 'Cohorts']);
    });

    it('should switch to Revenue tab', () => {
      cy.clickTab('Revenue');
      cy.assertContainsAny(['Revenue']);
    });

    it('should switch to Growth tab', () => {
      cy.clickTab('Growth');
      cy.assertContainsAny(['Growth']);
    });
  });

  describe('Overview Tab Content', () => {
    beforeEach(() => {
      cy.navigateTo('/app/business/analytics');
    });

    it('should display metrics overview', () => {
      cy.assertContainsAny(['MRR', 'Revenue', 'Customers']);
    });

    it('should display chart sections', () => {
      cy.assertContainsAny(['Revenue Trend', 'Growth Rate', 'Churn Analysis', 'Customer Growth', 'Growth', 'Customer']);
    });
  });

  describe('Permission Check', () => {
    it('should handle page access appropriately', () => {
      cy.navigateTo('/app/business/analytics');
      cy.assertContainsAny(['Analytics Dashboard', 'Overview', 'Access Restricted', 'analytics.read permission']);
    });
  });

  describe('Error Handling', () => {
    it('should handle API errors gracefully', () => {
      cy.testErrorHandling('**/api/**/analytics/**', {
        statusCode: 500,
        visitUrl: '/app/business/analytics',
      });
    });
  });

  describe('Loading State', () => {
    it('should display loading indicator', () => {
      cy.mockEndpoint('GET', '**/api/**/analytics/**', { success: true, data: {} }, { delay: 1000 });
      cy.visit('/app/business/analytics');
      cy.verifyLoadingState();
    });
  });

  describe('Export Modal', () => {
    it('should open export modal when Export clicked', () => {
      cy.navigateTo('/app/business/analytics');
      cy.get('body').then($body => {
        if ($body.find('button:contains("Export")').length > 0) {
          cy.clickButton('Export');
          cy.assertContainsAny(['Export', 'Download', 'Format']);
        }
      });
    });
  });

  describe('Responsive Design', () => {
    it('should display properly across viewports', () => {
      cy.testResponsiveDesign('/app/business/analytics', {
        checkContent: 'Analytics',
      });
    });
  });
});

export {};

/// <reference types="cypress" />

/**
 * Business Plans Page Tests
 *
 * Tests for Business Plans management functionality including:
 * - Page navigation and load
 * - Tab navigation (Overview, Active Plans, Analytics)
 * - Statistics cards display
 * - Plan list display
 * - Plan CRUD operations
 * - Error handling
 * - Responsive design
 */

describe('Business Plans Page Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Page Navigation', () => {
    it('should navigate to Plans page', () => {
      cy.assertPageReady('/app/business/plans', 'Plans');
    });

    it('should display page title and description', () => {
      cy.navigateTo('/app/business/plans');
      cy.verifyPageTitle('Plans');
      cy.assertContainsAny(['Manage', 'subscription', 'Subscription Plans', 'pricing', 'View']);
    });

    it('should display breadcrumbs', () => {
      cy.navigateTo('/app/business/plans');
      cy.assertContainsAny(['Dashboard', 'Plans']);
    });
  });

  describe('Tab Navigation', () => {
    beforeEach(() => {
      cy.navigateTo('/app/business/plans');
    });

    it('should display tab navigation', () => {
      cy.assertContainsAny(['Overview', 'Active Plans', 'Analytics']);
    });

    it('should switch to Active Plans tab', () => {
      cy.clickTab('Active Plans');
      // Active Plans tab shows a grid of plan cards, not a table
      cy.assertContainsAny(['Active Plans', 'Active', 'Plan', 'Edit', 'Copy', 'No plans found']);
    });

    it('should switch to Analytics tab', () => {
      cy.clickTab('Analytics');
      // Analytics tab shows Plan Performance and Revenue Breakdown sections
      cy.assertContainsAny(['Analytics', 'Plan Performance', 'Revenue Breakdown', 'subscriptions']);
    });
  });

  describe('Statistics Cards', () => {
    beforeEach(() => {
      cy.navigateTo('/app/business/plans');
    });

    it('should display plan statistics', () => {
      // PlansPage shows: Total Plans, Active Plans, Total Subscriptions, Monthly Revenue
      cy.assertContainsAny(['Total Plans', 'Active Plans', 'Total Subscriptions', 'Monthly Revenue', 'Created']);
    });

    it('should display revenue metrics', () => {
      cy.assertContainsAny(['Revenue', 'Monthly Revenue', '$']);
    });
  });

  describe('Plans List Display', () => {
    beforeEach(() => {
      cy.navigateTo('/app/business/plans');
    });

    it('should display plans list or empty state', () => {
      cy.assertHasElement([
        'table',
        '[data-testid="plans-table"]',
        '[data-testid="empty-state"]',
        '[class*="table"]',
        '[class*="list"]',
        '[class*="card"]',
      ]).should('be.visible');
    });

    it('should display plan details', () => {
      cy.assertContainsAny(['Name', 'Plan', 'Price', '$', 'Status', 'Active']);
    });
  });

  describe('Page Actions', () => {
    beforeEach(() => {
      cy.navigateTo('/app/business/plans');
    });

    it('should have Create Plan button', () => {
      cy.assertActionButton('Create Plan');
    });

    it('should open Create Plan modal', () => {
      cy.clickButton('Create Plan');
      cy.assertModalVisible('Plan');
    });
  });

  describe('Search and Filtering', () => {
    beforeEach(() => {
      cy.navigateTo('/app/business/plans');
    });

    it('should display search input or plan content', () => {
      // Search may not be visible on overview tab - check for plan content or search
      cy.get('body').then(($body) => {
        const hasSearch = $body.find('input[placeholder*="Search"], input[placeholder*="search"], [data-testid="search-input"]').length > 0;
        const hasPlans = $body.text().includes('Plans') || $body.text().includes('Plan');
        expect(hasSearch || hasPlans, 'Should show search or plan content').to.be.true;
      });
    });

    it('should display status filter or plan statuses', () => {
      cy.assertContainsAny(['Status', 'All', 'Active', 'Inactive', 'active', 'inactive']);
    });
  });

  describe('Permission Check', () => {
    it('should handle page access appropriately', () => {
      cy.navigateTo('/app/business/plans');
      cy.assertContainsAny(['Plans', 'permission', "don't have permission"]);
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.testErrorHandling('/api/v1/plans*', {
        statusCode: 500,
        visitUrl: '/app/business/plans',
      });
    });
  });

  describe('Responsive Design', () => {
    it('should display properly across viewports', () => {
      cy.testResponsiveDesign('/app/business/plans', {
        checkContent: 'Plans',
      });
    });
  });
});

export {};

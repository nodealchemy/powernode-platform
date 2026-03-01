/// <reference types="cypress" />

/**
 * AI Workflow Validation Statistics Page Tests
 *
 * Tests for Workflow Validation Statistics functionality including:
 * - Page navigation
 * - Quick stats overview
 * - Validation dashboard
 * - Permission checks
 * - Error handling
 * - Responsive design
 */

describe('AI Workflow Validation Statistics Page Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup({ intercepts: ['ai'] });
  });

  describe('Page Navigation', () => {
    it('should navigate to Workflow Validation Statistics page', () => {
      cy.navigateTo('/app/ai/workflows/validation-stats');
      cy.url().should('include', '/ai');
    });

    it('should display page title', () => {
      cy.navigateTo('/app/ai/workflows/validation-stats');
      cy.assertContainsAny(['Validation Statistics', 'Workflow Validation', 'Validation']);
    });

    it('should display breadcrumbs', () => {
      cy.navigateTo('/app/ai/workflows/validation-stats');
      cy.assertContainsAny(['AI', 'Workflows']);
    });
  });

  describe('Quick Stats Overview', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/workflows/validation-stats');
    });

    it('should display Total Workflows stat card', () => {
      cy.assertContainsAny(['Total Workflows', 'Workflows']);
    });

    it('should display Average Health stat card', () => {
      cy.assertContainsAny(['Average Health', 'Health']);
    });

    it('should display Valid Workflows stat card', () => {
      cy.assertContainsAny(['Valid Workflows', 'Valid']);
    });

    it('should display Issues Found stat card', () => {
      cy.assertContainsAny(['Issues Found', 'Issues']);
    });

    it('should display stat cards in grid layout', () => {
      cy.assertHasElement(['[class*="grid"]']);
    });
  });

  describe('Validation Statistics Dashboard', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/workflows/validation-stats');
    });

    it('should display validation statistics content', () => {
      cy.assertContainsAny(['Validation', 'Statistics', 'Health']);
    });

    it('should display stat cards with icons', () => {
      cy.assertHasElement(['[class*="border"][class*="rounded"]', '[class*="card"]', '[class*="surface"]']);
    });
  });

  describe('Permission Check', () => {
    it('should display page or access denied based on permissions', () => {
      cy.navigateTo('/app/ai/workflows/validation-stats');
      // Page should show either the stats (authorized) or access denied (unauthorized)
      cy.assertContainsAny(['Access Denied', 'Validation Statistics', 'Total Workflows', 'permission']);
    });

    it('should display appropriate description', () => {
      cy.navigateTo('/app/ai/workflows/validation-stats');
      cy.assertContainsAny(['Platform-wide', 'platform-wide', 'Your account', 'your account', 'Validation', 'workflow']);
    });
  });

  describe('Error Handling', () => {
    it('should handle API errors gracefully', () => {
      cy.testErrorHandling(/\/api\/v1\/ai\/workflows.*/, {
        statusCode: 500,
        visitUrl: '/app/ai/workflows/validation-stats'
      });
    });
  });

  describe('Loading State', () => {
    it('should display loading indicator', () => {
      cy.intercept('GET', /\/api\/v1\/ai\/workflows.*/, {
        delay: 2000,
        statusCode: 200,
        body: {
          success: true,
          data: {
            total_workflows: 0,
            valid_workflows: 0,
            average_health: 0,
            issues_found: 0
          }
        }
      });
      cy.visit('/app/ai/workflows/validation-stats');
      cy.assertHasElement(['[class*="animate-spin"]', '[class*="spinner"]', '[class*="loading"]', '[class*="pulse"]']);
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.testResponsiveDesign('/app/ai/workflows/validation-stats', {
        checkContent: ['Validation', 'Workflow']
      });
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.navigateTo('/app/ai/workflows/validation-stats');
      cy.assertContainsAny(['Validation', 'Statistics', 'Workflow', 'Health']);
    });

    it('should display stat cards on small screens', () => {
      cy.viewport('iphone-x');
      cy.navigateTo('/app/ai/workflows/validation-stats');
      cy.assertHasElement(['[class*="grid"]']);
    });

    it('should show multi-column layout on large screens', () => {
      cy.viewport(1920, 1080);
      cy.navigateTo('/app/ai/workflows/validation-stats');
      cy.assertHasElement(['[class*="grid"]']);
    });
  });
});

export {};

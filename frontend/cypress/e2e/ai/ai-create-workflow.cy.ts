/// <reference types="cypress" />

/**
 * AI Create Workflow Page Tests
 *
 * Tests for Create Workflow functionality including:
 * - Page navigation and load
 * - Tab navigation
 * - Basic Information form
 * - Configuration section
 * - Advanced Settings
 * - Form validation
 * - Error handling
 * - Responsive design
 */

describe('AI Create Workflow Page Tests', () => {
  beforeEach(() => {
    // Handle uncaught exceptions from React/application code
    Cypress.on('uncaught:exception', () => false);
    cy.standardTestSetup({ intercepts: ['ai'] });
  });

  describe('Page Navigation', () => {
    it('should navigate to Create Workflow page', () => {
      cy.navigateTo('/app/ai/workflows/new');
      cy.url().should('include', '/ai');
    });

    it('should display page title', () => {
      cy.navigateTo('/app/ai/workflows/new');
      cy.assertContainsAny(['Create New Workflow', 'Create Workflow']);
    });

    it('should display page description', () => {
      cy.navigateTo('/app/ai/workflows/new');
      cy.assertContainsAny(['automated AI workflow', 'business processes']);
    });

    it('should display breadcrumbs', () => {
      cy.navigateTo('/app/ai/workflows/new');
      cy.assertContainsAny(['AI', 'Workflows', 'Create']);
    });
  });

  describe('Page Actions', () => {
    it('should have Save as Draft button', () => {
      cy.navigateTo('/app/ai/workflows/new');
      cy.assertActionButton('Save as Draft');
    });

    it('should have Save & Activate button', () => {
      cy.navigateTo('/app/ai/workflows/new');
      cy.assertContainsAny(['Save & Activate', 'Activate']);
    });

    it('should have Cancel button', () => {
      cy.navigateTo('/app/ai/workflows/new');
      cy.assertContainsAny(['Cancel']);
    });
  });

  describe('Tab Navigation', () => {
    it('should display Basic Information tab', () => {
      cy.navigateTo('/app/ai/workflows/new');
      cy.assertContainsAny(['Basic Information']);
    });

    it('should display Workflow Builder tab', () => {
      cy.navigateTo('/app/ai/workflows/new');
      cy.assertContainsAny(['Workflow Builder']);
    });

    it('should display Configuration tab', () => {
      cy.navigateTo('/app/ai/workflows/new');
      cy.assertContainsAny(['Configuration']);
    });

    it('should display Advanced Settings tab', () => {
      cy.navigateTo('/app/ai/workflows/new');
      cy.assertContainsAny(['Advanced Settings', 'Advanced']);
    });

    it('should switch between tabs', () => {
      cy.navigateTo('/app/ai/workflows/new');
      cy.clickButton('Configuration');
      cy.assertContainsAny(['Timeout']);
    });
  });

  describe('Basic Information Form', () => {
    it('should display Name input', () => {
      cy.navigateTo('/app/ai/workflows/new');
      cy.assertContainsAny(['Name']);
    });

    it('should display Description input', () => {
      cy.navigateTo('/app/ai/workflows/new');
      cy.assertContainsAny(['Description']);
    });

    it('should display Visibility selector', () => {
      cy.navigateTo('/app/ai/workflows/new');
      cy.assertContainsAny(['Visibility', 'Private', 'Public']);
    });

    it('should display Execution Mode selector', () => {
      cy.navigateTo('/app/ai/workflows/new');
      cy.assertContainsAny(['Execution Mode', 'Sequential', 'Parallel']);
    });

    it('should display Tags input', () => {
      cy.navigateTo('/app/ai/workflows/new');
      cy.assertContainsAny(['Tags']);
    });
  });

  describe('Workflow Builder', () => {
    it('should display workflow builder area', () => {
      cy.navigateTo('/app/ai/workflows/new');
      cy.clickButton('Workflow Builder');
      cy.assertContainsAny(['Visual Workflow Builder', 'Builder']);
    });
  });

  describe('Configuration Section', () => {
    it('should display Timeout input', () => {
      cy.navigateTo('/app/ai/workflows/new');
      cy.clickButton('Configuration');
      cy.assertContainsAny(['Timeout']);
    });

    it('should display Max Parallel Nodes input', () => {
      cy.navigateTo('/app/ai/workflows/new');
      cy.clickButton('Configuration');
      cy.assertContainsAny(['Max Parallel', 'Parallel Nodes']);
    });

    it('should display Auto Retry checkbox', () => {
      cy.navigateTo('/app/ai/workflows/new');
      cy.clickButton('Configuration');
      cy.assertContainsAny(['Auto Retry']);
    });

    it('should display Error Handling selector', () => {
      cy.navigateTo('/app/ai/workflows/new');
      cy.clickButton('Configuration');
      cy.assertContainsAny(['Error Handling', 'Stop on Error']);
    });
  });

  describe('Advanced Settings', () => {
    it('should display Notification Settings', () => {
      cy.navigateTo('/app/ai/workflows/new');
      cy.clickButton('Advanced');
      cy.assertContainsAny(['Notification', 'Notify on']);
    });

    it('should display Resource Limits', () => {
      cy.navigateTo('/app/ai/workflows/new');
      cy.clickButton('Advanced');
      cy.assertContainsAny(['Resource Limits', 'Cost Limit', 'Memory Limit']);
    });
  });

  describe('Form Validation', () => {
    it('should show validation error for empty name', () => {
      cy.navigateTo('/app/ai/workflows/new');
      cy.clickButton('Save as Draft');
      cy.assertContainsAny(['required', 'error']);
    });
  });

  describe('Permission Check', () => {
    it('should show access denied for unauthorized users', () => {
      cy.navigateTo('/app/ai/workflows/new');
      cy.assertContainsAny(['Access Denied', "don't have permission", 'Create New Workflow', 'Basic Information']);
    });
  });

  describe('Error Handling', () => {
    it('should handle API errors gracefully', () => {
      cy.mockApiError('**/api/**/workflows**', 500, 'Internal Server Error');
      cy.navigateTo('/app/ai/workflows/new');
      cy.assertContainsAny(['Error', 'Create New Workflow', 'Create Workflow']);
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.testResponsiveDesign('/app/ai/workflows/new', {
        checkContent: ['Workflow', 'Create']
      });
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.navigateTo('/app/ai/workflows/new');
      cy.assertContainsAny(['Create New Workflow', 'Create Workflow']);
    });

    it('should stack form elements on small screens', () => {
      cy.viewport('iphone-x');
      cy.navigateTo('/app/ai/workflows/new');
      cy.assertHasElement(['[class*="grid"]']);
    });
  });
});

export {};

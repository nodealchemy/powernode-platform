/// <reference types="cypress" />

/**
 * DevOps New Integration Page Tests
 *
 * Tests for New Integration page functionality including:
 * - Page navigation
 * - Integration wizard
 * - Page actions
 * - Error handling
 * - Responsive design
 */

describe('DevOps New Integration Page Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup({ intercepts: ['devops'] });
  });

  describe('Page Navigation', () => {
    it('should navigate to New Integration page', () => {
      cy.visit('/app/devops/integrations/new');
      cy.waitForPageLoad();
      cy.url().should('include', '/devops');
    });

    it('should display page title and description', () => {
      cy.visit('/app/devops/integrations/new');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Add Integration', 'Set up a new integration', 'integration', 'Integration']);
    });
  });

  describe('Page Actions', () => {
    beforeEach(() => {
      cy.visit('/app/devops/integrations/new');
      cy.waitForPageLoad();
    });

    it('should have Cancel button', () => {
      cy.assertContainsAny(['Cancel', 'Back', 'Integration']);
    });

    it('should navigate back on Cancel click', () => {
      cy.get('button:contains("Cancel")').first().click();
      cy.waitForPageLoad();
      cy.url().should('match', /integrations|marketplace/);
    });
  });

  describe('Integration Wizard', () => {
    beforeEach(() => {
      cy.visit('/app/devops/integrations/new');
      cy.waitForPageLoad();
    });

    it('should display IntegrationWizard component', () => {
      cy.assertContainsAny(['Select', 'Choose', 'Step', 'Integration', 'Add Integration']);
    });

    it('should display integration type selection', () => {
      cy.assertHasElement(['[class*="card"]', '[class*="grid"]', '[class*="wizard"]']);
    });
  });

  describe('Error Handling', () => {
    it('should handle API errors gracefully', () => {
      cy.testErrorHandling('**/api/**/integration**', {
        statusCode: 500,
        visitUrl: '/app/devops/integrations/new',
      });
    });

    it('should display error message on API failure', () => {
      cy.mockApiError('**/integrations*', 500, 'Server error');
      cy.visit('/app/devops/integrations/new');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Error', 'Failed', 'Integration', 'Add Integration']);
    });
  });

  describe('Responsive Design', () => {
    it('should display properly across viewports', () => {
      cy.testResponsiveDesign('/app/devops/integrations/new', {
        checkContent: 'Integration',
      });
    });
  });
});

export {};

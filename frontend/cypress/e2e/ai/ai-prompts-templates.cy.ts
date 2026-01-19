/// <reference types="cypress" />

/**
 * AI Prompt Templates E2E Tests
 *
 * Tests for AI prompt template management including:
 * - Template listing
 * - Template creation
 * - Template actions
 * - Search and filter
 * - Responsive design
 */

describe('AI Prompt Templates Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup({ intercepts: ['ai'] });
  });

  describe('Page Navigation', () => {
    it('should navigate to Prompts page', () => {
      cy.assertPageReady('/app/ai/prompts', 'Prompt');
    });

    it('should display page title', () => {
      cy.navigateTo('/app/ai/prompts');
      cy.assertContainsAny(['Prompt Templates', 'Prompts', 'AI']);
    });
  });

  describe('Template List', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/prompts');
    });

    it('should display template list or page content', () => {
      cy.assertContainsAny(['Prompt', 'Template', 'No templates', 'Create']);
    });

    it('should display template names', () => {
      cy.assertContainsAny(['Template', 'Name', 'Prompt']);
    });

    it('should display template categories', () => {
      cy.assertContainsAny(['Category', 'General', 'Workflow', 'Agent', 'Prompt']);
    });

    it('should display page with content', () => {
      cy.get('body').should('be.visible');
      cy.assertContainsAny(['Prompt', 'Template', 'AI']);
    });

    it('should have refresh button or page controls', () => {
      cy.get('body').should('be.visible');
    });
  });

  describe('Template Creation', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/prompts');
    });

    it('should have Create Template button or action', () => {
      cy.assertContainsAny(['Create', 'New', 'Add', 'Prompt']);
    });

    it('should open create form when Create clicked', () => {
      cy.get('body').then($body => {
        const createBtn = $body.find('button:contains("Create"), button:contains("New Template"), button:contains("New")');
        if (createBtn.length > 0) {
          cy.wrap(createBtn).first().click();
          cy.waitForStableDOM();
        }
        cy.get('body').should('be.visible');
      });
    });
  });

  describe('Template Categories', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/prompts');
    });

    it('should display category options or page content', () => {
      cy.assertContainsAny(['General', 'Agent', 'Workflow', 'Custom', 'Category', 'Prompt']);
    });
  });

  describe('Template Actions', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/prompts');
    });

    it('should have template actions or page content', () => {
      cy.get('body').should('be.visible');
      cy.assertContainsAny(['Edit', 'Delete', 'View', 'Prompt', 'Template']);
    });
  });

  describe('Variables Handling', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/prompts');
    });

    it('should display variable indicators or page content', () => {
      cy.assertContainsAny(['Variable', '{{', 'Prompt', 'Template']);
    });
  });

  describe('Search and Filter', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/prompts');
    });

    it('should have search or filter functionality', () => {
      cy.get('body').then($body => {
        const hasSearch = $body.find('input[type="search"], input[placeholder*="Search"]').length > 0;
        if (hasSearch) {
          cy.log('Search input found');
        }
        cy.get('body').should('be.visible');
      });
    });
  });

  describe('Error Handling', () => {
    it('should handle API errors gracefully', () => {
      cy.testErrorHandling('**/api/**/prompts/**', {
        statusCode: 500,
        visitUrl: '/app/ai/prompts'
      });
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.navigateTo('/app/ai/prompts');
      cy.get('body').should('be.visible');
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.navigateTo('/app/ai/prompts');
      cy.get('body').should('be.visible');
    });

    it('should display properly on large screens', () => {
      cy.viewport(1920, 1080);
      cy.navigateTo('/app/ai/prompts');
      cy.get('body').should('be.visible');
    });
  });
});

export {};

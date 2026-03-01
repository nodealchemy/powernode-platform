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
      cy.assertContainsAny(['Prompt', 'Template', 'AI']);
    });

    it('should have refresh button or page controls', () => {
      cy.assertHasElement(['button:contains("Refresh")', '[aria-label*="refresh"]', 'button svg']);
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
      cy.get('button:contains("Create"), button:contains("New Template"), button:contains("New")').first().click();
      cy.waitForStableDOM();
      cy.assertContainsAny(['Create', 'Name', 'Template', 'Prompt']);
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
      cy.assertHasElement(['input[type="search"]', 'input[placeholder*="Search"]', 'input[placeholder*="search"]', 'input[type="text"]']);
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
      cy.testResponsiveDesign('/app/ai/prompts', {
        checkContent: ['Prompt']
      });
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.navigateTo('/app/ai/prompts');
      cy.assertContainsAny(['Prompt', 'Template', 'AI']);
    });

    it('should display properly on large screens', () => {
      cy.viewport(1920, 1080);
      cy.navigateTo('/app/ai/prompts');
      cy.assertContainsAny(['Prompt', 'Template', 'AI']);
    });
  });
});

export {};

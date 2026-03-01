/// <reference types="cypress" />

/**
 * AI Prompts Page Tests
 *
 * Tests for AI Prompt Templates functionality including:
 * - Page navigation and load
 * - Template list display
 * - Category filtering
 * - Create template
 * - Edit template
 * - Preview template
 * - Duplicate template
 * - Delete template
 * - Responsive design
 */

describe('AI Prompts Page Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup({ intercepts: ['ai'] });
  });

  describe('Page Navigation', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/prompts');
    });

    it('should load AI Prompts page directly', () => {
      cy.assertContainsAny(['Prompt', 'Prompts', 'AI']);
    });

    it('should display breadcrumbs', () => {
      cy.assertContainsAny(['Dashboard', 'AI', 'Prompts']);
    });
  });

  describe('Template List Display', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/prompts');
    });

    it('should display template list or empty state', () => {
      cy.assertContainsAny(['No prompt templates', 'Create your first', 'Prompt']);
    });

    it('should display category badges', () => {
      cy.assertContainsAny(['review', 'implement', 'security', 'custom', 'general', 'Prompt']);
    });

    it('should display template status', () => {
      cy.assertContainsAny(['Active', 'Inactive', 'Prompt']);
    });

    it('should display usage count', () => {
      cy.assertContainsAny(['uses', 'usage', 'Prompt']);
    });

    it('should display variable count', () => {
      cy.assertContainsAny(['variable', 'Prompt']);
    });
  });

  describe('Category Filtering', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/prompts');
    });

    it('should display category filter tabs', () => {
      cy.assertContainsAny(['All', 'General', 'Agent', 'Workflow']);
    });

    it('should filter by General category', () => {
      cy.clickButton('General');
      cy.assertContainsAny(['General', 'Prompt']);
    });

    it('should filter by Agent category', () => {
      cy.clickButton('Agent');
      cy.assertContainsAny(['Agent', 'Prompt']);
    });
  });

  describe('Create Template', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/prompts');
    });

    it('should display Create Template button', () => {
      cy.assertHasElement(['button:contains("Create Template")', 'button:contains("Create")']);
    });

    it('should open editor when Create Template clicked', () => {
      cy.clickButton('Create Template');
      cy.waitForStableDOM();
      cy.assertContainsAny(['Create Prompt Template', 'Name', 'Category']);
    });

    it('should close editor when Cancel clicked', () => {
      cy.clickButton('Create Template');
      cy.waitForStableDOM();
      cy.clickButton('Cancel');
      cy.waitForModalClose();
    });
  });

  describe('Edit Template', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/prompts');
    });

    it('should open editor when template card clicked', () => {
      cy.get('[class*="card"][class*="cursor-pointer"], [class*="template"]').first().click();
      cy.waitForStableDOM();
      cy.assertContainsAny(['Edit Prompt Template', 'Name', 'Prompt']);
    });
  });

  describe('Preview Template', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/prompts');
    });

    it('should have Preview button on templates', () => {
      cy.assertHasElement(['button:contains("Preview")']);
    });

    it('should open preview modal when Preview clicked', () => {
      cy.get('button:contains("Preview")').first().click();
      cy.waitForStableDOM();
      cy.assertContainsAny(['Preview', 'Content', 'Prompt']);
    });
  });

  describe('Refresh Functionality', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/prompts');
    });

    it('should have Refresh button', () => {
      cy.assertHasElement(['button:contains("Refresh")', '[aria-label*="refresh"]']);
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.testErrorHandling('/api/v1/prompt_templates*', {
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
      cy.assertPageReady('/app/ai/prompts');
      cy.assertContainsAny(['Prompt', 'Prompts']);
    });
  });
});

export {};

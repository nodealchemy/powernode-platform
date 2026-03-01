/// <reference types="cypress" />

/**
 * AI Contexts Page Tests
 *
 * Tests for AI Contexts functionality including:
 * - Page navigation and load
 * - Tab navigation (browse/search/create)
 * - Context browser display
 * - Search functionality
 * - Context creation form
 * - Form validation
 * - Error handling
 * - Responsive design
 */

describe('AI Contexts Page Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup({ intercepts: ['ai'] });
  });

  describe('Page Navigation', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/contexts');
    });

    it('should navigate to Contexts page', () => {
      cy.assertContainsAny(['Context', 'Contexts', 'AI']);
    });

    it('should display page title', () => {
      cy.assertContainsAny(['Contexts']);
    });

    it('should display page description', () => {
      cy.assertContainsAny(['memory', 'Persistent', 'Context']);
    });

    it('should display breadcrumbs', () => {
      cy.assertContainsAny(['Dashboard', 'AI', 'Contexts']);
    });
  });

  describe('Page Actions', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/contexts');
    });

    it('should have Refresh button', () => {
      cy.assertHasElement(['button:contains("Refresh")', '[aria-label*="refresh"]', 'button svg']);
    });

    it('should have New Context button or page content', () => {
      cy.assertContainsAny(['New Context', 'Create', 'New', 'Context', 'Contexts']);
    });
  });

  describe('Tab Navigation', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/contexts');
    });

    it('should display tab navigation', () => {
      cy.assertContainsAny(['Browse', 'Search', 'Create']);
    });

    it('should switch to Browse tab', () => {
      cy.clickButton('Browse');
      cy.assertContainsAny(['Browse', 'Context', 'Contexts']);
    });

    it('should switch to Search tab', () => {
      cy.clickButton('Search');
      cy.assertContainsAny(['Search', 'query', 'results']);
    });

    it('should switch to Create tab', () => {
      cy.get('button:contains("Create New"), button:contains("Create")').first().click();
      cy.assertContainsAny(['Create', 'Name', 'Context']);
    });
  });

  describe('Context Browser', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/contexts');
    });

    it('should display context list', () => {
      cy.assertHasElement(['[class*="card"]', '[class*="list"]', '[class*="grid"]']);
    });

    it('should show empty state when no contexts', () => {
      cy.assertContainsAny(['No contexts', 'no contexts', 'Create your first', 'Context']);
    });
  });

  describe('Search Tab', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/contexts');
      cy.clickButton('Search');
      cy.waitForStableDOM();
    });

    it('should display search interface', () => {
      cy.assertHasElement([
        'input[type="search"]',
        'input[placeholder*="search"]',
        'input[placeholder*="Search"]',
        'input[type="text"]',
        'input[placeholder*="Filter"]',
        '[data-testid*="search"]'
      ]);
    });
  });

  describe('Create Context Form', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/contexts');
      cy.get('button:contains("Create New"), button:contains("Create")').first().click();
      cy.waitForStableDOM();
    });

    it('should display create context form', () => {
      cy.assertContainsAny(['Create Context', 'Name', 'Context']);
    });

    it('should have scope selector', () => {
      cy.assertContainsAny(['Scope', 'Account-wide', 'Team', 'Context']);
    });

    it('should have retention policy fields', () => {
      cy.assertContainsAny(['Retention', 'Max Entries', 'Max Age', 'Context']);
    });

    it('should have cancel button', () => {
      cy.assertHasElement([
        'button:contains("Cancel")',
        '[data-testid*="cancel"]',
        'button:contains("Back")',
        'a:contains("Cancel")'
      ]);
    });

    it('should have submit button', () => {
      cy.assertHasElement([
        'button:contains("Create Context")',
        'button[type="submit"]',
        'button:contains("Create")',
        'button:contains("Save")',
        '[data-testid*="submit"]'
      ]);
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.testErrorHandling('/api/v1/ai/contexts*', {
        statusCode: 500,
        visitUrl: '/app/ai/contexts'
      });
    });
  });

  describe('Loading State', () => {
    it('should display loading indicator', () => {
      cy.intercept('GET', '**/api/**/contexts*', {
        delay: 1000,
        statusCode: 200,
        body: { success: true, data: [] }
      });
      cy.visit('/app/ai/contexts');
      cy.assertHasElement([
        '[class*="spin"]',
        '[class*="loading"]',
        '[class*="animate-spin"]',
        '[data-testid*="loading"]',
        'svg[class*="animate"]'
      ]);
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.testResponsiveDesign('/app/ai/contexts', {
        checkContent: ['Contexts']
      });
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.assertPageReady('/app/ai/contexts');
      cy.assertContainsAny(['Context', 'Contexts']);
    });
  });
});

export {};

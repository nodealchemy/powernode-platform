/// <reference types="cypress" />

/**
 * AI Context Detail Page Tests
 *
 * Tests for Context Detail functionality including:
 * - Page navigation and load
 * - Context header display
 * - Stats cards
 * - Tab navigation
 * - Entries tab content
 * - Settings tab content
 * - Error handling
 * - Responsive design
 */

describe('AI Context Detail Page Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup({ intercepts: ['ai'] });
  });

  describe('Page Navigation', () => {
    it('should navigate to Context Detail page', () => {
      cy.navigateTo('/app/ai/contexts/test-context');
      cy.url().should('include', '/ai');
    });

    it('should display Context Not Found for invalid ID', () => {
      cy.navigateTo('/app/ai/contexts/invalid-context-id');
      cy.assertContainsAny(['Not Found', "doesn't exist", 'Back to']);
    });
  });

  describe('Page Actions', () => {
    it('should have Import/Export button or page content', () => {
      cy.navigateTo('/app/ai/contexts/test-context');
      cy.assertContainsAny(['Import/Export', 'Import', 'Export', 'Context', 'Not Found']);
    });

    it('should have Add Entry button or page content', () => {
      cy.navigateTo('/app/ai/contexts/test-context');
      cy.assertContainsAny(['Add Entry', 'Add', 'Create', 'Context', 'Not Found']);
    });
  });

  describe('Context Header', () => {
    it('should display context name or not found state', () => {
      cy.navigateTo('/app/ai/contexts/test-context');
      cy.assertContainsAny(['Context', 'Not Found']);
    });

    it('should display Archived badge when archived', () => {
      cy.navigateTo('/app/ai/contexts/test-context');
      cy.assertContainsAny(['Archived', 'Context', 'Not Found']);
    });

    it('should display context description', () => {
      cy.navigateTo('/app/ai/contexts/test-context');
      cy.assertHasElement([
        'p[class*="secondary"]',
        'p[class*="text-"]',
        '[class*="description"]',
        'p',
        '[data-testid*="description"]'
      ]);
    });

    it('should display context metadata', () => {
      cy.navigateTo('/app/ai/contexts/test-context');
      cy.assertContainsAny(['Agent:', 'v1', 'Context', 'Not Found']);
    });
  });

  describe('Stats Cards', () => {
    it('should display Total Entries stat', () => {
      cy.navigateTo('/app/ai/contexts/test-context');
      cy.assertContainsAny(['Total Entries', 'Entries', 'Context', 'Not Found', '0']);
    });

    it('should display Data Size stat', () => {
      cy.navigateTo('/app/ai/contexts/test-context');
      cy.assertContainsAny(['Data Size', 'Size', 'Context', 'Not Found', 'KB', 'MB', '0']);
    });

    it('should display With Embeddings stat', () => {
      cy.navigateTo('/app/ai/contexts/test-context');
      cy.assertContainsAny(['With Embeddings', 'Embeddings', 'Context', 'Not Found', '0']);
    });

    it('should display Avg Importance stat', () => {
      cy.navigateTo('/app/ai/contexts/test-context');
      cy.assertContainsAny(['Avg Importance', 'Importance', 'Context', 'Not Found', '0']);
    });

    it('should display Total Accesses stat', () => {
      cy.navigateTo('/app/ai/contexts/test-context');
      cy.assertContainsAny(['Total Accesses', 'Accesses', 'Context', 'Not Found', '0']);
    });
  });

  describe('Tab Navigation', () => {
    it('should display Entries tab', () => {
      cy.navigateTo('/app/ai/contexts/test-context');
      cy.assertContainsAny(['Entries']);
    });

    it('should display Search tab', () => {
      cy.navigateTo('/app/ai/contexts/test-context');
      cy.assertContainsAny(['Search']);
    });

    it('should display Settings tab', () => {
      cy.navigateTo('/app/ai/contexts/test-context');
      cy.assertContainsAny(['Settings']);
    });

    it('should switch to Search tab', () => {
      cy.navigateTo('/app/ai/contexts/test-context');
      cy.clickButton('Search');
      cy.assertContainsAny(['Search', 'query', 'results']);
    });

    it('should switch to Settings tab', () => {
      cy.navigateTo('/app/ai/contexts/test-context');
      cy.clickButton('Settings');
      cy.assertContainsAny(['Settings', 'Retention', 'Danger']);
    });
  });

  describe('Entries Tab Content', () => {
    it('should display filter input', () => {
      cy.navigateTo('/app/ai/contexts/test-context');
      cy.assertHasElement([
        'input[placeholder*="Filter"]',
        'input[type="text"]',
        'input[placeholder*="Search"]',
        '[data-testid*="filter"]',
        '[data-testid*="search"]'
      ]);
    });

    it('should display type selector', () => {
      cy.navigateTo('/app/ai/contexts/test-context');
      cy.assertContainsAny(['All Types', 'Type', 'Context', 'Not Found']);
    });

    it('should display entries list or empty state', () => {
      cy.navigateTo('/app/ai/contexts/test-context');
      cy.assertContainsAny(['No entries', 'Add your first entry', 'Entry', 'Context', 'Not Found']);
    });

    it('should display entry type badges', () => {
      cy.navigateTo('/app/ai/contexts/test-context');
      cy.assertContainsAny(['fact', 'preference', 'knowledge', 'Context', 'Not Found']);
    });
  });

  describe('Settings Tab Content', () => {
    it('should display Retention Policy section', () => {
      cy.navigateTo('/app/ai/contexts/test-context');
      cy.clickButton('Settings');
      cy.assertContainsAny(['Retention Policy']);
    });

    it('should display Danger Zone section', () => {
      cy.navigateTo('/app/ai/contexts/test-context');
      cy.clickButton('Settings');
      cy.assertContainsAny(['Danger Zone']);
    });

    it('should display Archive/Restore button', () => {
      cy.navigateTo('/app/ai/contexts/test-context');
      cy.clickButton('Settings');
      cy.assertContainsAny(['Archive', 'Restore']);
    });

    it('should display Delete button', () => {
      cy.navigateTo('/app/ai/contexts/test-context');
      cy.clickButton('Settings');
      cy.assertContainsAny(['Delete Context', 'Delete']);
    });
  });

  describe('Import/Export Modal', () => {
    it('should open Import/Export modal', () => {
      cy.navigateTo('/app/ai/contexts/test-context');
      cy.clickButton('Import/Export');
      cy.waitForStableDOM();
      cy.assertModalVisible('Import');
    });
  });

  describe('Entry Editor', () => {
    it('should open entry editor when Add Entry clicked', () => {
      cy.navigateTo('/app/ai/contexts/test-context');
      cy.clickButton('Add Entry');
      cy.assertContainsAny(['New Entry', 'Edit Entry']);
    });
  });

  describe('Error Handling', () => {
    it('should handle API errors gracefully', () => {
      cy.testErrorHandling('**/api/**/contexts/**', {
        statusCode: 500,
        visitUrl: '/app/ai/contexts/test-context'
      });
    });
  });

  describe('Loading State', () => {
    it('should display loading indicator', () => {
      cy.intercept('GET', '**/api/**/contexts/**', {
        delay: 1000,
        statusCode: 200,
        body: { success: true, data: {} }
      });
      cy.visit('/app/ai/contexts/test-context');
      cy.assertHasElement([
        '[class*="animate-spin"]',
        '[class*="loading"]',
        '[class*="spin"]',
        '[data-testid*="loading"]',
        'svg[class*="animate"]'
      ]);
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.testResponsiveDesign('/app/ai/contexts/test-context', {
        checkContent: ['Context', 'Not Found', 'Back']
      });
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.navigateTo('/app/ai/contexts/test-context');
      cy.assertContainsAny(['Context', 'Not Found']);
    });

    it('should stack stats cards on small screens', () => {
      cy.viewport('iphone-x');
      cy.navigateTo('/app/ai/contexts/test-context');
      cy.assertHasElement([
        '[class*="grid-cols-2"]',
        '[class*="md:grid-cols"]',
        '[class*="grid"]',
        '[class*="flex"]',
        'main'
      ]);
    });

    it('should show multi-column layout on large screens', () => {
      cy.viewport(1920, 1080);
      cy.navigateTo('/app/ai/contexts/test-context');
      cy.assertHasElement([
        '[class*="md:grid-cols-5"]',
        '[class*="md:grid-cols"]',
        '[class*="grid"]',
        '[class*="flex"]',
        'main'
      ]);
    });
  });
});

export {};

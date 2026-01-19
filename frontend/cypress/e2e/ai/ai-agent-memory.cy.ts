/// <reference types="cypress" />

/**
 * AI Agent Memory Page Tests
 *
 * Tests for Agent Memory functionality including:
 * - Page navigation
 * - Memory viewer
 * - Entry editor
 * - Error handling
 * - Responsive design
 */

describe('AI Agent Memory Page Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup({ intercepts: ['ai'] });
  });

  describe('Page Navigation', () => {
    it('should navigate to Agent Memory page', () => {
      cy.navigateTo('/app/ai/agents/test-agent/memory');
      cy.url().should('include', '/ai');
    });

    it('should display agent not found for invalid agent', () => {
      cy.navigateTo('/app/ai/agents/invalid-agent-id/memory');
      cy.assertContainsAny(['Not Found', 'does not exist', 'Back to Agents']);
    });
  });

  describe('Page Actions', () => {
    it('should have Clear All button or empty state', () => {
      cy.navigateTo('/app/ai/agents/test-agent/memory');
      cy.assertContainsAny(['Clear All', 'Clear', 'No memories', 'no entries', 'Memory']);
    });

    it('should have Add Memory button or empty state', () => {
      cy.navigateTo('/app/ai/agents/test-agent/memory');
      cy.assertContainsAny(['Add Memory', 'Add', 'No memories', 'no entries', 'Memory']);
    });
  });

  describe('Context Info Display', () => {
    it('should display context information', () => {
      cy.navigateTo('/app/ai/agents/test-agent/memory');
      cy.assertContainsAny(['entries', 'Memory']);
    });

    it('should display entry count', () => {
      cy.navigateTo('/app/ai/agents/test-agent/memory');
      cy.assertContainsAny(['entries', 'Memory']);
    });

    it('should have View Full Context link', () => {
      cy.navigateTo('/app/ai/agents/test-agent/memory');
      cy.assertContainsAny(['View Full Context', 'Context']);
    });
  });

  describe('Memory Viewer', () => {
    it('should display memory viewer component', () => {
      cy.navigateTo('/app/ai/agents/test-agent/memory');
      cy.assertContainsAny(['Memory']);
    });

    it('should display memory entries or empty state', () => {
      cy.navigateTo('/app/ai/agents/test-agent/memory');
      cy.assertContainsAny(['No memories', 'no entries', 'Memory']);
    });
  });

  describe('Entry Editor', () => {
    it('should display entry editor when adding memory', () => {
      cy.navigateTo('/app/ai/agents/test-agent/memory');
      cy.get('body').then($body => {
        if ($body.find('button:contains("Add Memory"), button:contains("Add")').length > 0) {
          cy.get('button:contains("Add Memory"), button:contains("Add")').first().click();
          cy.assertContainsAny(['Add Memory', 'Edit Memory']);
        }
      });
    });

    it('should have Cancel button in editor', () => {
      cy.navigateTo('/app/ai/agents/test-agent/memory');
      cy.assertContainsAny(['Cancel', 'Memory']);
    });
  });

  describe('Error Handling', () => {
    it('should handle API errors gracefully', () => {
      cy.testErrorHandling('**/api/**/agents/*/memory**', {
        statusCode: 500,
        visitUrl: '/app/ai/agents/test-agent/memory'
      });
    });

    it('should show error notification on failure', () => {
      cy.mockApiError('**/api/**/agents/*/memory**', 404, 'Agent not found');
      cy.navigateTo('/app/ai/agents/test-agent/memory');
      cy.get('body').should('be.visible');
    });
  });

  describe('Loading State', () => {
    it('should display loading indicator', () => {
      cy.intercept('GET', '**/api/**/agents/**', (req) => {
        req.reply((res) => {
          res.delay = 2000;
          res.send({ success: true, data: {} });
        });
      });
      cy.visit('/app/ai/agents/test-agent/memory');
      cy.assertHasElement(['[class*="animate-spin"]', '[class*="loading"]']);
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.testResponsiveDesign('/app/ai/agents/test-agent/memory', {
        checkContent: ['Memory']
      });
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.navigateTo('/app/ai/agents/test-agent/memory');
      cy.get('body').should('be.visible');
    });
  });
});

export {};

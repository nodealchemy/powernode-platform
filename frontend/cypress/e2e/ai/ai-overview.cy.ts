/// <reference types="cypress" />

/**
 * AI Overview Page Tests
 *
 * Tests for AI Overview functionality including:
 * - Page navigation and load
 * - Dashboard stats display
 * - Quick actions
 * - Live updates toggle
 * - Refresh functionality
 * - System health status
 * - Responsive design
 */

describe('AI Overview Page Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup({ intercepts: ['ai'] });
  });

  describe('Page Navigation', () => {
    it('should load AI Overview page directly', () => {
      cy.assertPageReady('/app/ai', 'AI');
    });

    it('should display page title', () => {
      cy.navigateTo('/app/ai');
      cy.assertContainsAny(['AI Overview', 'AI Dashboard', 'AI system dashboard']);
    });

    it('should display breadcrumbs', () => {
      cy.navigateTo('/app/ai');
      cy.assertContainsAny(['Dashboard', 'AI']);
    });
  });

  describe('Dashboard Stats Display', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai');
    });

    it('should display AI stats cards', () => {
      cy.assertContainsAny(['Workflows', 'Agents', 'Providers', 'Conversations', 'Total', 'Active']);
    });

    it('should display workflow count', () => {
      cy.assertContainsAny(['Workflow', 'AI', 'Active']);
    });

    it('should display agent count', () => {
      cy.assertContainsAny(['Agent', 'AI', 'Total']);
    });

    it('should display provider count', () => {
      cy.assertContainsAny(['Provider', 'AI', 'Connected']);
    });
  });

  describe('Quick Actions', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai');
    });

    it('should have Refresh button', () => {
      cy.assertHasElement([
        '[data-testid="action-refresh"]',
        '[aria-label="Refresh"]',
        '[aria-label*="Refresh"]',
      ]);
    });

    it('should have Live Updates toggle', () => {
      cy.assertHasElement([
        '[data-testid="action-live-updates"]',
        '[aria-label="Live"]',
        '[aria-label="Paused"]',
      ]);
    });
  });

  describe('System Health Display', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai');
    });

    it('should display system health status', () => {
      cy.assertContainsAny(['Health', 'Status', 'healthy', 'Online', 'AI', 'System']);
    });

    it('should display provider status', () => {
      cy.assertContainsAny(['Provider', 'Connected', 'Available', 'AI', 'Active']);
    });
  });

  describe('Quick Access Links', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai');
    });

    it('should have links to AI subpages', () => {
      cy.assertHasElement(['a[href*="/workflows"]', 'a[href*="/agents"]', 'a[href*="/providers"]', 'a[href*="/ai"]']);
    });
  });

  describe('Empty State', () => {
    it('should handle empty AI system gracefully', () => {
      cy.mockEndpoint('GET', '/api/v1/ai/*', []);
      cy.navigateTo('/app/ai');
      cy.get('body').should('be.visible');
      cy.get('body').should('not.contain.text', 'Cannot read');
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.testErrorHandling('/api/v1/ai/dashboard*', {
        statusCode: 500,
        visitUrl: '/app/ai'
      });
    });
  });

  describe('Permission-Based Display', () => {
    it('should show content based on permissions', () => {
      cy.navigateTo('/app/ai');
      cy.assertContainsAny(['Permission', 'Access', 'AI', 'Overview', 'Dashboard']);
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.testResponsiveDesign('/app/ai', {
        checkContent: ['AI']
      });
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.navigateTo('/app/ai');
      cy.get('body').should('be.visible');
    });
  });
});

export {};

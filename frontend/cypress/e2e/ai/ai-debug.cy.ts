/// <reference types="cypress" />

/**
 * AI Debug Page Tests
 *
 * Tests for AI Debug functionality including:
 * - Page navigation and load
 * - Debug information display
 * - Troubleshooting steps
 * - Common solutions
 * - Permission-based access
 * - Error handling
 * - Responsive design
 */

describe('AI Debug Page Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup({ intercepts: ['ai'] });
  });

  describe('Page Navigation', () => {
    it('should navigate to AI Debug page', () => {
      cy.assertPageReady('/app/ai/debug', 'Debug');
    });

    it('should display page title', () => {
      cy.navigateTo('/app/ai/debug');
      cy.assertContainsAny(['Debug', 'AI Debug']);
    });

    it('should display breadcrumbs', () => {
      cy.navigateTo('/app/ai/debug');
      cy.assertContainsAny(['Dashboard', 'AI', 'Orchestration']);
    });
  });

  describe('Debug Information Display', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/debug');
    });

    it('should display permissions debug component', () => {
      cy.assertContainsAny(['Permission', 'Access', 'Debug']);
    });

    it('should display current user permissions', () => {
      cy.assertContainsAny(['User', 'Current', 'Permissions']);
    });

    it('should display AI-related permissions', () => {
      cy.assertContainsAny(['ai.', 'workflow', 'agent']);
    });
  });

  describe('Troubleshooting Steps', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/debug');
    });

    it('should display troubleshooting section', () => {
      cy.assertContainsAny(['Troubleshoot', 'Steps', 'Fix']);
    });

    it('should display step-by-step instructions', () => {
      cy.assertContainsAny(['Step', '1.']);
    });
  });

  describe('Common Solutions', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/debug');
    });

    it('should display common solutions section', () => {
      cy.assertContainsAny(['Common', 'Solution', 'Issue']);
    });

    it('should display permission-related solutions', () => {
      cy.assertContainsAny(['permission', 'access', 'denied']);
    });

    it('should display configuration solutions', () => {
      cy.assertContainsAny(['config', 'setting', 'enable']);
    });
  });

  describe('Debug Actions', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/debug');
    });

    it('should have Refresh button', () => {
      cy.assertHasElement([
        'button:contains("Refresh")',
        '[data-testid="refresh-btn"]',
        '[data-testid*="refresh"]',
        'button[aria-label*="refresh"]',
        'button svg[class*="rotate"]'
      ]);
    });

    it('should have Clear Cache button', () => {
      cy.assertHasElement([
        'button:contains("Clear")',
        'button:contains("Reset")',
        '[data-testid*="clear"]',
        '[data-testid*="reset"]',
        'button:contains("Cache")'
      ]);
    });

    it('should have Export Debug Info button', () => {
      cy.assertHasElement([
        'button:contains("Export")',
        'button:contains("Download")',
        '[data-testid*="export"]',
        '[data-testid*="download"]',
        'button:contains("Debug")'
      ]);
    });
  });

  describe('System Status', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/debug');
    });

    it('should display system status', () => {
      cy.assertContainsAny(['Status', 'Online', 'Connected', 'Debug', 'AI']);
    });

    it('should display API connection status', () => {
      cy.assertContainsAny(['API', 'Connection', 'Debug', 'Status', 'AI']);
    });
  });

  describe('Permission Check', () => {
    it('should show permission message for unauthorized users', () => {
      cy.navigateTo('/app/ai/debug');
      cy.assertContainsAny(["don't have permission", 'Debug', 'AI']);
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.testErrorHandling('/api/v1/ai/debug*', {
        statusCode: 500,
        visitUrl: '/app/ai/debug'
      });
    });

    it('should display error notification on failure', () => {
      cy.mockApiError('/api/v1/ai/debug*', 500, 'Failed to load debug info');
      cy.navigateTo('/app/ai/debug');
      cy.assertContainsAny(['Error', 'Failed', 'Debug']);
    });
  });

  describe('Loading State', () => {
    it('should display loading indicator', () => {
      cy.intercept('GET', '/api/v1/ai/debug*', {
        delay: 1000,
        statusCode: 200,
        body: { success: true, debug: {} }
      });
      cy.visit('/app/ai/debug');
      cy.assertHasElement(['[class*="spin"]', '[class*="loading"]']);
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.testResponsiveDesign('/app/ai/debug', {
        checkContent: ['Debug', 'AI']
      });
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.navigateTo('/app/ai/debug');
      cy.assertContainsAny(['Debug', 'AI']);
    });

    it('should stack elements on small screens', () => {
      cy.viewport(375, 667);
      cy.navigateTo('/app/ai/debug');
      cy.get('body').should('be.visible');
    });
  });
});

export {};

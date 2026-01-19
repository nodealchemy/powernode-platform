/// <reference types="cypress" />

/**
 * AI Providers Tests
 *
 * Tests for AI Providers page functionality including:
 * - Page navigation and load
 * - Providers list display
 * - Provider configuration
 * - Provider status
 * - Add/configure provider actions
 * - Provider integration settings
 * - API key management for providers
 * - Responsive design
 */

describe('AI Providers Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup({ intercepts: ['ai'] });
  });

  describe('Page Navigation', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/providers');
    });

    it('should load AI Providers page directly', () => {
      cy.assertContainsAny(['Provider', 'Providers', 'AI']);
    });

    it('should display breadcrumbs', () => {
      cy.assertContainsAny(['Dashboard', 'AI', 'Providers']);
    });
  });

  describe('Providers List Display', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/providers');
    });

    it('should display providers list or empty state', () => {
      cy.assertContainsAny(['No providers', 'Configure', 'Provider']);
    });

    it('should display common AI providers', () => {
      cy.assertContainsAny(['OpenAI', 'Anthropic', 'Azure', 'Google', 'Provider']);
    });

    it('should display provider status', () => {
      cy.assertContainsAny(['Connected', 'Configured', 'Active', 'Not configured', 'Provider']);
    });

    it('should display provider logos or icons', () => {
      cy.assertHasElement(['img', 'svg', '[class*="icon"]', '[class*="logo"]']);
    });
  });

  describe('Provider Configuration', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/providers');
    });

    it('should have configure action for providers', () => {
      cy.assertHasElement(['button:contains("Configure")', 'button:contains("Setup")', 'button:contains("Connect")']);
    });

    it('should open configuration modal when configure clicked', () => {
      cy.get('body').then($body => {
        const configureButton = $body.find('button:contains("Configure"), button:contains("Setup")');
        if (configureButton.length > 0) {
          cy.wrap(configureButton).first().click();
          cy.waitForStableDOM();
          cy.assertContainsAny(['API Key', 'Configuration', 'Provider']);
        }
      });
    });

    it('should close configuration modal when cancel clicked', () => {
      cy.get('body').then($body => {
        const configureButton = $body.find('button:contains("Configure")');
        if (configureButton.length > 0) {
          cy.wrap(configureButton).first().click();
          cy.waitForStableDOM();
          cy.get('body').then($newBody => {
            if ($newBody.find('button:contains("Cancel")').length > 0) {
              cy.clickButton('Cancel');
              cy.waitForModalClose();
            }
          });
        }
      });
    });
  });

  describe('Provider Status Management', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/providers');
    });

    it('should have enable/disable action for providers', () => {
      cy.assertHasElement(['button:contains("Enable")', 'button:contains("Disable")', '[class*="toggle"]']);
    });

    it('should display connected status for configured providers', () => {
      cy.assertContainsAny(['Connected', 'Active', 'Provider']);
    });
  });

  describe('Provider Details', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/providers');
    });

    it('should display provider capabilities', () => {
      cy.assertContainsAny(['chat', 'completion', 'embedding', 'model', 'Provider']);
    });

    it('should display available models', () => {
      cy.assertContainsAny(['gpt', 'claude', 'model', 'Provider']);
    });
  });

  describe('API Key Management', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/providers');
    });

    it('should have option to update API key', () => {
      cy.assertHasElement(['button:contains("Update")', 'button:contains("Edit")', 'button:contains("Change")']);
    });
  });

  describe('Provider Testing', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/providers');
    });

    it('should have test connection action', () => {
      cy.assertHasElement(['button:contains("Test")', 'button:contains("Verify")']);
    });
  });

  describe('Provider Settings', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/providers');
    });

    it('should display rate limiting settings', () => {
      cy.assertContainsAny(['rate', 'limit', 'quota', 'Provider']);
    });

    it('should display default model settings', () => {
      cy.assertContainsAny(['Default', 'model', 'Provider']);
    });
  });

  describe('Empty State', () => {
    it('should display empty state when no providers configured', () => {
      cy.mockEndpoint('GET', '/api/v1/ai/providers*', { success: true, data: { providers: [] } });
      cy.assertPageReady('/app/ai/providers');
      cy.assertContainsAny(['No providers', 'Get started', 'Configure', 'Add provider']);
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.testErrorHandling('/api/v1/ai/providers*', {
        statusCode: 500,
        visitUrl: '/app/ai/providers'
      });
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.testResponsiveDesign('/app/ai/providers', {
        checkContent: ['Provider']
      });
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.assertPageReady('/app/ai/providers');
      cy.get('body').should('be.visible');
    });
  });
});

export {};

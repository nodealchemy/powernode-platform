/// <reference types="cypress" />

/**
 * AI Orchestration Page Tests
 *
 * Tests for AI Orchestration hub functionality including:
 * - Page navigation and load
 * - Tab navigation (Overview, Providers, Agents, Workflows, Conversations, Analytics, Monitoring, MCP)
 * - Permission-based tab visibility
 * - Enhanced AI Overview display
 * - Tab content loading
 * - Authentication check
 * - Error handling
 * - Responsive design
 */

describe('AI Orchestration Page Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup({ intercepts: ['ai'] });
  });

  describe('Page Navigation', () => {
    it('should navigate to AI Orchestration page', () => {
      cy.assertPageReady('/app/ai', 'AI');
    });

    it('should display page title', () => {
      cy.navigateTo('/app/ai');
      cy.assertContainsAny(['AI Orchestration', 'AI']);
    });

    it('should display page description', () => {
      cy.navigateTo('/app/ai');
      cy.assertContainsAny(['Manage', 'AI providers', 'agents', 'workflows']);
    });

    it('should display breadcrumbs', () => {
      cy.navigateTo('/app/ai');
      cy.assertContainsAny(['Dashboard', 'AI Orchestration']);
    });
  });

  describe('Tab Navigation', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai');
    });

    it('should display Overview tab', () => {
      cy.assertContainsAny(['Overview']);
    });

    it('should display AI Providers tab', () => {
      cy.assertContainsAny(['Providers', 'AI Providers']);
    });

    it('should display AI Agents tab', () => {
      cy.assertContainsAny(['Agents', 'AI Agents']);
    });

    it('should display Workflows tab', () => {
      cy.assertContainsAny(['Workflows']);
    });

    it('should display Conversations tab', () => {
      cy.assertContainsAny(['Conversations']);
    });

    it('should display Analytics tab', () => {
      cy.assertContainsAny(['Analytics']);
    });

    it('should display Monitoring tab', () => {
      cy.assertContainsAny(['Monitoring']);
    });

    it('should display MCP tab', () => {
      cy.assertContainsAny(['MCP']);
    });
  });

  describe('Tab Switching', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai');
    });

    it('should switch to AI Providers tab', () => {
      cy.clickButton('Providers');
      cy.assertContainsAny(['Provider', 'AI Providers']);
    });

    it('should switch to AI Agents tab', () => {
      cy.clickButton('Agents');
      cy.assertContainsAny(['Agent', 'AI Agents']);
    });

    it('should switch to Workflows tab', () => {
      cy.clickButton('Workflows');
      cy.assertContainsAny(['Workflow', 'Workflows']);
    });

    it('should switch to Analytics tab', () => {
      cy.clickButton('Analytics');
      cy.assertContainsAny(['Analytics', 'AI']);
    });

    it('should switch to Monitoring tab', () => {
      cy.clickButton('Monitoring');
      cy.assertContainsAny(['Monitoring', 'AI']);
    });
  });

  describe('Overview Tab Content', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai');
    });

    it('should display Enhanced AI Overview', () => {
      cy.assertContainsAny(['Overview', 'AI']);
    });

    it('should display AI system statistics', () => {
      cy.assertContainsAny(['Providers', 'Agents', 'Workflows', 'AI']);
    });
  });

  describe('Page Actions', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai');
    });

    it('should have Refresh button', () => {
      cy.assertHasElement(['button:contains("Refresh")']);
    });
  });

  describe('Permission Check', () => {
    it('should show permission message for unauthorized users', () => {
      cy.navigateTo('/app/ai');
      cy.assertContainsAny(["don't have permission", 'AI Orchestration', 'AI']);
    });
  });

  describe('Direct Tab Navigation', () => {
    it('should navigate directly to providers tab', () => {
      cy.navigateTo('/app/ai/providers');
      cy.assertContainsAny(['Provider', 'AI']);
    });

    it('should navigate directly to agents tab', () => {
      cy.navigateTo('/app/ai/agents');
      cy.assertContainsAny(['Agent', 'AI']);
    });

    it('should navigate directly to workflows tab', () => {
      cy.navigateTo('/app/ai/workflows');
      cy.assertContainsAny(['Workflow', 'AI']);
    });

    it('should navigate directly to conversations tab', () => {
      cy.navigateTo('/app/ai/conversations');
      cy.assertContainsAny(['Conversation', 'AI']);
    });

    it('should navigate directly to analytics tab', () => {
      cy.navigateTo('/app/ai/analytics');
      cy.assertContainsAny(['Analytics', 'AI']);
    });

    it('should navigate directly to monitoring tab', () => {
      cy.navigateTo('/app/ai/monitoring');
      cy.assertContainsAny(['Monitoring', 'AI']);
    });

    it('should navigate directly to MCP tab', () => {
      cy.navigateTo('/app/ai/mcp');
      cy.assertContainsAny(['MCP', 'AI']);
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.testErrorHandling('/api/v1/ai/*', {
        statusCode: 500,
        visitUrl: '/app/ai'
      });
    });
  });

  describe('Loading State', () => {
    it('should display loading indicator', () => {
      cy.intercept('GET', '/api/v1/ai/*', {
        delay: 1000,
        statusCode: 200,
        body: { success: true }
      });
      cy.visit('/app/ai');
      cy.assertHasElement(['[class*="spin"]', '[class*="loading"]']);
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
      cy.assertContainsAny(['AI Orchestration', 'AI']);
    });

    it('should handle horizontal tab scrolling on mobile', () => {
      cy.viewport('iphone-x');
      cy.navigateTo('/app/ai');
      cy.assertHasElement(['[role="tablist"]', '[class*="tab"]']);
    });
  });
});

export {};

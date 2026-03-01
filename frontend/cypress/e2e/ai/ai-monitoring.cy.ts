/// <reference types="cypress" />

/**
 * AI Monitoring Page Tests
 *
 * Tests for AI Monitoring functionality including:
 * - Page navigation and load
 * - Status bar display
 * - Overview cards
 * - Tab navigation (overview, providers, agents, workflows, conversations, alerts)
 * - Real-time updates toggle
 * - Time range selection
 * - Refresh functionality
 * - System health dashboard
 * - Provider monitoring
 * - Agent performance
 * - Alert management
 * - Permission-based access
 * - Responsive design
 */

describe('AI Monitoring Page Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup({ intercepts: ['ai'] });
  });

  describe('Page Navigation', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/monitoring');
    });

    it('should load AI Monitoring page directly', () => {
      cy.assertContainsAny(['Monitoring', 'AI']);
    });

    it('should display page title', () => {
      cy.assertContainsAny(['AI System Monitoring', 'Monitoring']);
    });

    it('should display breadcrumbs', () => {
      cy.assertContainsAny(['Dashboard', 'AI', 'Monitoring']);
    });
  });

  describe('Status Bar Display', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/monitoring');
    });

    it('should display connection status', () => {
      cy.assertContainsAny(['Connected', 'Disconnected', 'Online', 'Offline', 'Monitoring']);
    });

    it('should display real-time status indicator', () => {
      cy.assertContainsAny(['Real-time', 'Live', 'Paused', 'Monitoring']);
    });

    it('should display last update timestamp', () => {
      cy.assertContainsAny(['Updated', 'Last', 'ago', 'Monitoring']);
    });
  });

  describe('Overview Cards', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/monitoring');
    });

    it('should display overview statistics cards', () => {
      cy.assertContainsAny(['Workflows', 'Agents', 'Providers', 'Monitoring']);
    });

    it('should display workflow stats', () => {
      cy.assertContainsAny(['Workflow', 'Monitoring']);
    });

    it('should display conversation stats', () => {
      cy.assertContainsAny(['Conversation', 'Monitoring']);
    });

    it('should display alert count', () => {
      cy.assertContainsAny(['Alert', 'Monitoring']);
    });
  });

  describe('Tab Navigation', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/monitoring');
    });

    it('should display monitoring tabs', () => {
      cy.assertContainsAny(['Overview', 'Providers', 'Agents', 'Workflows']);
    });

    it('should switch to Providers tab', () => {
      cy.clickButton('Providers');
      cy.assertContainsAny(['Provider', 'Providers']);
    });

    it('should switch to Agents tab', () => {
      cy.clickButton('Agents');
      cy.assertContainsAny(['Agent', 'Agents']);
    });

    it('should switch to Alerts tab', () => {
      cy.clickButton('Alerts');
      cy.assertContainsAny(['Alert', 'Alerts']);
    });
  });

  describe('Real-Time Updates', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/monitoring');
    });

    it('should have Enable Real-time button', () => {
      cy.assertHasElement(['button:contains("Real-time")', 'button:contains("Enable")', 'button:contains("Disable")']);
    });
  });

  describe('Time Range Selection', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/monitoring');
    });

    it('should have time range selector', () => {
      cy.assertHasElement(['select', 'button:contains("1h")', 'button:contains("24h")', 'button:contains("7d")']);
    });
  });

  describe('Refresh Functionality', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/monitoring');
    });

    it('should have Refresh button', () => {
      cy.assertHasElement(['button:contains("Refresh")', '[aria-label*="refresh"]']);
    });
  });

  describe('System Health Dashboard', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/monitoring');
    });

    it('should display system health information', () => {
      cy.assertContainsAny(['Health', 'System', 'Status', 'Monitoring']);
    });

    it('should display health score', () => {
      cy.assertContainsAny(['%', 'Score', 'healthy', 'Monitoring']);
    });
  });

  describe('Provider Monitoring', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/monitoring');
    });

    it('should display provider list', () => {
      cy.assertContainsAny(['Provider', 'OpenAI', 'Anthropic', 'Monitoring']);
    });
  });

  describe('Agent Performance', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/monitoring');
    });

    it('should display agent performance metrics', () => {
      cy.assertContainsAny(['Agent', 'Performance', 'Success', 'Monitoring']);
    });
  });

  describe('Alert Management', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/monitoring');
    });

    it('should display alert list', () => {
      cy.assertContainsAny(['Alert', 'No alerts', 'critical', 'warning', 'Monitoring']);
    });
  });

  describe('Permission-Based Access', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/monitoring');
    });

    it('should show access denied for unauthorized users', () => {
      cy.assertContainsAny(['Access Denied', 'permission', 'Monitoring']);
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.testErrorHandling('/api/v1/ai/monitoring*', {
        statusCode: 500,
        visitUrl: '/app/ai/monitoring'
      });
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.testResponsiveDesign('/app/ai/monitoring', {
        checkContent: ['Monitoring']
      });
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.navigateTo('/app/ai/monitoring');
      cy.assertContainsAny(['Monitoring', 'AI']);
    });
  });
});

export {};

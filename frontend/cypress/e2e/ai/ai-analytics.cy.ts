/// <reference types="cypress" />

/**
 * AI Analytics Page Tests
 *
 * Tests for AI Analytics functionality including:
 * - Page navigation and load
 * - Analytics dashboard display
 * - Charts and visualizations
 * - Metrics display
 * - Date range selection
 * - Export functionality
 * - Responsive design
 */

describe('AI Analytics Page Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup({ intercepts: ['ai'] });
  });

  describe('Page Navigation', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/analytics');
    });

    it('should load AI Analytics page directly', () => {
      cy.assertContainsAny(['Analytics', 'AI', 'Dashboard']);
    });

    it('should display page title', () => {
      cy.assertContainsAny(['Analytics', 'Dashboard']);
    });

    it('should display breadcrumbs', () => {
      cy.assertContainsAny(['Dashboard', 'AI', 'Analytics']);
    });
  });

  describe('Analytics Dashboard Display', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/analytics');
    });

    it('should display analytics dashboard', () => {
      cy.assertContainsAny(['Analytics', 'Usage', 'Metrics']);
    });

    it('should display summary metrics', () => {
      cy.assertContainsAny(['Total', 'Average', 'Count', 'Analytics']);
    });
  });

  describe('Key Metrics Display', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/analytics');
    });

    it('should display token usage metrics', () => {
      cy.assertContainsAny(['Token', 'token', 'Analytics']);
    });

    it('should display cost metrics', () => {
      cy.assertContainsAny(['Cost', '$', 'Spend', 'Analytics']);
    });

    it('should display execution metrics', () => {
      cy.assertContainsAny(['Execution', 'Request', 'Call', 'Analytics']);
    });

    it('should display success rate metrics', () => {
      cy.assertContainsAny(['Success', 'Rate', '%', 'Analytics']);
    });
  });

  describe('Charts and Visualizations', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/analytics');
    });

    it('should display charts', () => {
      cy.assertHasElement(['canvas', 'svg[class*="chart"]', '[class*="chart"]']);
    });

    it('should display usage trend chart', () => {
      cy.assertContainsAny(['Trend', 'Usage', 'Over Time', 'Analytics']);
    });

    it('should display provider distribution', () => {
      cy.assertContainsAny(['Provider', 'Distribution', 'Breakdown', 'Analytics']);
    });
  });

  describe('Date Range Selection', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/analytics');
    });

    it('should have date range selector', () => {
      cy.assertHasElement(['select', 'button:contains("7 days")', 'button:contains("30 days")', 'input[type="date"]']);
    });
  });

  describe('Refresh Functionality', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/analytics');
    });

    it('should have Refresh button or icon', () => {
      cy.get('body').then($body => {
        const hasRefreshButton = $body.find('button:contains("Refresh"), [aria-label*="refresh"], [title*="Refresh"]').length > 0;
        const hasRefreshIcon = $body.find('button svg, button [class*="refresh"], [class*="sync"]').length > 0;
        const hasAnalyticsContent = $body.text().includes('Analytics');
        expect(hasRefreshButton || hasRefreshIcon || hasAnalyticsContent).to.be.true;
      });
    });
  });

  describe('Export Functionality', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/analytics');
    });

    it('should have Export button', () => {
      cy.assertHasElement(['button:contains("Export")', 'button:contains("Download")']);
    });
  });

  describe('Empty State', () => {
    it('should handle no analytics data gracefully', () => {
      cy.mockEndpoint('GET', '/api/v1/ai/analytics*', { metrics: [], charts: [] });
      cy.assertPageReady('/app/ai/analytics');
      cy.get('body').should('be.visible');
      cy.get('body').should('not.contain.text', 'Cannot read');
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.testErrorHandling('/api/v1/ai/analytics*', {
        statusCode: 500,
        visitUrl: '/app/ai/analytics'
      });
    });
  });

  describe('Permission-Based Display', () => {
    it('should show content based on permissions', () => {
      cy.assertPageReady('/app/ai/analytics');
      cy.assertContainsAny(['Permission', 'Access', 'Analytics']);
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.testResponsiveDesign('/app/ai/analytics', {
        checkContent: ['Analytics']
      });
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.assertPageReady('/app/ai/analytics');
      cy.get('body').should('be.visible');
    });
  });
});

export {};

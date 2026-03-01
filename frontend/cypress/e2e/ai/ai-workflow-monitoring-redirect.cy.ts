/// <reference types="cypress" />

/**
 * AI Workflow Monitoring Redirect Tests
 *
 * Tests for the WorkflowMonitoringPage redirect behavior.
 * This page redirects to the consolidated AI Monitoring page.
 */

describe('AI Workflow Monitoring Redirect Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup({ intercepts: ['ai'] });
  });

  describe('Page Redirect', () => {
    it('should redirect from workflow-monitoring to ai/monitoring/workflows', () => {
      cy.visit('/app/ai/workflow-monitoring');

      // Should redirect to the monitoring page with workflows path
      cy.url().should('include', '/app/ai/monitoring');
    });

    it('should load the monitoring page after redirect', () => {
      cy.visit('/app/ai/workflow-monitoring');

      // Wait for redirect and page load
      cy.waitForPageLoad();

      // Should display monitoring content
      cy.assertContainsAny(['Monitoring', 'Workflows', 'AI', 'Dashboard']);
    });

    it('should handle direct navigation to monitoring page', () => {
      cy.navigateTo('/app/ai/monitoring');

      // Should display monitoring content
      cy.assertContainsAny(['Monitoring', 'AI Monitoring', 'Dashboard']);
    });

    it('should handle navigation to workflows tab', () => {
      cy.navigateTo('/app/ai/monitoring/workflows');

      // Should display workflow monitoring content
      cy.assertContainsAny(['Workflows', 'Monitoring', 'Status', 'Executions']);
    });
  });

  describe('Monitoring Page Content', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/monitoring');
    });

    it('should display monitoring overview', () => {
      cy.assertContainsAny(['Overview', 'Status', 'Monitoring', 'Health']);
    });

    it('should have navigation to workflow details', () => {
      cy.get('body').then($body => {
        const hasWorkflowNav = $body.find('a[href*="workflow"], button:contains("Workflow")').length > 0 ||
                              $body.text().includes('Workflow');
        expect(hasWorkflowNav).to.be.true;
      });
    });
  });

  describe('Error Handling', () => {
    it('should handle redirect gracefully on network error', () => {
      cy.intercept('GET', '**/api/**/ai/monitoring**', {
        statusCode: 500,
        body: { error: 'Server error' },
      }).as('failedMonitoring');

      cy.visit('/app/ai/workflow-monitoring');

      // Should still redirect and show error state
      cy.url().should('include', '/app/ai/monitoring');
    });
  });

  describe('Responsive Design', () => {
    it('should redirect correctly on mobile viewport', () => {
      cy.viewport(375, 667);
      cy.visit('/app/ai/workflow-monitoring');

      cy.url().should('include', '/app/ai/monitoring');
      cy.get('body').should('be.visible');
    });

    it('should redirect correctly on tablet viewport', () => {
      cy.viewport(768, 1024);
      cy.visit('/app/ai/workflow-monitoring');

      cy.url().should('include', '/app/ai/monitoring');
      cy.get('body').should('be.visible');
    });
  });
});

export {};

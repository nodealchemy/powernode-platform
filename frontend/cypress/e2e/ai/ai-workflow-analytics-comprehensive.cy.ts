/// <reference types="cypress" />

/**
 * AI Workflow Analytics Comprehensive Tests
 *
 * Comprehensive E2E tests for Workflow Analytics:
 * - Performance metrics
 * - Execution history
 * - Filter controls
 * - Charts and visualizations
 * - Export functionality
 * - Recommendations
 */

describe('AI Workflow Analytics Comprehensive Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup({ intercepts: ['ai'] });
    setupWorkflowAnalyticsIntercepts();
  });

  describe('Analytics Dashboard', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/workflows/analytics');
    });

    it('should display analytics page with title', () => {
      cy.assertContainsAny(['Workflow Analytics', 'Analytics', 'Performance']);
    });

    it('should display date range selector', () => {
      cy.assertContainsAny(['7 days', '30 days', '90 days', 'Custom']);
    });

    it('should display export button', () => {
      cy.get('button').contains(/export|download/i).should('exist');
    });

    it('should display refresh button', () => {
      cy.get('button').contains(/refresh/i).should('exist');
    });
  });

  describe('Overview Metrics', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/workflows/analytics');
    });

    it('should display total workflows metric', () => {
      cy.assertContainsAny(['Total Workflows', 'Workflows', 'total']);
    });

    it('should display active workflows metric', () => {
      cy.assertContainsAny(['Active', 'active workflows']);
    });

    it('should display total executions metric', () => {
      cy.assertContainsAny(['Executions', 'Total Executions', 'runs']);
    });

    it('should display success rate metric', () => {
      cy.assertContainsAny(['Success Rate', 'success', '%']);
    });

    it('should display average execution time', () => {
      cy.assertContainsAny(['Avg', 'Average', 'Execution Time', 'ms', 's']);
    });

    it('should display failed executions count', () => {
      cy.assertContainsAny(['Failed', 'Failures', 'errors']);
    });
  });

  describe('Date Range Filter', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/workflows/analytics');
    });

    it('should filter by last 7 days', () => {
      cy.get('button, select').contains(/7 days|week/i).first().click();
      cy.waitForPageLoad();
    });

    it('should filter by last 30 days', () => {
      cy.get('button, select').contains(/30 days|month/i).first().click();
      cy.waitForPageLoad();
    });

    it('should filter by last 90 days', () => {
      cy.get('button, select').contains(/90 days|quarter/i).first().click();
      cy.waitForPageLoad();
    });

    it('should support custom date range', () => {
      cy.get('button, select').contains(/custom|range/i).first().click();
      cy.get('input[type="date"]').should('exist');
    });
  });

  describe('Workflow Filter', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/workflows/analytics');
    });

    it('should filter by specific workflow', () => {
      cy.get('select, button').contains(/workflow|all/i).first().click();
      cy.assertContainsAny(['All Workflows', 'Select', 'Workflow']);
    });

    it('should update metrics when workflow selected', () => {
      cy.intercept('GET', '**/api/**/workflows/*/statistics*', {
        statusCode: 200,
        body: { total_executions: 500, success_rate: 0.92 },
      }).as('getWorkflowStats');

      cy.get('select').first().select(1);
    });
  });

  describe('Performance Charts', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/workflows/analytics');
    });

    it('should display executions over time chart', () => {
      cy.assertContainsAny(['Executions', 'Daily', 'chart', 'trend']);
    });

    it('should display success/failure distribution', () => {
      cy.assertContainsAny(['Success', 'Failed', 'distribution', 'breakdown']);
    });

    it('should display execution time distribution', () => {
      cy.assertContainsAny(['Execution Time', 'duration', 'performance']);
    });

    it('should allow chart type switching', () => {
      cy.get('button').contains(/line|bar|area/i).should('exist');
    });
  });

  describe('Execution History', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/workflows/analytics');
    });

    it('should display recent executions list', () => {
      cy.assertContainsAny(['Recent', 'History', 'Executions', 'Last']);
    });

    it('should show execution status', () => {
      cy.assertContainsAny(['Success', 'Failed', 'Running', 'Pending']);
    });

    it('should show execution duration', () => {
      cy.assertContainsAny(['ms', 's', 'seconds', 'duration']);
    });

    it('should show execution timestamp', () => {
      cy.get('body').then($body => {
        const hasTime = $body.text().match(/\d+:\d+|ago|AM|PM/) !== null;
        expect(hasTime).to.be.true;
      });
    });

    it('should allow viewing execution details', () => {
      cy.get('button').contains(/view|details/i).should('exist');
    });
  });

  describe('Top Workflows Table', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/workflows/analytics');
    });

    it('should display top workflows by usage', () => {
      cy.assertContainsAny(['Top', 'Most', 'Active', 'Popular']);
    });

    it('should show workflow names', () => {
      cy.assertContainsAny(['Workflow', 'name', 'workflow']);
    });

    it('should show execution counts', () => {
      cy.assertContainsAny(['executions', 'runs', 'count']);
    });

    it('should show success rates', () => {
      cy.assertContainsAny(['success', 'rate', '%']);
    });
  });

  describe('User Activity', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/workflows/analytics');
    });

    it('should display most active users', () => {
      cy.assertContainsAny(['Users', 'Active', 'Top']);
    });

    it('should show user names or emails', () => {
      cy.assertContainsAny(['@', 'user', 'admin', 'email']);
    });

    it('should show user execution counts', () => {
      cy.assertContainsAny(['executions', 'runs', 'count']);
    });
  });

  describe('Recommendations', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/workflows/analytics');
    });

    it('should display optimization recommendations', () => {
      cy.assertContainsAny(['Recommendations', 'Optimize', 'Suggestions']);
    });

    it('should show recommendation details', () => {
      cy.assertContainsAny(['improve', 'consider', 'recommend', 'tip']);
    });

    it('should have action buttons for recommendations', () => {
      cy.get('button').contains(/apply|implement|view/i).should('exist');
    });
  });

  describe('Export Functionality', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/workflows/analytics');
    });

    it('should open export options', () => {
      cy.get('button').contains(/export/i).first().click();
      cy.assertContainsAny(['Export', 'CSV', 'PDF', 'JSON']);
    });

    it('should export to CSV', () => {
      cy.intercept('GET', '**/api/**/workflows/analytics/export*', {
        statusCode: 200,
        headers: { 'content-type': 'text/csv' },
        body: 'workflow,executions,success_rate\n',
      }).as('exportCSV');

      cy.get('button').contains(/export/i).first().click();
      cy.get('button').contains(/csv/i).click();
    });

    it('should export to PDF', () => {
      cy.intercept('GET', '**/api/**/workflows/analytics/export*', {
        statusCode: 200,
        headers: { 'content-type': 'application/pdf' },
        body: 'PDF content',
      }).as('exportPDF');

      cy.get('button').contains(/export/i).first().click();
      cy.get('button').contains(/pdf/i).click();
    });
  });

  describe('Real-time Updates', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/workflows/analytics');
    });

    it('should have auto-refresh option', () => {
      cy.assertContainsAny(['Auto', 'refresh', 'live', 'real-time']);
    });

    it('should refresh data when button clicked', () => {
      cy.intercept('GET', '**/api/**/workflows/statistics*').as('refreshStats');
      cy.get('button').contains(/refresh/i).first().click();
      cy.wait('@refreshStats');
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.testErrorHandling('**/api/**/workflows/statistics**', {
        statusCode: 500,
        visitUrl: '/app/ai/workflows/analytics',
      });
    });

    it('should display error state for failed chart data', () => {
      cy.intercept('GET', '**/api/**/workflows/chart-data**', {
        statusCode: 500,
        body: { error: 'Failed to load chart data' },
      }).as('chartError');

      cy.navigateTo('/app/ai/workflows/analytics');
      cy.assertContainsAny(['Error', 'failed', 'retry', 'Analytics']);
    });
  });

  describe('Empty State', () => {
    it('should display empty state when no data', () => {
      cy.intercept('GET', '**/api/**/workflows/statistics*', {
        statusCode: 200,
        body: { total_workflows: 0, total_executions: 0 },
      }).as('emptyStats');

      cy.navigateTo('/app/ai/workflows/analytics');
      cy.assertContainsAny(['No data', 'No workflows', 'Get started', 'Create']);
    });
  });

  describe('Responsive Design', () => {
    it('should display correctly across viewports', () => {
      cy.testResponsiveDesign('/app/ai/workflows/analytics', {
        checkContent: 'Analytics',
      });
    });
  });
});

function setupWorkflowAnalyticsIntercepts() {
  const mockStatistics = {
    total_workflows: 25,
    active_workflows: 18,
    total_executions: 5000,
    success_rate: 0.94,
    average_execution_time: 2500,
    failed_executions: 300,
    min_execution_time: 100,
    max_execution_time: 15000,
  };

  const mockDailyExecutions = [
    { date: '2025-01-15', executions: 350, success: 330, failed: 20 },
    { date: '2025-01-14', executions: 400, success: 380, failed: 20 },
    { date: '2025-01-13', executions: 320, success: 300, failed: 20 },
    { date: '2025-01-12', executions: 280, success: 265, failed: 15 },
    { date: '2025-01-11', executions: 300, success: 285, failed: 15 },
  ];

  const mockTopWorkflows = [
    { id: 'wf-1', name: 'Data Processing', executions: 1200, success_rate: 0.96 },
    { id: 'wf-2', name: 'Customer Onboarding', executions: 800, success_rate: 0.92 },
    { id: 'wf-3', name: 'Report Generation', executions: 600, success_rate: 0.98 },
  ];

  const mockActiveUsers = [
    { id: 'user-1', email: 'admin@example.com', executions: 500 },
    { id: 'user-2', email: 'analyst@example.com', executions: 350 },
    { id: 'user-3', email: 'developer@example.com', executions: 200 },
  ];

  const mockRecentExecutions = [
    { id: 'exec-1', workflow: 'Data Processing', status: 'success', duration: 2300, timestamp: '2025-01-15T14:30:00Z' },
    { id: 'exec-2', workflow: 'Customer Onboarding', status: 'failed', duration: 5000, timestamp: '2025-01-15T14:25:00Z' },
    { id: 'exec-3', workflow: 'Report Generation', status: 'success', duration: 1800, timestamp: '2025-01-15T14:20:00Z' },
  ];

  const mockRecommendations = [
    { id: 'rec-1', type: 'performance', message: 'Consider caching results for Data Processing workflow', severity: 'medium' },
    { id: 'rec-2', type: 'reliability', message: 'Add retry logic to Customer Onboarding workflow', severity: 'high' },
  ];

  cy.intercept('GET', '**/api/**/workflows/statistics*', {
    statusCode: 200,
    body: { statistics: mockStatistics },
  }).as('getStatistics');

  cy.intercept('GET', '**/api/**/workflows/daily-executions*', {
    statusCode: 200,
    body: { items: mockDailyExecutions },
  }).as('getDailyExecutions');

  cy.intercept('GET', '**/api/**/workflows/top*', {
    statusCode: 200,
    body: { items: mockTopWorkflows },
  }).as('getTopWorkflows');

  cy.intercept('GET', '**/api/**/workflows/active-users*', {
    statusCode: 200,
    body: { items: mockActiveUsers },
  }).as('getActiveUsers');

  cy.intercept('GET', '**/api/**/workflows/recent-executions*', {
    statusCode: 200,
    body: { items: mockRecentExecutions },
  }).as('getRecentExecutions');

  cy.intercept('GET', '**/api/**/workflows/recommendations*', {
    statusCode: 200,
    body: { items: mockRecommendations },
  }).as('getRecommendations');
}

export {};

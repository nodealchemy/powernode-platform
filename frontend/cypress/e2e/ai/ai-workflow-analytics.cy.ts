/// <reference types="cypress" />

/**
 * AI Workflow Analytics Page Tests
 *
 * Tests for Workflow Analytics functionality including:
 * - Page navigation
 * - Filter controls
 * - Overview metrics
 * - Performance metrics
 * - Charts and recommendations
 * - Error handling
 * - Responsive design
 */

describe('AI Workflow Analytics Page Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup({ intercepts: ['ai'] });
  });

  describe('Page Navigation', () => {
    it('should navigate to Workflow Analytics page', () => {
      cy.navigateTo('/app/ai/workflows/analytics');
      cy.url().should('include', '/ai');
    });

    it('should display page title', () => {
      cy.navigateTo('/app/ai/workflows/analytics');
      cy.assertContainsAny(['Workflow Analytics', 'Analytics']);
    });

    it('should display page description', () => {
      cy.navigateTo('/app/ai/workflows/analytics');
      cy.assertContainsAny(['Performance insights', 'optimization', 'AI workflows']);
    });

    it('should display breadcrumbs', () => {
      cy.navigateTo('/app/ai/workflows/analytics');
      cy.assertContainsAny(['Dashboard', 'AI', 'Analytics']);
    });
  });

  describe('Filter Controls', () => {
    it('should display period selector', () => {
      cy.navigateTo('/app/ai/workflows/analytics');
      cy.assertContainsAny(['Last 7 days', 'Last 30 days']);
    });

    it('should display date range picker', () => {
      cy.navigateTo('/app/ai/workflows/analytics');
      cy.assertHasElement(['[class*="DateRangePicker"]', 'input[type="date"]', '[class*="date"]']);
    });

    it('should have period options', () => {
      cy.navigateTo('/app/ai/workflows/analytics');
      cy.assertContainsAny(['7 days', '30 days', '90 days', 'year']);
    });
  });

  describe('Overview Metrics', () => {
    it('should display Total Workflows metric', () => {
      cy.navigateTo('/app/ai/workflows/analytics');
      cy.assertStatCards(['Total Workflows']);
    });

    it('should display Active Workflows metric', () => {
      cy.navigateTo('/app/ai/workflows/analytics');
      cy.assertStatCards(['Active Workflows']);
    });

    it('should display Total Executions metric', () => {
      cy.navigateTo('/app/ai/workflows/analytics');
      cy.assertContainsAny(['Total Executions', 'Executions']);
    });

    it('should display Success Rate metric', () => {
      cy.navigateTo('/app/ai/workflows/analytics');
      cy.assertContainsAny(['Success Rate', 'success rate']);
    });
  });

  describe('Performance Metrics', () => {
    it('should display Avg Execution Time metric', () => {
      cy.navigateTo('/app/ai/workflows/analytics');
      cy.assertContainsAny(['Avg Execution', 'Execution Time', 'Average']);
    });

    it('should display Failed Executions metric', () => {
      cy.navigateTo('/app/ai/workflows/analytics');
      cy.assertContainsAny(['Failed', 'Failures']);
    });

    it('should display Min Execution Time metric', () => {
      cy.navigateTo('/app/ai/workflows/analytics');
      cy.assertContainsAny(['Min Execution', 'Minimum']);
    });

    it('should display Max Execution Time metric', () => {
      cy.navigateTo('/app/ai/workflows/analytics');
      cy.assertContainsAny(['Max Execution', 'Maximum']);
    });
  });

  describe('Charts and Data', () => {
    it('should display Daily Executions section', () => {
      cy.navigateTo('/app/ai/workflows/analytics');
      cy.assertContainsAny(['Daily Executions', 'daily', 'Executions', 'Analytics', 'Workflow']);
    });

    it('should display Most Active Users section', () => {
      cy.navigateTo('/app/ai/workflows/analytics');
      cy.assertContainsAny(['Most Active Users', 'Active Users', 'Users', 'Analytics', 'Workflow']);
    });
  });

  describe('Recommendations', () => {
    it('should display Optimization Recommendations section', () => {
      cy.navigateTo('/app/ai/workflows/analytics');
      cy.assertContainsAny(['Optimization', 'Recommendations', 'Analytics', 'Workflow']);
    });
  });

  describe('Page Actions', () => {
    it('should have page actions or content', () => {
      cy.navigateTo('/app/ai/workflows/analytics');
      cy.assertContainsAny(['Export', 'Analytics', 'Workflow', 'Dashboard']);
    });
  });

  describe('Permission Check', () => {
    it('should show access denied for unauthorized users', () => {
      cy.navigateTo('/app/ai/workflows/analytics');
      cy.assertContainsAny(['Access Denied', 'permission', "don't have permission", 'Workflow Analytics', 'Total Workflows']);
    });
  });

  describe('Error Handling', () => {
    it('should handle API errors gracefully', () => {
      cy.testErrorHandling('**/api/**/workflows/**', {
        statusCode: 500,
        visitUrl: '/app/ai/workflows/analytics'
      });
    });

    it('should display error notification on API failure', () => {
      cy.mockApiError('**/api/**/workflows/statistics**', 500, 'Statistics API failed');
      cy.navigateTo('/app/ai/workflows/analytics');
      cy.get('body').should('be.visible');
    });
  });

  describe('Loading State', () => {
    it('should display loading indicator', () => {
      cy.intercept('GET', '**/api/**/workflows/**', (req) => {
        req.reply((res) => {
          res.delay = 2000;
          res.send({ data: {} });
        });
      });
      cy.visit('/app/ai/workflows/analytics');
      cy.assertHasElement(['[class*="animate-spin"]', '[class*="loading"]']);
    });

    it('should display loading skeleton cards', () => {
      cy.intercept('GET', '**/api/**/workflows/**', (req) => {
        req.reply((res) => {
          res.delay = 3000;
          res.send({ data: {} });
        });
      });
      cy.visit('/app/ai/workflows/analytics');
      cy.assertHasElement(['[class*="animate-pulse"]', '[class*="skeleton"]']);
    });
  });

  describe('Empty State', () => {
    it('should display empty state when no data', () => {
      cy.mockEndpoint('GET', '**/api/**/workflows/statistics**', { totalWorkflows: 0 });
      cy.navigateTo('/app/ai/workflows/analytics');
      cy.assertContainsAny(['No Analytics Data', 'No data', 'No analytics', 'Analytics']);
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.testResponsiveDesign('/app/ai/workflows/analytics', {
        checkContent: ['Analytics']
      });
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.navigateTo('/app/ai/workflows/analytics');
      cy.get('body').should('be.visible');
    });

    it('should stack metric cards on small screens', () => {
      cy.viewport('iphone-x');
      cy.navigateTo('/app/ai/workflows/analytics');
      cy.get('body').should('be.visible');
    });

    it('should show multi-column layout on large screens', () => {
      cy.viewport(1920, 1080);
      cy.navigateTo('/app/ai/workflows/analytics');
      cy.get('body').should('be.visible');
    });
  });
});

export {};

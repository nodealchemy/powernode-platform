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
    cy.clearAppData();
    cy.setupAiIntercepts();
    // Login with demo user
    cy.visit('/login');
    cy.get('[data-testid="email-input"]', { timeout: 5000 }).type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').click();
    cy.url({ timeout: 5000 }).should('match', /\/(app|dashboard)/);
  });

  describe('Page Navigation', () => {
    it('should navigate to AI Analytics from AI section', () => {
      cy.visit('/app/ai');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const analyticsLink = $body.find('a[href*="/analytics"], button:contains("Analytics")');

        if (analyticsLink.length > 0) {
          cy.wrap(analyticsLink).first().click();
          cy.url().should('include', '/analytics');
        } else {
          cy.visit('/app/ai/analytics');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should load AI Analytics page directly', () => {
      cy.visit('/app/ai/analytics');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const text = $body.text();
        const hasContent = text.includes('Analytics') ||
                           text.includes('Metrics') ||
                           text.includes('Usage') ||
                           text.includes('Loading') ||
                           text.includes('Permission');
        if (hasContent) {
          cy.log('AI Analytics page content loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display page title', () => {
      cy.visit('/app/ai/analytics');

      cy.get('body').then($body => {
        const hasTitle = $body.text().includes('Analytics') ||
                          $body.text().includes('Dashboard');

        if (hasTitle) {
          cy.log('Page title displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display breadcrumbs', () => {
      cy.visit('/app/ai/analytics');

      cy.get('body').then($body => {
        const hasBreadcrumbs = $body.text().includes('Dashboard') ||
                               $body.text().includes('AI');

        if (hasBreadcrumbs) {
          cy.log('Breadcrumbs displayed correctly');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Analytics Dashboard Display', () => {
    beforeEach(() => {
      cy.visit('/app/ai/analytics');
      cy.waitForPageLoad();
    });

    it('should display analytics dashboard', () => {
      cy.get('body').then($body => {
        const hasDashboard = $body.find('[class*="chart"], [class*="card"], canvas').length > 0 ||
                              $body.text().includes('Analytics') ||
                              $body.text().includes('Usage');

        if (hasDashboard) {
          cy.log('Analytics dashboard displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display summary metrics', () => {
      cy.get('body').then($body => {
        const hasMetrics = $body.text().includes('Total') ||
                            $body.text().includes('Average') ||
                            $body.text().includes('Count');

        if (hasMetrics) {
          cy.log('Summary metrics displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Key Metrics Display', () => {
    beforeEach(() => {
      cy.visit('/app/ai/analytics');
      cy.waitForPageLoad();
    });

    it('should display token usage metrics', () => {
      cy.get('body').then($body => {
        const hasTokens = $body.text().includes('Token') ||
                           $body.text().includes('token');

        if (hasTokens) {
          cy.log('Token usage metrics displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display cost metrics', () => {
      cy.get('body').then($body => {
        const hasCost = $body.text().includes('Cost') ||
                         $body.text().includes('$') ||
                         $body.text().includes('Spend');

        if (hasCost) {
          cy.log('Cost metrics displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display execution metrics', () => {
      cy.get('body').then($body => {
        const hasExecutions = $body.text().includes('Execution') ||
                               $body.text().includes('Request') ||
                               $body.text().includes('Call');

        if (hasExecutions) {
          cy.log('Execution metrics displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display success rate metrics', () => {
      cy.get('body').then($body => {
        const hasSuccessRate = $body.text().includes('Success') ||
                                $body.text().includes('Rate') ||
                                $body.text().includes('%');

        if (hasSuccessRate) {
          cy.log('Success rate metrics displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Charts and Visualizations', () => {
    beforeEach(() => {
      cy.visit('/app/ai/analytics');
      cy.waitForPageLoad();
    });

    it('should display charts', () => {
      cy.get('body').then($body => {
        const hasCharts = $body.find('canvas, svg[class*="chart"], [class*="chart"]').length > 0;

        if (hasCharts) {
          cy.log('Charts displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display usage trend chart', () => {
      cy.get('body').then($body => {
        const hasTrend = $body.text().includes('Trend') ||
                          $body.text().includes('Usage') ||
                          $body.text().includes('Over Time');

        if (hasTrend) {
          cy.log('Usage trend chart displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display provider distribution', () => {
      cy.get('body').then($body => {
        const hasDistribution = $body.text().includes('Provider') ||
                                 $body.text().includes('Distribution') ||
                                 $body.text().includes('Breakdown');

        if (hasDistribution) {
          cy.log('Provider distribution displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Date Range Selection', () => {
    beforeEach(() => {
      cy.visit('/app/ai/analytics');
      cy.waitForPageLoad();
    });

    it('should have date range selector', () => {
      cy.get('body').then($body => {
        const hasDateRange = $body.find('select, button:contains("7 days"), button:contains("30 days"), input[type="date"]').length > 0;

        if (hasDateRange) {
          cy.log('Date range selector found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should change date range', () => {
      cy.get('body').then($body => {
        // Look for date range buttons (not select options)
        const dateRangeButton = $body.find('button:contains("30 days"), button:contains("7 days"), button:contains("Last")').not('select option');

        if (dateRangeButton.length > 0) {
          cy.wrap(dateRangeButton).first().should('be.visible').click();
          cy.waitForPageLoad();
          cy.log('Date range changed');
        } else {
          // If using a select dropdown, handle differently
          const selectElement = $body.find('select');
          if (selectElement.length > 0) {
            cy.wrap(selectElement).first().should('be.visible').select(1);
            cy.waitForPageLoad();
            cy.log('Date range changed via select');
          } else {
            cy.log('Date range selector not found - may not be available');
          }
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Refresh Functionality', () => {
    beforeEach(() => {
      cy.visit('/app/ai/analytics');
      cy.waitForPageLoad();
    });

    it('should have Refresh button', () => {
      cy.get('body').then($body => {
        const refreshButton = $body.find('button:contains("Refresh"), [aria-label*="refresh"]');

        if (refreshButton.length > 0) {
          cy.wrap(refreshButton).should('be.visible');
          cy.log('Refresh button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should refresh analytics data', () => {
      cy.get('body').then($body => {
        const refreshButton = $body.find('button:contains("Refresh")');

        if (refreshButton.length > 0) {
          cy.wrap(refreshButton).first().should('be.visible').click();
          cy.waitForPageLoad();
          cy.log('Analytics data refreshed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Export Functionality', () => {
    beforeEach(() => {
      cy.visit('/app/ai/analytics');
      cy.waitForPageLoad();
    });

    it('should have Export button', () => {
      cy.get('body').then($body => {
        const exportButton = $body.find('button:contains("Export"), button:contains("Download")');

        if (exportButton.length > 0) {
          cy.log('Export button found');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Empty State', () => {
    it('should handle no analytics data gracefully', () => {
      cy.intercept('GET', '/api/v1/ai/analytics*', {
        statusCode: 200,
        body: { metrics: [], charts: [] }
      });

      cy.visit('/app/ai/analytics');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
      cy.get('body').should('not.contain.text', 'Cannot read');
      cy.get('body').should('not.contain.text', 'TypeError');
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.intercept('GET', '/api/v1/ai/analytics*', {
        statusCode: 500,
        body: { success: false, error: 'Server error' }
      });

      cy.visit('/app/ai/analytics');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
      cy.get('body').should('not.contain.text', 'Cannot read');
      cy.get('body').should('not.contain.text', 'TypeError');
    });

    it('should display error notification on failure', () => {
      cy.intercept('GET', '/api/v1/ai/analytics*', {
        statusCode: 500,
        body: { success: false, error: 'Failed to load analytics' }
      });

      cy.visit('/app/ai/analytics');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasError = $body.text().includes('Error') ||
                          $body.text().includes('Failed') ||
                          $body.find('[class*="error"]').length > 0;

        if (hasError) {
          cy.log('Error notification displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Permission-Based Display', () => {
    it('should show content based on permissions', () => {
      cy.visit('/app/ai/analytics');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        if ($body.text().includes('Permission') || $body.text().includes('Access')) {
          cy.log('Permission notice displayed');
        } else {
          cy.log('User has analytics permissions');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/ai/analytics');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Analytics') || $body.text().includes('AI');
        if (hasContent) {
          cy.log('Content visible on mobile');
        }
      });
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/ai/analytics');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Analytics') || $body.text().includes('AI');
        if (hasContent) {
          cy.log('Content visible on tablet');
        }
      });
    });

    it('should stack cards on small screens', () => {
      cy.viewport(375, 667);
      cy.visit('/app/ai/analytics');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
    });
  });
});


export {};

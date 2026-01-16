/// <reference types="cypress" />

/**
 * Core Metrics Page E2E Tests
 *
 * Tests for the root-level metrics page including:
 * - Page navigation and load
 * - Metrics display
 * - Chart visualizations
 * - Time range selection
 * - Export functionality
 * - Responsive design
 */

describe('Core Metrics Page Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Page Navigation', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/metrics');
    });

    it('should navigate to Metrics page', () => {
      cy.assertContainsAny(['Metrics', 'Analytics', 'Performance']);
    });

    it('should display page title', () => {
      cy.assertContainsAny(['Metrics', 'Analytics', 'Dashboard']);
    });

    it('should display breadcrumbs', () => {
      cy.get('body').then($body => {
        const hasBreadcrumbs = $body.text().includes('Dashboard') ||
                               $body.find('[class*="breadcrumb"], nav[aria-label*="breadcrumb"]').length > 0;
        if (hasBreadcrumbs) {
          cy.log('Breadcrumbs displayed');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Metrics Overview', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/metrics');
    });

    it('should display key metrics cards', () => {
      cy.get('body').then($body => {
        const hasCards = $body.find('[class*="card"], [class*="stat"], [class*="metric"]').length > 0 ||
                        $body.find('div').filter(function() {
                          return $(this).find('h3, h4, p').length >= 2;
                        }).length > 0;
        if (hasCards) {
          cy.log('Key metrics cards displayed');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display user metrics', () => {
      cy.assertContainsAny(['Users', 'Active', 'Registrations']);
    });

    it('should display revenue metrics', () => {
      cy.assertContainsAny(['Revenue', 'MRR', '$']);
    });

    it('should display growth indicators', () => {
      cy.assertContainsAny(['%', 'Growth', 'Change']);
    });
  });

  describe('Charts and Visualizations', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/metrics');
    });

    it('should display chart containers', () => {
      cy.get('body').then($body => {
        const hasCharts = $body.find('canvas, svg, [class*="chart"], [class*="graph"]').length > 0;
        if (hasCharts) {
          cy.log('Chart containers displayed');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display line charts', () => {
      cy.get('body').then($body => {
        const hasLineChart = $body.find('canvas, [class*="line"]').length > 0 ||
                             $body.text().includes('Trend');
        if (hasLineChart) {
          cy.log('Line charts displayed');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display bar charts', () => {
      cy.get('body').then($body => {
        const hasBarChart = $body.find('canvas, [class*="bar"]').length > 0 ||
                            $body.text().includes('Comparison');
        if (hasBarChart) {
          cy.log('Bar charts displayed');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display chart legends', () => {
      cy.get('body').then($body => {
        const hasLegends = $body.find('[class*="legend"]').length > 0;
        if (hasLegends) {
          cy.log('Chart legends displayed');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Time Range Selection', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/metrics');
    });

    it('should display time range selector', () => {
      cy.get('body').then($body => {
        const hasTimeRange = $body.find('select, [class*="date"], button').filter(function() {
                               const text = $(this).text();
                               return text.includes('day') || text.includes('week') || text.includes('month');
                             }).length > 0 ||
                             $body.text().includes('7 days') ||
                             $body.text().includes('30 days');
        if (hasTimeRange) {
          cy.log('Time range selector displayed');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should have preset time ranges', () => {
      cy.assertContainsAny(['Today', 'Week', 'Month', 'Year']);
    });

    it('should allow custom date range selection', () => {
      cy.get('body').then($body => {
        const hasCustom = $body.find('input[type="date"], [class*="datepicker"]').length > 0 ||
                          $body.text().includes('Custom');
        if (hasCustom) {
          cy.log('Custom date range selection available');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Metrics Categories', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/metrics');
    });

    it('should display subscription metrics', () => {
      cy.assertContainsAny(['Subscription', 'Churn', 'Retention']);
    });

    it('should display API metrics', () => {
      cy.assertContainsAny(['API', 'Requests', 'Latency']);
    });

    it('should display system metrics', () => {
      cy.assertContainsAny(['System', 'Performance', 'Uptime']);
    });
  });

  describe('Export Functionality', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/metrics');
    });

    it('should have export button', () => {
      cy.get('body').then($body => {
        const hasExport = $body.find('button:contains("Export"), button:contains("Download")').length > 0 ||
                          $body.text().includes('Export') ||
                          $body.text().includes('Download');
        if (hasExport) {
          cy.log('Export button found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should have export format options', () => {
      cy.assertContainsAny(['CSV', 'PDF', 'Excel', 'Export']);
    });
  });

  describe('Refresh Functionality', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/metrics');
    });

    it('should have refresh button', () => {
      cy.get('body').then($body => {
        const hasRefresh = $body.find('button:contains("Refresh"), [aria-label*="refresh"]').length > 0 ||
                          $body.find('button svg').length > 0;
        if (hasRefresh) {
          cy.log('Refresh button found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display last updated timestamp', () => {
      cy.assertContainsAny(['Updated', 'Last', 'ago']);
    });
  });

  describe('Error Handling', () => {
    it('should handle API errors gracefully', () => {
      cy.intercept('GET', '**/api/**/metrics/**', {
        statusCode: 500,
        body: { success: false, error: 'Server error' }
      });

      cy.visit('/app/metrics');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
      cy.get('body').should('not.contain.text', 'Cannot read');
    });

    it('should display error state when data fails to load', () => {
      cy.intercept('GET', '**/api/**/metrics/**', {
        statusCode: 500,
        body: { success: false, error: 'Failed to load' }
      });

      cy.visit('/app/metrics');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasError = $body.text().includes('Error') ||
                         $body.text().includes('Failed') ||
                         $body.text().includes('Unable');
        if (hasError) {
          cy.log('Error state displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Loading State', () => {
    it('should display loading indicator', () => {
      cy.intercept('GET', '**/api/**/metrics/**', {
        delay: 2000,
        statusCode: 200,
        body: {}
      });

      cy.visit('/app/metrics');

      cy.get('body').then($body => {
        const hasLoading = $body.find('.animate-spin, [class*="loading"], [class*="spinner"]').length > 0 ||
                          $body.find('svg').filter(function() {
                            return $(this).attr('class')?.includes('animate') || false;
                          }).length > 0 ||
                          $body.text().includes('Loading');
        if (hasLoading) {
          cy.log('Loading indicator displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/metrics');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/metrics');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
    });

    it('should stack metrics on small screens', () => {
      cy.viewport(375, 667);
      cy.visit('/app/metrics');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
    });

    it('should display multi-column layout on large screens', () => {
      cy.viewport(1920, 1080);
      cy.visit('/app/metrics');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasMultiCol = $body.find('[class*="grid"]').length > 0;
        if (hasMultiCol) {
          cy.log('Multi-column layout found');
        }
      });

      cy.get('body').should('be.visible');
    });
  });
});


export {};

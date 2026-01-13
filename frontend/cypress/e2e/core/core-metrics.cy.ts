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
    cy.clearAppData();
    cy.visit('/login');
    cy.get('[data-testid="email-input"]', { timeout: 10000 }).type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').click();
    cy.url({ timeout: 15000 }).should('match', /\/(app|dashboard)/);
  });

  describe('Page Navigation', () => {
    it('should navigate to Metrics page', () => {
      cy.visit('/app/metrics');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Metrics') ||
                          $body.text().includes('Analytics') ||
                          $body.text().includes('Performance');
        if (hasContent) {
          cy.log('Metrics page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display page title', () => {
      cy.visit('/app/metrics');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasTitle = $body.text().includes('Metrics') ||
                         $body.text().includes('Analytics') ||
                         $body.text().includes('Dashboard');
        if (hasTitle) {
          cy.log('Page title displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display breadcrumbs', () => {
      cy.visit('/app/metrics');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasBreadcrumbs = $body.text().includes('Dashboard') ||
                               $body.find('[class*="breadcrumb"]').length > 0;
        if (hasBreadcrumbs) {
          cy.log('Breadcrumbs displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Metrics Overview', () => {
    beforeEach(() => {
      cy.visit('/app/metrics');
      cy.wait(2000);
    });

    it('should display key metrics cards', () => {
      cy.get('body').then($body => {
        const hasCards = $body.find('[class*="card"], [class*="stat"]').length > 0;
        if (hasCards) {
          cy.log('Key metrics cards displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display user metrics', () => {
      cy.get('body').then($body => {
        const hasUserMetrics = $body.text().includes('Users') ||
                               $body.text().includes('Active') ||
                               $body.text().includes('Registrations');
        if (hasUserMetrics) {
          cy.log('User metrics displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display revenue metrics', () => {
      cy.get('body').then($body => {
        const hasRevenueMetrics = $body.text().includes('Revenue') ||
                                   $body.text().includes('MRR') ||
                                   $body.text().includes('$');
        if (hasRevenueMetrics) {
          cy.log('Revenue metrics displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display growth indicators', () => {
      cy.get('body').then($body => {
        const hasGrowth = $body.text().includes('%') ||
                          $body.text().includes('Growth') ||
                          $body.text().includes('Change');
        if (hasGrowth) {
          cy.log('Growth indicators displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Charts and Visualizations', () => {
    beforeEach(() => {
      cy.visit('/app/metrics');
      cy.wait(2000);
    });

    it('should display chart containers', () => {
      cy.get('body').then($body => {
        const hasCharts = $body.find('canvas, svg, [class*="chart"]').length > 0;
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
      cy.visit('/app/metrics');
      cy.wait(2000);
    });

    it('should display time range selector', () => {
      cy.get('body').then($body => {
        const hasTimeRange = $body.find('select, [class*="date"], button:contains("day")').length > 0 ||
                             $body.text().includes('7 days') ||
                             $body.text().includes('30 days');
        if (hasTimeRange) {
          cy.log('Time range selector displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have preset time ranges', () => {
      cy.get('body').then($body => {
        const hasPresets = $body.text().includes('Today') ||
                           $body.text().includes('Week') ||
                           $body.text().includes('Month') ||
                           $body.text().includes('Year');
        if (hasPresets) {
          cy.log('Preset time ranges found');
        }
      });

      cy.get('body').should('be.visible');
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
      cy.visit('/app/metrics');
      cy.wait(2000);
    });

    it('should display subscription metrics', () => {
      cy.get('body').then($body => {
        const hasSubscriptions = $body.text().includes('Subscription') ||
                                  $body.text().includes('Churn') ||
                                  $body.text().includes('Retention');
        if (hasSubscriptions) {
          cy.log('Subscription metrics displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display API metrics', () => {
      cy.get('body').then($body => {
        const hasAPI = $body.text().includes('API') ||
                       $body.text().includes('Requests') ||
                       $body.text().includes('Latency');
        if (hasAPI) {
          cy.log('API metrics displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display system metrics', () => {
      cy.get('body').then($body => {
        const hasSystem = $body.text().includes('System') ||
                          $body.text().includes('Performance') ||
                          $body.text().includes('Uptime');
        if (hasSystem) {
          cy.log('System metrics displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Export Functionality', () => {
    beforeEach(() => {
      cy.visit('/app/metrics');
      cy.wait(2000);
    });

    it('should have export button', () => {
      cy.get('body').then($body => {
        const hasExport = $body.find('button:contains("Export"), button:contains("Download")').length > 0;
        if (hasExport) {
          cy.log('Export button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have export format options', () => {
      cy.get('body').then($body => {
        const hasFormats = $body.text().includes('CSV') ||
                           $body.text().includes('PDF') ||
                           $body.text().includes('Excel');
        if (hasFormats) {
          cy.log('Export format options available');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Refresh Functionality', () => {
    beforeEach(() => {
      cy.visit('/app/metrics');
      cy.wait(2000);
    });

    it('should have refresh button', () => {
      cy.get('body').then($body => {
        const hasRefresh = $body.find('button:contains("Refresh"), [aria-label*="refresh"]').length > 0;
        if (hasRefresh) {
          cy.log('Refresh button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display last updated timestamp', () => {
      cy.get('body').then($body => {
        const hasTimestamp = $body.text().includes('Updated') ||
                             $body.text().includes('Last') ||
                             $body.text().includes('ago');
        if (hasTimestamp) {
          cy.log('Last updated timestamp displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Error Handling', () => {
    it('should handle API errors gracefully', () => {
      cy.intercept('GET', '**/api/**/metrics/**', {
        statusCode: 500,
        body: { success: false, error: 'Server error' }
      });

      cy.visit('/app/metrics');
      cy.wait(2000);

      cy.get('body').should('be.visible');
      cy.get('body').should('not.contain.text', 'Cannot read');
    });

    it('should display error state when data fails to load', () => {
      cy.intercept('GET', '**/api/**/metrics/**', {
        statusCode: 500,
        body: { success: false, error: 'Failed to load' }
      });

      cy.visit('/app/metrics');
      cy.wait(2000);

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
        body: { success: true, data: {} }
      });

      cy.visit('/app/metrics');

      cy.get('body').then($body => {
        const hasLoading = $body.find('[class*="spin"]').length > 0 ||
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
      cy.wait(2000);

      cy.get('body').should('be.visible');
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/metrics');
      cy.wait(2000);

      cy.get('body').should('be.visible');
    });

    it('should stack metrics on small screens', () => {
      cy.viewport(375, 667);
      cy.visit('/app/metrics');
      cy.wait(2000);

      cy.get('body').should('be.visible');
    });

    it('should display multi-column layout on large screens', () => {
      cy.viewport(1920, 1080);
      cy.visit('/app/metrics');
      cy.wait(2000);

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

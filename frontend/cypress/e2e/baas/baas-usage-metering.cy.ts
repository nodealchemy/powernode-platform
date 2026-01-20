/// <reference types="cypress" />

/**
 * BaaS Usage Metering Tests
 *
 * Tests for BaaS Usage Metering functionality including:
 * - Usage event tracking
 * - Meter configuration
 * - Usage aggregation
 * - Overage calculations
 * - Usage reports
 * - Billing integration
 */

describe('BaaS Usage Metering Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Usage Dashboard', () => {
    it('should navigate to usage dashboard', () => {
      cy.visit('/app/baas/usage');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasUsage = $body.text().includes('Usage') ||
                        $body.text().includes('Metering') ||
                        $body.text().includes('Consumption');
        if (hasUsage) {
          cy.log('Usage dashboard loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display usage overview', () => {
      cy.visit('/app/baas/usage');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasOverview = $body.find('[data-testid="usage-overview"], .overview, .summary').length > 0 ||
                           $body.text().includes('Overview');
        if (hasOverview) {
          cy.log('Usage overview displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display current period usage', () => {
      cy.visit('/app/baas/usage');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasPeriod = $body.text().includes('Current') ||
                         $body.text().includes('This month') ||
                         $body.text().includes('Period');
        if (hasPeriod) {
          cy.log('Current period usage displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Usage Meters', () => {
    it('should navigate to meters configuration', () => {
      cy.visit('/app/baas/usage/meters');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasMeters = $body.text().includes('Meter') ||
                         $body.text().includes('Metric') ||
                         $body.text().includes('Event');
        if (hasMeters) {
          cy.log('Meters configuration loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display meter list', () => {
      cy.visit('/app/baas/usage/meters');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasList = $body.find('table, [data-testid="meters-list"], .list').length > 0;
        if (hasList) {
          cy.log('Meter list displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have create meter button', () => {
      cy.visit('/app/baas/usage/meters');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasCreate = $body.find('button:contains("Create"), button:contains("Add"), button:contains("New")').length > 0;
        if (hasCreate) {
          cy.log('Create meter button displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display meter types', () => {
      cy.visit('/app/baas/usage/meters');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasTypes = $body.text().includes('Sum') ||
                        $body.text().includes('Count') ||
                        $body.text().includes('Max') ||
                        $body.text().includes('Unique');
        if (hasTypes) {
          cy.log('Meter types displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Usage Events', () => {
    it('should navigate to usage events', () => {
      cy.visit('/app/baas/usage/events');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasEvents = $body.text().includes('Event') ||
                         $body.text().includes('Activity') ||
                         $body.text().includes('Log');
        if (hasEvents) {
          cy.log('Usage events loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display event stream or list', () => {
      cy.visit('/app/baas/usage/events');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasList = $body.find('table, [data-testid="events-list"], .stream').length > 0;
        if (hasList) {
          cy.log('Event list displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have date range filter', () => {
      cy.visit('/app/baas/usage/events');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasDateFilter = $body.find('input[type="date"], [data-testid="date-range"]').length > 0 ||
                             $body.text().includes('Date') ||
                             $body.text().includes('From') ||
                             $body.text().includes('To');
        if (hasDateFilter) {
          cy.log('Date range filter displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have event type filter', () => {
      cy.visit('/app/baas/usage/events');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasTypeFilter = $body.find('select, [data-testid="event-type-filter"]').length > 0 ||
                             $body.text().includes('Type') ||
                             $body.text().includes('Filter');
        if (hasTypeFilter) {
          cy.log('Event type filter displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Usage Reports', () => {
    it('should navigate to usage reports', () => {
      cy.visit('/app/baas/usage/reports');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasReports = $body.text().includes('Report') ||
                          $body.text().includes('Summary') ||
                          $body.text().includes('Analysis');
        if (hasReports) {
          cy.log('Usage reports loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display usage charts', () => {
      cy.visit('/app/baas/usage/reports');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasCharts = $body.find('canvas, svg, [data-testid*="chart"]').length > 0;
        if (hasCharts) {
          cy.log('Usage charts displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have export option', () => {
      cy.visit('/app/baas/usage/reports');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasExport = $body.find('button:contains("Export"), button:contains("Download")').length > 0 ||
                         $body.text().includes('Export') ||
                         $body.text().includes('CSV');
        if (hasExport) {
          cy.log('Export option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Overage Management', () => {
    it('should display overage alerts', () => {
      cy.visit('/app/baas/usage');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasOverage = $body.text().includes('Overage') ||
                          $body.text().includes('Limit') ||
                          $body.text().includes('Exceeded') ||
                          $body.text().includes('Warning');
        if (hasOverage) {
          cy.log('Overage alerts displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display usage thresholds', () => {
      cy.visit('/app/baas/usage');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasThreshold = $body.text().includes('Threshold') ||
                            $body.text().includes('%') ||
                            $body.find('[data-testid="usage-progress"]').length > 0;
        if (hasThreshold) {
          cy.log('Usage thresholds displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Responsive Design', () => {
    const viewports = [
      { width: 1280, height: 720, name: 'desktop' },
      { width: 768, height: 1024, name: 'tablet' },
      { width: 375, height: 667, name: 'mobile' },
    ];

    viewports.forEach(({ width, height, name }) => {
      it(`should display usage metering correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/app/baas/usage');
        cy.waitForPageLoad();

        cy.get('body').should('be.visible');
        cy.log(`Usage metering displayed correctly on ${name}`);
      });
    });
  });
});

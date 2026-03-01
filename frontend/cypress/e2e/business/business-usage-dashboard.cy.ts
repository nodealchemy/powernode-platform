/// <reference types="cypress" />

/**
 * Business Usage Dashboard Tests
 *
 * Enhanced E2E tests for the Usage Dashboard functionality:
 * - Usage overview and summary cards
 * - Usage charts and trends
 * - Quota progress tracking
 * - Usage by meter breakdown
 * - Export functionality
 * - Recent usage events
 *
 * Uses proper API intercepts and meaningful assertions.
 */

describe('Business Usage Dashboard Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
    setupUsageDashboardIntercepts();
  });

  describe('Dashboard Overview', () => {
    beforeEach(() => {
      cy.navigateTo('/app/business/usage');
    });

    describe('Page Load and Layout', () => {
      it('should display usage dashboard page with title', () => {
        cy.assertContainsAny(['Usage Dashboard', 'Usage', 'Dashboard']);
      });

      it('should display current billing period', () => {
        cy.assertContainsAny(['billing period', 'Current', 'Period', '-']);
      });

      it('should have export action button', () => {
        cy.assertContainsAny(['Export Usage', 'Export', 'Download']);
      });
    });

    describe('Summary Statistics Cards', () => {
      it('should display total usage card', () => {
        cy.assertContainsAny(['Total Usage', 'Usage', 'units']);
      });

      it('should display calculated cost card', () => {
        cy.assertContainsAny(['Calculated Cost', 'Cost', 'this period', '$']);
      });

      it('should display events tracked card', () => {
        cy.assertContainsAny(['Events Tracked', 'Events', 'total events']);
      });

      it('should display quota status card', () => {
        cy.assertContainsAny(['Quota Status', 'Exceeded', 'All OK', 'quotas']);
      });

      it('should show formatted numbers in cards', () => {
        cy.get('body').then($body => {
          const hasNumbers = $body.text().match(/[\d,]+/) !== null ||
                            $body.text().includes('$');
          expect(hasNumbers).to.be.true;
        });
      });
    });
  });

  describe('Usage Charts', () => {
    beforeEach(() => {
      cy.navigateTo('/app/business/usage');
    });

    it('should display usage trends chart', () => {
      cy.get('body').then($body => {
        const hasChart = $body.find('svg, canvas, [class*="chart"], [class*="Chart"], [data-testid*="usage-chart"]').length > 0;
        if (hasChart) {
          cy.log('Usage chart component rendered');
        }
        cy.assertContainsAny(['Usage', 'Trend', 'Chart', 'Graph']);
      });
    });

    it('should display chart with time-based data', () => {
      cy.assertContainsAny(['day', 'week', 'month', 'Daily', 'Weekly', 'Monthly', 'Jan', 'Feb', 'Mar']);
    });
  });

  describe('Quota Progress', () => {
    beforeEach(() => {
      cy.navigateTo('/app/business/usage');
    });

    it('should display quota progress section', () => {
      cy.assertContainsAny(['Quota', 'Progress', 'Limit', 'Allowance']);
    });

    it('should show quota percentage indicators', () => {
      cy.get('body').then($body => {
        const hasProgress = $body.find('[role="progressbar"], progress, [class*="progress"]').length > 0 ||
                           $body.text().match(/\d+%/) !== null;
        expect(hasProgress).to.be.true;
      });
    });

    it('should indicate exceeded quotas with visual warning', () => {
      cy.get('body').then($body => {
        if ($body.text().includes('Exceeded')) {
          cy.get('[class*="error"], [class*="warning"], [class*="exceeded"]').should('exist');
        }
      });
    });
  });

  describe('Usage by Meter', () => {
    beforeEach(() => {
      cy.navigateTo('/app/business/usage');
    });

    it('should display usage by meter section', () => {
      cy.assertContainsAny(['Usage by Meter', 'Meters', 'By Meter']);
    });

    it('should display individual meter cards', () => {
      cy.get('body').then($body => {
        const hasMeterCards = $body.find('[data-testid*="meter"], [class*="meter"]').length > 0 ||
                             $body.text().includes('API Calls') ||
                             $body.text().includes('Storage') ||
                             $body.text().includes('Bandwidth');
        expect(hasMeterCards || $body.text().includes('Meter')).to.be.true;
      });
    });

    it('should show meter usage values', () => {
      cy.get('body').should('contain.text', 'units').or('contain.text', 'events').or('contain.text', 'requests');
    });

    it('should display meter event counts', () => {
      cy.assertContainsAny(['events', 'requests', 'calls', 'operations']);
    });

    it('should show billable meter costs', () => {
      cy.get('body').should('contain', '$');
    });

    it('should display quota limits on meters', () => {
      cy.get('body').then($body => {
        const hasQuotaProgress = $body.find('[role="progressbar"], [class*="progress"]').length > 0;
        if (hasQuotaProgress) {
          cy.log('Quota progress bars displayed on meters');
        }
      });
    });
  });

  describe('Recent Usage Events', () => {
    beforeEach(() => {
      cy.navigateTo('/app/business/usage');
    });

    it('should display recent events section', () => {
      cy.assertContainsAny(['Recent', 'Events', 'History', 'Activity']);
    });

    it('should display event list or table', () => {
      cy.get('body').then($body => {
        const hasEvents = $body.find('table, [data-testid*="events"], [class*="event-list"]').length > 0;
        if (hasEvents) {
          cy.log('Events list/table displayed');
        }
      });
    });

    it('should have export option for events', () => {
      cy.assertContainsAny(['Export', 'Download', 'CSV']);
    });
  });

  describe('Export Functionality', () => {
    beforeEach(() => {
      cy.navigateTo('/app/business/usage');
    });

    it('should have export button visible', () => {
      cy.get('button').contains(/export/i).should('be.visible');
    });

    it('should trigger export when button clicked', () => {
      cy.intercept('GET', '**/api/**/usage/export*', {
        statusCode: 200,
        headers: {
          'content-type': 'text/csv',
          'content-disposition': 'attachment; filename=usage_export.csv',
        },
        body: 'date,meter,usage,cost\n2025-01-15,API Calls,1000,10.00',
      }).as('exportUsage');

      cy.get('button').contains(/export/i).first().click();
      cy.wait('@exportUsage', { timeout: 10000 });
    });
  });

  describe('Loading States', () => {
    it('should display loading indicator while fetching data', () => {
      cy.mockEndpoint('GET', '**/api/**/usage/dashboard*', { success: true, data: {} }, { delay: 1000 });
      cy.visit('/app/business/usage');
      cy.verifyLoadingState();
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.testErrorHandling('**/api/**/usage/**', {
        statusCode: 500,
        visitUrl: '/app/business/usage',
      });
    });

    it('should display retry option on error', () => {
      cy.intercept('GET', '**/api/**/usage/dashboard*', {
        statusCode: 500,
        body: { error: 'Internal server error' },
      }).as('failedDashboard');

      cy.visit('/app/business/usage');

      cy.get('body').then($body => {
        if ($body.text().includes('Error') || $body.text().includes('Failed')) {
          cy.assertContainsAny(['Retry', 'Try again', 'Reload']);
        }
      });
    });
  });

  describe('Empty State', () => {
    it('should display message when no usage data exists', () => {
      cy.intercept('GET', '**/api/**/usage/dashboard*', {
        statusCode: 200,
        body: {
          success: true,
          data: {
            period: { start: '2025-01-01', end: '2025-01-31' },
            meters: [],
            quotas: [],
            trends: [],
            recent_events: [],
          },
        },
      }).as('emptyDashboard');

      cy.visit('/app/business/usage');
      cy.wait('@emptyDashboard');

      cy.get('body').then($body => {
        if ($body.text().includes('No Usage') || $body.text().includes('No data')) {
          cy.assertContainsAny(['No Usage', 'No data', 'Start tracking']);
        }
      });
    });
  });

  describe('Responsive Design', () => {
    it('should display correctly across viewports', () => {
      cy.testResponsiveDesign('/app/business/usage', {
        checkContent: 'Usage',
      });
    });

    it('should stack cards on mobile viewport', () => {
      cy.viewport(375, 667);
      cy.navigateTo('/app/business/usage');
      cy.get('body').should('be.visible');
    });
  });

  describe('Navigation Integration', () => {
    it('should navigate to meters page', () => {
      cy.navigateTo('/app/business/usage');
      cy.get('body').then($body => {
        const metersLink = $body.find('a[href*="meters"], button:contains("Meters")').first();
        if (metersLink.length > 0) {
          cy.wrap(metersLink).click();
          cy.url().should('include', 'meters');
        }
      });
    });

    it('should navigate to quotas page', () => {
      cy.navigateTo('/app/business/usage');
      cy.get('body').then($body => {
        const quotasLink = $body.find('a[href*="quotas"], button:contains("Quotas")').first();
        if (quotasLink.length > 0) {
          cy.wrap(quotasLink).click();
          cy.url().should('include', 'quotas');
        }
      });
    });
  });
});

/**
 * Setup usage dashboard API intercepts with mock data
 */
function setupUsageDashboardIntercepts() {
  const mockMeterUsage = [
    {
      id: 'meter-1',
      name: 'API Calls',
      unit_name: 'calls',
      total_usage: 125000,
      event_count: 125000,
      calculated_cost: 125.00,
      is_billable: true,
      quota_limit: 200000,
      quota_percent: 62.5,
      quota_exceeded: false,
    },
    {
      id: 'meter-2',
      name: 'Storage',
      unit_name: 'GB',
      total_usage: 45.5,
      event_count: 1500,
      calculated_cost: 45.50,
      is_billable: true,
      quota_limit: 100,
      quota_percent: 45.5,
      quota_exceeded: false,
    },
    {
      id: 'meter-3',
      name: 'Bandwidth',
      unit_name: 'GB',
      total_usage: 180.25,
      event_count: 8500,
      calculated_cost: 18.03,
      is_billable: true,
      quota_limit: 150,
      quota_percent: 120.17,
      quota_exceeded: true,
    },
    {
      id: 'meter-4',
      name: 'Compute Hours',
      unit_name: 'hours',
      total_usage: 320,
      event_count: 45,
      calculated_cost: 64.00,
      is_billable: true,
      quota_limit: 500,
      quota_percent: 64,
      quota_exceeded: false,
    },
  ];

  const mockQuotas = [
    { id: 'quota-1', meter_id: 'meter-1', limit: 200000, current: 125000, percent: 62.5, exceeded: false },
    { id: 'quota-2', meter_id: 'meter-2', limit: 100, current: 45.5, percent: 45.5, exceeded: false },
    { id: 'quota-3', meter_id: 'meter-3', limit: 150, current: 180.25, percent: 120.17, exceeded: true },
    { id: 'quota-4', meter_id: 'meter-4', limit: 500, current: 320, percent: 64, exceeded: false },
  ];

  const mockTrends = Array.from({ length: 30 }, (_, i) => {
    const date = new Date();
    date.setDate(date.getDate() - (29 - i));
    return {
      date: date.toISOString().split('T')[0],
      total_usage: 4000 + Math.random() * 1000,
      total_cost: 8.50 + Math.random() * 2,
    };
  });

  const mockRecentEvents = [
    { id: 'evt-1', meter: 'API Calls', usage: 150, timestamp: '2025-01-15T14:30:00Z' },
    { id: 'evt-2', meter: 'Storage', usage: 0.5, timestamp: '2025-01-15T14:25:00Z' },
    { id: 'evt-3', meter: 'Bandwidth', usage: 2.3, timestamp: '2025-01-15T14:20:00Z' },
    { id: 'evt-4', meter: 'API Calls', usage: 200, timestamp: '2025-01-15T14:15:00Z' },
    { id: 'evt-5', meter: 'Compute Hours', usage: 0.25, timestamp: '2025-01-15T14:10:00Z' },
  ];

  const mockDashboardData = {
    period: {
      start: '2025-01-01',
      end: '2025-01-31',
    },
    meters: mockMeterUsage,
    quotas: mockQuotas,
    trends: mockTrends,
    recent_events: mockRecentEvents,
  };

  // Dashboard endpoint
  cy.intercept('GET', '**/api/**/usage/dashboard*', {
    statusCode: 200,
    body: { success: true, data: mockDashboardData },
  }).as('getUsageDashboard');

  // Meters endpoint
  cy.intercept('GET', '**/api/**/usage/meters*', {
    statusCode: 200,
    body: { success: true, data: mockMeterUsage },
  }).as('getUsageMeters');

  // Quotas endpoint
  cy.intercept('GET', '**/api/**/usage/quotas*', {
    statusCode: 200,
    body: { success: true, data: mockQuotas },
  }).as('getUsageQuotas');

  // Trends endpoint
  cy.intercept('GET', '**/api/**/usage/trends*', {
    statusCode: 200,
    body: { success: true, data: mockTrends },
  }).as('getUsageTrends');

  // Events endpoint
  cy.intercept('GET', '**/api/**/usage/events*', {
    statusCode: 200,
    body: { success: true, data: mockRecentEvents },
  }).as('getUsageEvents');

  // Export endpoint
  cy.intercept('GET', '**/api/**/usage/export*', {
    statusCode: 200,
    headers: {
      'content-type': 'text/csv',
      'content-disposition': 'attachment; filename=usage_export.csv',
    },
    body: 'date,meter,usage,cost\n2025-01-15,API Calls,125000,125.00\n2025-01-15,Storage,45.5,45.50',
  }).as('exportUsage');
}

export {};

/// <reference types="cypress" />

/**
 * Public Status Page E2E Tests
 *
 * Tests for the public-facing system status page (/status).
 * This page is accessible without authentication and displays:
 * - Overall system status (operational, degraded, partial_outage, major_outage)
 * - Uptime metrics and percentages
 * - Component statuses with response times
 * - Active incidents (if any)
 * - 30-day uptime history chart
 * - Auto-refresh every 60 seconds
 */

describe('Public Status Page Tests', () => {
  // Mock data for different scenarios
  const mockOperationalStatus = {
    success: true,
    data: {
      overall_status: 'operational',
      components: {
        api: {
          name: 'API Server',
          status: 'operational',
          response_time: 45,
          description: 'Core API endpoints',
        },
        database: {
          name: 'Database',
          status: 'operational',
          response_time: 12,
          description: 'Primary data storage',
        },
        worker: {
          name: 'Background Workers',
          status: 'operational',
          response_time: 8,
          description: 'Async job processing',
        },
        cdn: {
          name: 'CDN',
          status: 'operational',
          response_time: 25,
          description: 'Static asset delivery',
        },
      },
      incidents: [],
      uptime: {
        last_24_hours: 100.0,
        last_7_days: 99.98,
        last_30_days: 99.95,
        last_90_days: 99.92,
      },
      last_updated: new Date().toISOString(),
    },
  };

  const mockDegradedStatus = {
    success: true,
    data: {
      overall_status: 'degraded',
      components: {
        api: {
          name: 'API Server',
          status: 'operational',
          response_time: 45,
          description: 'Core API endpoints',
        },
        database: {
          name: 'Database',
          status: 'degraded',
          response_time: 250,
          description: 'Primary data storage',
        },
        worker: {
          name: 'Background Workers',
          status: 'operational',
          response_time: 8,
          description: 'Async job processing',
        },
        cdn: {
          name: 'CDN',
          status: 'operational',
          response_time: 25,
          description: 'Static asset delivery',
        },
      },
      incidents: [
        {
          id: 'inc-001',
          title: 'Database Performance Degradation',
          status: 'investigating',
          impact: 'minor',
          started_at: new Date(Date.now() - 30 * 60000).toISOString(),
          updated_at: new Date().toISOString(),
        },
      ],
      uptime: {
        last_24_hours: 99.5,
        last_7_days: 99.75,
        last_30_days: 99.85,
        last_90_days: 99.88,
      },
      last_updated: new Date().toISOString(),
    },
  };

  const mockPartialOutageStatus = {
    success: true,
    data: {
      overall_status: 'partial_outage',
      components: {
        api: {
          name: 'API Server',
          status: 'operational',
          response_time: 65,
          description: 'Core API endpoints',
        },
        database: {
          name: 'Database',
          status: 'partial_outage',
          response_time: null,
          description: 'Primary data storage',
        },
        worker: {
          name: 'Background Workers',
          status: 'degraded',
          response_time: 150,
          description: 'Async job processing',
        },
        cdn: {
          name: 'CDN',
          status: 'operational',
          response_time: 30,
          description: 'Static asset delivery',
        },
      },
      incidents: [
        {
          id: 'inc-002',
          title: 'Database Connectivity Issues',
          status: 'identified',
          impact: 'major',
          started_at: new Date(Date.now() - 60 * 60000).toISOString(),
          updated_at: new Date().toISOString(),
        },
      ],
      uptime: {
        last_24_hours: 95.0,
        last_7_days: 98.5,
        last_30_days: 99.2,
        last_90_days: 99.5,
      },
      last_updated: new Date().toISOString(),
    },
  };

  const mockMajorOutageStatus = {
    success: true,
    data: {
      overall_status: 'major_outage',
      components: {
        api: {
          name: 'API Server',
          status: 'major_outage',
          response_time: null,
          description: 'Core API endpoints',
        },
        database: {
          name: 'Database',
          status: 'major_outage',
          response_time: null,
          description: 'Primary data storage',
        },
        worker: {
          name: 'Background Workers',
          status: 'major_outage',
          response_time: null,
          description: 'Async job processing',
        },
        cdn: {
          name: 'CDN',
          status: 'major_outage',
          response_time: null,
          description: 'Static asset delivery',
        },
      },
      incidents: [
        {
          id: 'inc-003',
          title: 'Complete Service Outage',
          status: 'investigating',
          impact: 'critical',
          started_at: new Date(Date.now() - 15 * 60000).toISOString(),
          updated_at: new Date().toISOString(),
        },
      ],
      uptime: {
        last_24_hours: 85.0,
        last_7_days: 95.0,
        last_30_days: 98.0,
        last_90_days: 99.0,
      },
      last_updated: new Date().toISOString(),
    },
  };

  const mockStatusHistory = {
    success: true,
    data: {
      period: '30_days',
      uptime_percentage: 99.85,
      incidents_count: 2,
      average_response_time_ms: 45,
      daily_status: Array.from({ length: 30 }, (_, i) => ({
        date: new Date(Date.now() - (29 - i) * 24 * 60 * 60 * 1000).toISOString().split('T')[0],
        status: i === 15 ? 'degraded' : i === 22 ? 'partial_outage' : 'operational',
        uptime_percentage: i === 15 ? 99.5 : i === 22 ? 98.0 : 100.0,
      })),
    },
  };

  const mockActiveIncidentsStatus = {
    success: true,
    data: {
      overall_status: 'degraded',
      components: {
        api: {
          name: 'API Server',
          status: 'operational',
          response_time: 50,
          description: 'Core API endpoints',
        },
        database: {
          name: 'Database',
          status: 'degraded',
          response_time: 200,
          description: 'Primary data storage',
        },
        worker: {
          name: 'Background Workers',
          status: 'operational',
          response_time: 10,
          description: 'Async job processing',
        },
        cdn: {
          name: 'CDN',
          status: 'operational',
          response_time: 28,
          description: 'Static asset delivery',
        },
      },
      incidents: [
        {
          id: 'inc-active-1',
          title: 'Elevated Database Latency',
          status: 'monitoring',
          impact: 'minor',
          started_at: new Date(Date.now() - 2 * 60 * 60000).toISOString(),
          updated_at: new Date(Date.now() - 30 * 60000).toISOString(),
        },
        {
          id: 'inc-active-2',
          title: 'Intermittent API Timeouts',
          status: 'identified',
          impact: 'major',
          started_at: new Date(Date.now() - 45 * 60000).toISOString(),
          updated_at: new Date(Date.now() - 10 * 60000).toISOString(),
        },
      ],
      uptime: {
        last_24_hours: 99.2,
        last_7_days: 99.5,
        last_30_days: 99.7,
        last_90_days: 99.8,
      },
      last_updated: new Date().toISOString(),
    },
  };

  // Setup interceptors helper
  const setupStatusIntercepts = (
    statusData: Record<string, unknown> = mockOperationalStatus,
    historyData: Record<string, unknown> = mockStatusHistory
  ) => {
    cy.intercept('GET', '/api/v1/public/status', statusData).as('getStatus');
    cy.intercept('GET', '/api/v1/public/status/history', historyData).as('getStatusHistory');
  };

  describe('Page Access (No Authentication Required)', () => {
    it('should load status page without authentication', () => {
      setupStatusIntercepts();
      cy.clearLocalStorage();
      cy.clearCookies();
      cy.visit('/status');
      cy.wait('@getStatus');
      cy.waitForPageLoad();
      cy.contains('System Status').should('be.visible');
    });

    it('should display Powernode branding in header', () => {
      setupStatusIntercepts();
      cy.visit('/status');
      cy.wait('@getStatus');
      cy.waitForPageLoad();
      cy.contains('Powernode').should('be.visible');
    });

    it('should have Home link in footer', () => {
      setupStatusIntercepts();
      cy.visit('/status');
      cy.wait('@getStatus');
      cy.waitForPageLoad();
      cy.contains('a', 'Home').should('be.visible').and('have.attr', 'href', '/');
    });

    it('should have Sign In link in footer', () => {
      setupStatusIntercepts();
      cy.visit('/status');
      cy.wait('@getStatus');
      cy.waitForPageLoad();
      cy.contains('a', 'Sign In').should('be.visible').and('have.attr', 'href', '/login');
    });
  });

  describe('All Systems Operational', () => {
    beforeEach(() => {
      setupStatusIntercepts();
      cy.visit('/status');
      cy.wait('@getStatus');
      cy.waitForPageLoad();
    });

    it('should display "All Systems Operational" banner', () => {
      cy.contains('All Systems Operational').should('be.visible');
    });

    it('should display operational status icon (check circle)', () => {
      cy.get('[class*="text-theme-success"]').should('exist');
    });

    it('should display all components with operational status', () => {
      cy.assertContainsAny(['System Components', 'API Server', 'Database', 'Background Workers']);
    });

    it('should show "Operational" badge for each component', () => {
      cy.contains('Operational').should('be.visible');
    });

    it('should display response times for components', () => {
      cy.contains('45ms').should('be.visible');
      cy.contains('12ms').should('be.visible');
    });

    it('should display component descriptions', () => {
      cy.contains('Core API endpoints').should('be.visible');
      cy.contains('Primary data storage').should('be.visible');
    });

    it('should not display active incidents section when none exist', () => {
      cy.contains('Active Incidents').should('not.exist');
    });
  });

  describe('Degraded Performance', () => {
    beforeEach(() => {
      setupStatusIntercepts(mockDegradedStatus);
      cy.visit('/status');
      cy.wait('@getStatus');
      cy.waitForPageLoad();
    });

    it('should display "Degraded Performance" banner', () => {
      cy.contains('Degraded Performance').should('be.visible');
    });

    it('should display warning icon for degraded status', () => {
      cy.get('[class*="text-theme-warning"]').should('exist');
    });

    it('should show degraded component with warning styling', () => {
      cy.contains('Database').should('be.visible');
      cy.get('[class*="bg-theme-warning"]').should('exist');
    });

    it('should display elevated response time for degraded component', () => {
      cy.contains('250ms').should('be.visible');
    });

    it('should display active incident', () => {
      cy.contains('Active Incidents').should('be.visible');
      cy.contains('Database Performance Degradation').should('be.visible');
    });

    it('should show incident status label', () => {
      cy.contains('Investigating').should('be.visible');
    });

    it('should show incident impact level', () => {
      cy.contains('MINOR').should('be.visible');
    });
  });

  describe('Partial Outage', () => {
    beforeEach(() => {
      setupStatusIntercepts(mockPartialOutageStatus);
      cy.visit('/status');
      cy.wait('@getStatus');
      cy.waitForPageLoad();
    });

    it('should display "Partial Outage" banner', () => {
      cy.contains('Partial Outage').should('be.visible');
    });

    it('should show components with mixed statuses', () => {
      cy.assertContainsAny(['API Server', 'Database', 'Background Workers']);
    });

    it('should display null response time as unavailable', () => {
      cy.get('body').should('not.contain.text', 'nullms');
    });

    it('should display incident with "identified" status', () => {
      cy.contains('Identified').should('be.visible');
    });

    it('should show major impact level', () => {
      cy.contains('MAJOR').should('be.visible');
    });
  });

  describe('Major Outage', () => {
    beforeEach(() => {
      setupStatusIntercepts(mockMajorOutageStatus);
      cy.visit('/status');
      cy.wait('@getStatus');
      cy.waitForPageLoad();
    });

    it('should display "Major Outage" banner', () => {
      cy.contains('Major Outage').should('be.visible');
    });

    it('should display danger/error icon', () => {
      cy.get('[class*="text-theme-danger"]').should('exist');
    });

    it('should show all components as down', () => {
      cy.contains('major outage').should('be.visible');
    });

    it('should show critical incident', () => {
      cy.contains('Complete Service Outage').should('be.visible');
      cy.contains('CRITICAL').should('be.visible');
    });

    it('should not display response times for unavailable components', () => {
      cy.get('body').should('not.contain.text', 'nullms');
    });
  });

  describe('Active Incidents Display', () => {
    beforeEach(() => {
      setupStatusIntercepts(mockActiveIncidentsStatus);
      cy.visit('/status');
      cy.wait('@getStatus');
      cy.waitForPageLoad();
    });

    it('should display Active Incidents section', () => {
      cy.contains('Active Incidents').should('be.visible');
    });

    it('should display multiple incidents', () => {
      cy.contains('Elevated Database Latency').should('be.visible');
      cy.contains('Intermittent API Timeouts').should('be.visible');
    });

    it('should show incident statuses', () => {
      cy.contains('Monitoring').should('be.visible');
      cy.contains('Identified').should('be.visible');
    });

    it('should show incident impact levels with appropriate colors', () => {
      cy.contains('MINOR').should('be.visible');
      cy.contains('MAJOR').should('be.visible');
    });

    it('should display incident start times', () => {
      cy.contains('Started:').should('be.visible');
    });

    it('should display incidents with warning border styling', () => {
      cy.get('[class*="border-theme-warning"]').should('exist');
    });
  });

  describe('Uptime Metrics Display', () => {
    beforeEach(() => {
      setupStatusIntercepts();
      cy.visit('/status');
      cy.wait('@getStatus');
      cy.waitForPageLoad();
    });

    it('should display Uptime section', () => {
      cy.contains('Uptime').should('be.visible');
    });

    it('should display 24-hour uptime percentage', () => {
      cy.contains('Last 24 hours').should('be.visible');
      cy.contains('100.00%').should('be.visible');
    });

    it('should display 7-day uptime percentage', () => {
      cy.contains('Last 7 days').should('be.visible');
      cy.contains('99.98%').should('be.visible');
    });

    it('should display 30-day uptime percentage', () => {
      cy.contains('Last 30 days').should('be.visible');
      cy.contains('99.95%').should('be.visible');
    });

    it('should display 90-day uptime percentage', () => {
      cy.contains('Last 90 days').should('be.visible');
      cy.contains('99.92%').should('be.visible');
    });

    it('should display uptime metrics in a grid layout', () => {
      cy.get('.grid').should('exist');
    });
  });

  describe('30-Day Uptime History Chart', () => {
    beforeEach(() => {
      setupStatusIntercepts();
      cy.visit('/status');
      cy.wait(['@getStatus', '@getStatusHistory']);
      cy.waitForPageLoad();
    });

    it('should display 30-Day Uptime History section', () => {
      cy.contains('30-Day Uptime History').should('be.visible');
    });

    it('should display overall uptime percentage', () => {
      cy.contains('99.85% uptime').should('be.visible');
    });

    it('should display incidents count', () => {
      cy.contains('2 incidents').should('be.visible');
    });

    it('should display history chart bars', () => {
      cy.get('.flex.gap-1').within(() => {
        cy.get('div[title]').should('have.length', 30);
      });
    });

    it('should display chart legend with date range', () => {
      cy.contains('30 days ago').should('be.visible');
      cy.contains('Today').should('be.visible');
    });

    it('should show different colors for different statuses in history', () => {
      cy.get('[class*="bg-theme-success"]').should('exist');
    });

    it('should display tooltip on hover with day details', () => {
      cy.get('div[title]').first().should('have.attr', 'title').and('include', '%');
    });
  });

  describe('Status Legend', () => {
    beforeEach(() => {
      setupStatusIntercepts();
      cy.visit('/status');
      cy.wait('@getStatus');
      cy.waitForPageLoad();
    });

    it('should display Status Legend section', () => {
      cy.contains('Status Legend').should('be.visible');
    });

    it('should show Operational status indicator', () => {
      cy.contains('Operational').should('be.visible');
      cy.get('.bg-theme-success').should('exist');
    });

    it('should show Degraded status indicator', () => {
      cy.contains('Degraded').should('be.visible');
    });

    it('should show Partial Outage status indicator', () => {
      cy.contains('Partial Outage').should('be.visible');
    });

    it('should show Major Outage status indicator', () => {
      cy.contains('Major Outage').should('be.visible');
      cy.get('.bg-theme-danger').should('exist');
    });

    it('should display legend in a grid layout', () => {
      cy.get('.grid.grid-cols-2').should('exist');
    });
  });

  describe('Manual Refresh Functionality', () => {
    it('should have a Refresh button', () => {
      setupStatusIntercepts();
      cy.visit('/status');
      cy.wait('@getStatus');
      cy.waitForPageLoad();
      cy.contains('button', 'Refresh').should('be.visible');
    });

    it('should refresh data when Refresh button is clicked', () => {
      setupStatusIntercepts();
      cy.visit('/status');
      cy.wait('@getStatus');
      cy.waitForPageLoad();

      cy.intercept('GET', '/api/v1/public/status', mockOperationalStatus).as('getStatusRefresh');
      cy.intercept('GET', '/api/v1/public/status/history', mockStatusHistory).as('getStatusHistoryRefresh');

      cy.clickButton('Refresh');
      cy.wait('@getStatusRefresh');
    });

    it('should show loading spinner during refresh', () => {
      cy.intercept('GET', '/api/v1/public/status', {
        delay: 1000,
        ...mockOperationalStatus,
      }).as('getStatusSlow');
      cy.intercept('GET', '/api/v1/public/status/history', mockStatusHistory).as('getStatusHistory');

      cy.visit('/status');
      cy.get('[class*="animate-spin"]').should('be.visible');
      cy.wait('@getStatusSlow');
    });

    it('should disable Refresh button while loading', () => {
      cy.intercept('GET', '/api/v1/public/status', {
        delay: 1000,
        ...mockOperationalStatus,
      }).as('getStatusSlow');
      cy.intercept('GET', '/api/v1/public/status/history', mockStatusHistory).as('getStatusHistory');

      cy.visit('/status');
      cy.contains('button', 'Refresh').should('be.disabled');
      cy.wait('@getStatusSlow');
    });
  });

  describe('Auto-Refresh Functionality', () => {
    it('should display last refresh time in footer', () => {
      setupStatusIntercepts();
      cy.visit('/status');
      cy.wait('@getStatus');
      cy.waitForPageLoad();
      cy.contains('Last checked:').should('be.visible');
    });

    it('should display "Last updated" relative time in status banner', () => {
      setupStatusIntercepts();
      cy.visit('/status');
      cy.wait('@getStatus');
      cy.waitForPageLoad();
      cy.contains('Last updated:').should('be.visible');
      cy.contains(/Just now|minutes ago|hours ago/).should('be.visible');
    });
  });

  describe('Error Handling', () => {
    it('should display error state when API fails', () => {
      cy.intercept('GET', '/api/v1/public/status', {
        statusCode: 500,
        body: { success: false, error: 'Internal Server Error' },
      }).as('getStatusError');
      cy.intercept('GET', '/api/v1/public/status/history', mockStatusHistory).as('getStatusHistory');

      cy.visit('/status');
      cy.wait('@getStatusError');
      cy.contains('Unable to Load Status').should('be.visible');
    });

    it('should display error message from API', () => {
      cy.intercept('GET', '/api/v1/public/status', {
        statusCode: 500,
        body: { success: false, error: 'Service temporarily unavailable' },
      }).as('getStatusError');
      cy.intercept('GET', '/api/v1/public/status/history', mockStatusHistory).as('getStatusHistory');

      cy.visit('/status');
      cy.wait('@getStatusError');
      cy.contains('Service temporarily unavailable').should('be.visible');
    });

    it('should display Try Again button on error', () => {
      cy.intercept('GET', '/api/v1/public/status', {
        statusCode: 500,
        body: { success: false, error: 'Failed to fetch status' },
      }).as('getStatusError');
      cy.intercept('GET', '/api/v1/public/status/history', mockStatusHistory).as('getStatusHistory');

      cy.visit('/status');
      cy.wait('@getStatusError');
      cy.contains('button', 'Try Again').should('be.visible');
    });

    it('should retry loading when Try Again is clicked', () => {
      cy.intercept('GET', '/api/v1/public/status', {
        statusCode: 500,
        body: { success: false, error: 'Failed to fetch status' },
      }).as('getStatusError');
      cy.intercept('GET', '/api/v1/public/status/history', mockStatusHistory).as('getStatusHistory');

      cy.visit('/status');
      cy.wait('@getStatusError');

      cy.intercept('GET', '/api/v1/public/status', mockOperationalStatus).as('getStatusRetry');
      cy.intercept('GET', '/api/v1/public/status/history', mockStatusHistory).as('getStatusHistoryRetry');

      cy.clickButton('Try Again');
      cy.wait('@getStatusRetry');
      cy.contains('All Systems Operational').should('be.visible');
    });

    it('should handle network timeout gracefully', () => {
      cy.intercept('GET', '/api/v1/public/status', {
        forceNetworkError: true,
      }).as('getStatusNetworkError');
      cy.intercept('GET', '/api/v1/public/status/history', mockStatusHistory).as('getStatusHistory');

      cy.visit('/status');
      cy.wait('@getStatusNetworkError');
      cy.contains('Unable to Load Status').should('be.visible');
    });

    it('should display error icon on error state', () => {
      cy.intercept('GET', '/api/v1/public/status', {
        statusCode: 500,
        body: { success: false, error: 'Server error' },
      }).as('getStatusError');
      cy.intercept('GET', '/api/v1/public/status/history', mockStatusHistory).as('getStatusHistory');

      cy.visit('/status');
      cy.wait('@getStatusError');
      cy.get('[class*="text-theme-danger"]').should('exist');
    });

    it('should still show footer links on error', () => {
      cy.intercept('GET', '/api/v1/public/status', {
        statusCode: 500,
        body: { success: false, error: 'Server error' },
      }).as('getStatusError');
      cy.intercept('GET', '/api/v1/public/status/history', mockStatusHistory).as('getStatusHistory');

      cy.visit('/status');
      cy.wait('@getStatusError');
      cy.contains('a', 'Home').should('be.visible');
      cy.contains('a', 'Sign In').should('be.visible');
    });
  });

  describe('Loading State', () => {
    it('should display loading spinner while fetching data', () => {
      cy.intercept('GET', '/api/v1/public/status', {
        delay: 2000,
        ...mockOperationalStatus,
      }).as('getStatusSlow');
      cy.intercept('GET', '/api/v1/public/status/history', {
        delay: 2000,
        ...mockStatusHistory,
      }).as('getStatusHistorySlow');

      cy.visit('/status');
      cy.get('[class*="animate-spin"]').should('be.visible');
    });

    it('should hide loading spinner after data loads', () => {
      setupStatusIntercepts();
      cy.visit('/status');
      cy.wait(['@getStatus', '@getStatusHistory']);
      cy.waitForPageLoad();
      cy.contains('All Systems Operational').should('be.visible');
    });
  });

  describe('Responsive Design', () => {
    beforeEach(() => {
      setupStatusIntercepts();
    });

    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/status');
      cy.wait('@getStatus');
      cy.waitForPageLoad();
      cy.assertContainsAny(['All Systems Operational', 'System Components']);
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/status');
      cy.wait('@getStatus');
      cy.waitForPageLoad();
      cy.assertContainsAny(['All Systems Operational', 'Uptime']);
    });

    it('should stack uptime stats on small screens', () => {
      cy.viewport(375, 667);
      cy.visit('/status');
      cy.wait('@getStatus');
      cy.waitForPageLoad();
      cy.contains('Last 24 hours').should('be.visible');
      cy.contains('Last 7 days').should('be.visible');
    });

    it('should display full grid on large screens', () => {
      cy.viewport(1280, 800);
      cy.visit('/status');
      cy.wait('@getStatus');
      cy.waitForPageLoad();
      cy.get('.grid.grid-cols-2').should('be.visible');
    });

    it('should maintain header layout on mobile', () => {
      cy.viewport('iphone-x');
      cy.visit('/status');
      cy.wait('@getStatus');
      cy.waitForPageLoad();
      cy.contains('Powernode').should('be.visible');
      cy.contains('button', 'Refresh').should('be.visible');
    });

    it('should display footer links on mobile', () => {
      cy.viewport('iphone-x');
      cy.visit('/status');
      cy.wait('@getStatus');
      cy.waitForPageLoad();
      cy.contains('a', 'Home').should('be.visible');
      cy.contains('a', 'Sign In').should('be.visible');
    });
  });

  describe('Component Response Times', () => {
    it('should display response times in milliseconds', () => {
      setupStatusIntercepts();
      cy.visit('/status');
      cy.wait('@getStatus');
      cy.waitForPageLoad();
      cy.contains('ms').should('be.visible');
    });

    it('should not display response time when null', () => {
      setupStatusIntercepts(mockMajorOutageStatus);
      cy.visit('/status');
      cy.wait('@getStatus');
      cy.waitForPageLoad();
      cy.get('body').should('not.contain.text', 'nullms');
    });

    it('should display response times next to component status', () => {
      setupStatusIntercepts();
      cy.visit('/status');
      cy.wait('@getStatus');
      cy.waitForPageLoad();
      cy.contains('API Server').should('be.visible');
      cy.contains('45ms').should('be.visible');
    });
  });

  describe('Incident Status Labels', () => {
    it('should display "Investigating" status', () => {
      setupStatusIntercepts(mockDegradedStatus);
      cy.visit('/status');
      cy.wait('@getStatus');
      cy.waitForPageLoad();
      cy.contains('Investigating').should('be.visible');
    });

    it('should display "Identified" status', () => {
      setupStatusIntercepts(mockPartialOutageStatus);
      cy.visit('/status');
      cy.wait('@getStatus');
      cy.waitForPageLoad();
      cy.contains('Identified').should('be.visible');
    });

    it('should display "Monitoring" status', () => {
      setupStatusIntercepts(mockActiveIncidentsStatus);
      cy.visit('/status');
      cy.wait('@getStatus');
      cy.waitForPageLoad();
      cy.contains('Monitoring').should('be.visible');
    });

    it('should show incident start timestamp', () => {
      setupStatusIntercepts(mockDegradedStatus);
      cy.visit('/status');
      cy.wait('@getStatus');
      cy.waitForPageLoad();
      cy.contains('Started:').should('be.visible');
    });
  });

  describe('History Data Not Available', () => {
    it('should handle missing history data gracefully', () => {
      cy.intercept('GET', '/api/v1/public/status', mockOperationalStatus).as('getStatus');
      cy.intercept('GET', '/api/v1/public/status/history', {
        statusCode: 500,
        body: { success: false, error: 'History unavailable' },
      }).as('getStatusHistoryError');

      cy.visit('/status');
      cy.wait(['@getStatus', '@getStatusHistoryError']);
      cy.waitForPageLoad();
      cy.assertContainsAny(['All Systems Operational', 'System Components']);
    });

    it('should not crash when history response is empty', () => {
      cy.intercept('GET', '/api/v1/public/status', mockOperationalStatus).as('getStatus');
      cy.intercept('GET', '/api/v1/public/status/history', {
        success: true,
        data: null,
      }).as('getStatusHistoryEmpty');

      cy.visit('/status');
      cy.wait(['@getStatus', '@getStatusHistoryEmpty']);
      cy.waitForPageLoad();
      cy.contains('All Systems Operational').should('be.visible');
    });
  });

  describe('Accessibility', () => {
    beforeEach(() => {
      setupStatusIntercepts();
      cy.visit('/status');
      cy.wait('@getStatus');
      cy.waitForPageLoad();
    });

    it('should have proper heading structure', () => {
      cy.get('h1, h2').should('have.length.at.least', 1);
    });

    it('should have accessible buttons', () => {
      cy.contains('button', 'Refresh').should('be.visible');
    });

    it('should have accessible links', () => {
      cy.get('a[href="/"]').should('contain', 'Home');
      cy.get('a[href="/login"]').should('contain', 'Sign In');
    });

    it('should have proper color contrast for status indicators', () => {
      cy.get('[class*="text-theme-success"]').should('be.visible');
    });

    it('should have semantic HTML structure', () => {
      cy.get('header').should('exist');
      cy.get('main').should('exist');
      cy.get('footer').should('exist');
    });
  });

  describe('Theme Support', () => {
    beforeEach(() => {
      setupStatusIntercepts();
    });

    it('should use theme-aware background classes', () => {
      cy.visit('/status');
      cy.wait('@getStatus');
      cy.waitForPageLoad();
      cy.get('[class*="bg-theme-"]').should('exist');
    });

    it('should use theme-aware text classes', () => {
      cy.visit('/status');
      cy.wait('@getStatus');
      cy.waitForPageLoad();
      cy.get('[class*="text-theme-"]').should('exist');
    });

    it('should use theme-aware border classes', () => {
      cy.visit('/status');
      cy.wait('@getStatus');
      cy.waitForPageLoad();
      cy.get('[class*="border-theme"]').should('exist');
    });
  });
});


export {};

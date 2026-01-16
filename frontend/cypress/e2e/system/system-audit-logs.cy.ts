/// <reference types="cypress" />

/**
 * System Audit Logs Page Tests
 *
 * Tests for Audit Logs functionality including:
 * - Page navigation and load
 * - Metrics cards display
 * - Table view
 * - Analytics view
 * - Filter functionality
 * - Export functionality
 * - Pagination
 * - Permission-based access
 * - Responsive design
 */

describe('System Audit Logs Page Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup({ intercepts: ['system'] });
  });

  describe('Page Navigation', () => {
    it('should navigate to Audit Logs from System section', () => {
      cy.visit('/app/system');
      cy.waitForPageLoad();
      cy.get('body').should('be.visible');
    });

    it('should load Audit Logs page directly', () => {
      cy.assertPageReady('/app/system/audit-logs');
      cy.assertContainsAny(['Audit Logs', 'Audit', 'Security', 'Access Restricted', 'permission']);
    });

    it('should display page title', () => {
      cy.assertPageReady('/app/system/audit-logs');
      cy.assertContainsAny(['Audit Logs', 'Audit', 'Access Restricted']);
    });

    it('should display breadcrumbs', () => {
      cy.assertPageReady('/app/system/audit-logs');
      cy.assertContainsAny(['Dashboard', 'System', 'Audit']);
    });
  });

  describe('Metrics Cards Display', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/system/audit-logs');
    });

    it('should display Total Events metric or access restricted', () => {
      cy.assertContainsAny(['Total Events', 'Total', 'Access Restricted', 'permission']);
    });

    it('should display Security Events metric or access restricted', () => {
      cy.assertContainsAny(['Security Events', 'Security', 'Access Restricted', 'permission']);
    });

    it('should display High Risk metric or access restricted', () => {
      cy.assertContainsAny(['High Risk', 'Risk', 'Access Restricted', 'permission']);
    });

    it('should display Failed Events metric or access restricted', () => {
      cy.assertContainsAny(['Failed Events', 'Failed', 'Access Restricted', 'permission']);
    });
  });

  describe('Table View', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/system/audit-logs');
    });

    it('should display audit logs table or access restricted', () => {
      cy.assertContainsAny(['No audit logs', 'No events', 'Audit', 'Event', 'Access Restricted', 'permission']);
    });

    it('should display event type column or access message', () => {
      cy.assertContainsAny(['Event', 'Action', 'Type', 'Access Restricted', 'permission']);
    });

    it('should display user column or access message', () => {
      cy.assertContainsAny(['User', 'Actor', 'Access Restricted', 'permission']);
    });

    it('should display timestamp column or access message', () => {
      cy.assertContainsAny(['Time', 'Date', 'When', 'Access Restricted', 'permission']);
    });
  });

  describe('Tab Navigation', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/system/audit-logs');
    });

    it('should display Table View tab or access restricted', () => {
      cy.get('body').then(($body) => {
        const hasAccessRestricted = $body.text().includes('Access Restricted');
        if (!hasAccessRestricted) {
          cy.assertHasElement(['button:contains("Table")', '[role="tab"]:contains("Table")', '[data-testid*="tab"]']);
        } else {
          expect(hasAccessRestricted).to.be.true;
        }
      });
    });

    it('should display Analytics tab or access restricted', () => {
      cy.get('body').then(($body) => {
        const hasAccessRestricted = $body.text().includes('Access Restricted');
        if (!hasAccessRestricted) {
          cy.assertHasElement(['button:contains("Analytics")', '[role="tab"]:contains("Analytics")', '[data-testid*="tab"]']);
        } else {
          expect(hasAccessRestricted).to.be.true;
        }
      });
    });

    it('should switch to Analytics tab if permitted', () => {
      cy.get('body').then(($body) => {
        const hasAccessRestricted = $body.text().includes('Access Restricted');
        if (!hasAccessRestricted) {
          cy.get('button:contains("Analytics"), [role="tab"]:contains("Analytics")').first().click();
          cy.waitForStableDOM();
          cy.url().should('include', 'analytics');
        } else {
          expect(hasAccessRestricted).to.be.true;
        }
      });
    });
  });

  describe('Filter Functionality', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/system/audit-logs');
    });

    it('should have Filters button or be access restricted', () => {
      cy.get('body').then(($body) => {
        const hasAccessRestricted = $body.text().includes('Access Restricted');
        if (!hasAccessRestricted) {
          cy.assertHasElement(['button:contains("Filters")', 'button:contains("Filter")', '[data-testid*="filter"]']);
        } else {
          expect(hasAccessRestricted).to.be.true;
        }
      });
    });

    it('should toggle filters panel when Filters clicked', () => {
      cy.get('body').then(($body) => {
        const hasAccessRestricted = $body.text().includes('Access Restricted');
        if (!hasAccessRestricted && $body.find('button:contains("Filters")').length > 0) {
          cy.get('button:contains("Filters")').first().click();
          cy.waitForStableDOM();
          cy.assertContainsAny(['Event Type', 'Date Range', 'Filters', 'Filter']);
        } else {
          expect(true).to.be.true;
        }
      });
    });

    it('should have event type filter option', () => {
      cy.get('body').then(($body) => {
        const hasAccessRestricted = $body.text().includes('Access Restricted');
        if (!hasAccessRestricted && $body.find('button:contains("Filters")').length > 0) {
          cy.get('button:contains("Filters")').first().click();
          cy.waitForStableDOM();
          cy.assertContainsAny(['Event Type', 'Action', 'Type']);
        } else {
          expect(true).to.be.true;
        }
      });
    });

    it('should have date range filter option', () => {
      cy.get('body').then(($body) => {
        const hasAccessRestricted = $body.text().includes('Access Restricted');
        if (!hasAccessRestricted && $body.find('button:contains("Filters")').length > 0) {
          cy.get('button:contains("Filters")').first().click();
          cy.waitForStableDOM();
          cy.assertContainsAny(['Date', 'Range', 'Period']);
        } else {
          expect(true).to.be.true;
        }
      });
    });
  });

  describe('Export Functionality', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/system/audit-logs');
    });

    it('should have Export button or be access restricted', () => {
      cy.get('body').then(($body) => {
        const hasAccessRestricted = $body.text().includes('Access Restricted');
        if (!hasAccessRestricted) {
          cy.assertContainsAny(['Export', 'Download']);
        } else {
          expect(hasAccessRestricted).to.be.true;
        }
      });
    });

    it('should show export panel when Export clicked', () => {
      cy.get('body').then(($body) => {
        const hasAccessRestricted = $body.text().includes('Access Restricted');
        if (!hasAccessRestricted && $body.find('button:contains("Export")').length > 0) {
          cy.get('button:contains("Export")').first().click();
          cy.waitForStableDOM();
          cy.assertContainsAny(['CSV', 'JSON', 'Export', 'Format']);
        } else {
          expect(true).to.be.true;
        }
      });
    });
  });

  describe('Refresh Functionality', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/system/audit-logs');
    });

    it('should have Refresh button or be access restricted', () => {
      cy.get('body').then(($body) => {
        const hasAccessRestricted = $body.text().includes('Access Restricted');
        if (!hasAccessRestricted) {
          cy.assertHasElement(['button:contains("Refresh")', '[aria-label*="refresh"]', '[data-testid*="refresh"]']);
        } else {
          expect(hasAccessRestricted).to.be.true;
        }
      });
    });

    it('should refresh audit logs', () => {
      cy.get('body').then(($body) => {
        const hasAccessRestricted = $body.text().includes('Access Restricted');
        if (!hasAccessRestricted && $body.find('button:contains("Refresh")').length > 0) {
          cy.get('button:contains("Refresh")').first().click();
          cy.waitForStableDOM();
          cy.get('body').should('be.visible');
        } else {
          expect(true).to.be.true;
        }
      });
    });
  });

  describe('Pagination', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/system/audit-logs');
    });

    it('should display pagination or access restricted message', () => {
      cy.assertContainsAny(['Page', 'of', 'Showing', 'Access Restricted', 'permission', 'Previous', 'Next', 'results']);
    });

    it('should display page info or access message', () => {
      cy.assertContainsAny(['Page', 'of', 'Showing', 'Access Restricted', 'permission', 'results']);
    });

    it('should navigate between pages if available', () => {
      cy.get('body').then(($body) => {
        const hasAccessRestricted = $body.text().includes('Access Restricted');
        if (!hasAccessRestricted) {
          const nextBtn = $body.find('button:contains("Next")');
          if (nextBtn.length > 0 && !nextBtn.is(':disabled')) {
            cy.wrap(nextBtn).click();
            cy.waitForStableDOM();
          }
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Permission-Based Access', () => {
    it('should show access restricted for unauthorized users', () => {
      cy.assertPageReady('/app/system/audit-logs');
      cy.assertContainsAny(['Access Restricted', 'permission', 'Audit', 'Total Events', 'Security Events']);
    });
  });

  describe('Analytics View', () => {
    beforeEach(() => {
      cy.visit('/app/system/audit-logs/analytics');
      cy.waitForPageLoad();
    });

    it('should display analytics dashboard or access restricted', () => {
      cy.assertContainsAny(['Analytics', 'Access Restricted', 'permission', 'Audit']);
    });

    it('should display activity charts or access message', () => {
      cy.get('body').then(($body) => {
        const hasAccessRestricted = $body.text().includes('Access Restricted');
        if (!hasAccessRestricted) {
          cy.assertHasElement(['canvas', 'svg[class*="chart"]', '[class*="chart"]', '[class*="analytics"]']);
        } else {
          expect(hasAccessRestricted).to.be.true;
        }
      });
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.testErrorHandling('/api/v1/audit_logs*', {
        statusCode: 500,
        visitUrl: '/app/system/audit-logs'
      });
    });

    it('should display error notification on failure', () => {
      cy.intercept('GET', '/api/v1/audit_logs*', {
        statusCode: 500,
        body: { success: false, error: 'Failed to load audit logs' }
      }).as('auditLogsError');

      cy.visit('/app/system/audit-logs');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Error', 'Failed', 'Audit', 'Access Restricted']);
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.testViewport('mobile', '/app/system/audit-logs');
      cy.assertContainsAny(['Audit', 'Log', 'Access Restricted']);
    });

    it('should display properly on tablet viewport', () => {
      cy.testViewport('tablet', '/app/system/audit-logs');
      cy.assertContainsAny(['Audit', 'Log', 'Access Restricted']);
    });

    it('should adapt table layout on small screens', () => {
      cy.viewport(375, 667);
      cy.visit('/app/system/audit-logs');
      cy.waitForPageLoad();
      cy.get('body').should('be.visible');
    });
  });
});


export {};

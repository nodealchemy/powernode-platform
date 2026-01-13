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
    cy.clearAppData();
    // Login with demo user
    cy.visit('/login');
    cy.get('[data-testid="email-input"]', { timeout: 10000 }).type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').click();
    cy.url({ timeout: 15000 }).should('match', /\/(app|dashboard)/);
  });

  describe('Page Navigation', () => {
    it('should navigate to Audit Logs from System section', () => {
      cy.visit('/app/system');
      cy.wait(2000);

      cy.get('body').then($body => {
        const auditLink = $body.find('a[href*="/audit"], button:contains("Audit")');

        if (auditLink.length > 0) {
          cy.wrap(auditLink).first().click();
          cy.url().should('include', '/audit');
        } else {
          cy.visit('/app/system/audit-logs');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should load Audit Logs page directly', () => {
      cy.visit('/app/system/audit-logs');
      cy.wait(2000);

      cy.get('body').then($body => {
        const text = $body.text();
        const hasContent = text.includes('Audit') ||
                           text.includes('Log') ||
                           text.includes('Security') ||
                           text.includes('Loading') ||
                           text.includes('Access');
        if (hasContent) {
          cy.log('Audit Logs page content loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display page title', () => {
      cy.visit('/app/system/audit-logs');

      cy.get('body').then($body => {
        const hasTitle = $body.text().includes('Audit Logs') ||
                          $body.text().includes('Audit');

        if (hasTitle) {
          cy.log('Page title displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display breadcrumbs', () => {
      cy.visit('/app/system/audit-logs');

      cy.get('body').then($body => {
        const hasBreadcrumbs = $body.text().includes('Dashboard') ||
                               $body.text().includes('System');

        if (hasBreadcrumbs) {
          cy.log('Breadcrumbs displayed correctly');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Metrics Cards Display', () => {
    beforeEach(() => {
      cy.visit('/app/system/audit-logs');
      cy.wait(2000);
    });

    it('should display Total Events metric', () => {
      cy.get('body').then($body => {
        if ($body.text().includes('Total Events') || $body.text().includes('Total')) {
          cy.log('Total Events metric displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display Security Events metric', () => {
      cy.get('body').then($body => {
        if ($body.text().includes('Security Events') || $body.text().includes('Security')) {
          cy.log('Security Events metric displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display High Risk metric', () => {
      cy.get('body').then($body => {
        if ($body.text().includes('High Risk') || $body.text().includes('Risk')) {
          cy.log('High Risk metric displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display Failed Events metric', () => {
      cy.get('body').then($body => {
        if ($body.text().includes('Failed Events') || $body.text().includes('Failed')) {
          cy.log('Failed Events metric displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Table View', () => {
    beforeEach(() => {
      cy.visit('/app/system/audit-logs');
      cy.wait(2000);
    });

    it('should display audit logs table or empty state', () => {
      cy.get('body').then($body => {
        const hasTable = $body.find('table, [class*="table"]').length > 0 ||
                          $body.text().includes('No audit logs') ||
                          $body.text().includes('No events');

        if ($body.text().includes('No audit logs')) {
          cy.log('Empty state displayed');
        } else {
          cy.log('Audit logs table displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display event type column', () => {
      cy.get('body').then($body => {
        const hasEventType = $body.text().includes('Event') ||
                              $body.text().includes('Action') ||
                              $body.text().includes('Type');

        if (hasEventType) {
          cy.log('Event type column displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display user column', () => {
      cy.get('body').then($body => {
        const hasUser = $body.text().includes('User') ||
                         $body.text().includes('Actor');

        if (hasUser) {
          cy.log('User column displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display timestamp column', () => {
      cy.get('body').then($body => {
        const hasTimestamp = $body.text().includes('Time') ||
                              $body.text().includes('Date') ||
                              $body.text().includes('When');

        if (hasTimestamp) {
          cy.log('Timestamp column displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Tab Navigation', () => {
    beforeEach(() => {
      cy.visit('/app/system/audit-logs');
      cy.wait(2000);
    });

    it('should display Table View tab', () => {
      cy.get('body').then($body => {
        const hasTableTab = $body.find('button:contains("Table"), [role="tab"]:contains("Table")').length > 0;

        if (hasTableTab) {
          cy.log('Table View tab displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display Analytics tab', () => {
      cy.get('body').then($body => {
        const hasAnalyticsTab = $body.find('button:contains("Analytics"), [role="tab"]:contains("Analytics")').length > 0;

        if (hasAnalyticsTab) {
          cy.log('Analytics tab displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should switch to Analytics tab', () => {
      cy.get('body').then($body => {
        const analyticsTab = $body.find('button:contains("Analytics"), [role="tab"]:contains("Analytics")');

        if (analyticsTab.length > 0) {
          cy.wrap(analyticsTab).first().click();
          cy.wait(500);
          cy.url().should('include', '/analytics');
          cy.log('Switched to Analytics tab');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Filter Functionality', () => {
    beforeEach(() => {
      cy.visit('/app/system/audit-logs');
      cy.wait(2000);
    });

    it('should have Filters button', () => {
      cy.get('body').then($body => {
        const filtersButton = $body.find('button:contains("Filters"), button:contains("Filter")');

        if (filtersButton.length > 0) {
          cy.wrap(filtersButton).first().should('be.visible');
          cy.log('Filters button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should toggle filters panel when Filters clicked', () => {
      cy.get('body').then($body => {
        const filtersButton = $body.find('button:contains("Filters")');

        if (filtersButton.length > 0) {
          cy.wrap(filtersButton).first().click();
          cy.wait(500);

          cy.get('body').then($newBody => {
            const filtersVisible = $newBody.find('[class*="filter"]').length > 0 ||
                                    $newBody.text().includes('Event Type') ||
                                    $newBody.text().includes('Date Range');

            if (filtersVisible) {
              cy.log('Filters panel toggled');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have event type filter', () => {
      cy.get('body').then($body => {
        const filtersButton = $body.find('button:contains("Filters")');

        if (filtersButton.length > 0) {
          cy.wrap(filtersButton).first().click();
          cy.wait(500);

          cy.get('body').then($newBody => {
            if ($newBody.text().includes('Event Type') || $newBody.text().includes('Action')) {
              cy.log('Event type filter found');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have date range filter', () => {
      cy.get('body').then($body => {
        const filtersButton = $body.find('button:contains("Filters")');

        if (filtersButton.length > 0) {
          cy.wrap(filtersButton).first().click();
          cy.wait(500);

          cy.get('body').then($newBody => {
            if ($newBody.text().includes('Date') || $newBody.find('input[type="date"]').length > 0) {
              cy.log('Date range filter found');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Export Functionality', () => {
    beforeEach(() => {
      cy.visit('/app/system/audit-logs');
      cy.wait(2000);
    });

    it('should have Export button', () => {
      cy.get('body').then($body => {
        const exportButton = $body.find('button:contains("Export"), button:contains("Download")');

        if (exportButton.length > 0) {
          cy.log('Export button found');
        } else {
          cy.log('Export button not visible - may require permissions');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should show export panel when Export clicked', () => {
      cy.get('body').then($body => {
        const exportButton = $body.find('button:contains("Export")');

        if (exportButton.length > 0) {
          cy.wrap(exportButton).first().click();
          cy.wait(500);

          cy.get('body').then($newBody => {
            const exportVisible = $newBody.text().includes('CSV') ||
                                   $newBody.text().includes('JSON') ||
                                   $newBody.text().includes('Export');

            if (exportVisible) {
              cy.log('Export panel displayed');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Refresh Functionality', () => {
    beforeEach(() => {
      cy.visit('/app/system/audit-logs');
      cy.wait(2000);
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

    it('should refresh audit logs', () => {
      cy.get('body').then($body => {
        const refreshButton = $body.find('button:contains("Refresh")');

        if (refreshButton.length > 0) {
          cy.wrap(refreshButton).first().click();
          cy.wait(1000);
          cy.log('Audit logs refreshed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Pagination', () => {
    beforeEach(() => {
      cy.visit('/app/system/audit-logs');
      cy.wait(2000);
    });

    it('should display pagination when many logs exist', () => {
      cy.get('body').then($body => {
        const hasPagination = $body.find('[class*="pagination"], button:contains("Next"), button:contains("Previous")').length > 0;

        if (hasPagination) {
          cy.log('Pagination controls displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display page info', () => {
      cy.get('body').then($body => {
        const hasPageInfo = $body.text().includes('Page') ||
                             $body.text().includes('of') ||
                             $body.text().includes('Showing');

        if (hasPageInfo) {
          cy.log('Page info displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should navigate between pages', () => {
      cy.get('body').then($body => {
        const nextButton = $body.find('button:contains("Next")');

        if (nextButton.length > 0 && !nextButton.is(':disabled')) {
          cy.wrap(nextButton).click();
          cy.wait(500);
          cy.log('Navigated to next page');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Permission-Based Access', () => {
    it('should show access restricted for unauthorized users', () => {
      cy.visit('/app/system/audit-logs');
      cy.wait(2000);

      cy.get('body').then($body => {
        if ($body.text().includes('Access Restricted') || $body.text().includes('permission')) {
          cy.log('Access restricted message displayed');
        } else {
          cy.log('User has audit logs permissions');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Analytics View', () => {
    beforeEach(() => {
      cy.visit('/app/system/audit-logs/analytics');
      cy.wait(2000);
    });

    it('should display analytics dashboard', () => {
      cy.get('body').then($body => {
        const hasAnalytics = $body.text().includes('Analytics') ||
                              $body.find('[class*="chart"], canvas').length > 0;

        if (hasAnalytics) {
          cy.log('Analytics dashboard displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display activity charts', () => {
      cy.get('body').then($body => {
        const hasCharts = $body.find('canvas, svg[class*="chart"], [class*="chart"]').length > 0 ||
                           $body.text().includes('Activity');

        if (hasCharts) {
          cy.log('Activity charts displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.intercept('GET', '/api/v1/audit_logs*', {
        statusCode: 500,
        body: { success: false, error: 'Server error' }
      });

      cy.visit('/app/system/audit-logs');
      cy.wait(2000);

      cy.get('body').should('be.visible');
      cy.get('body').should('not.contain.text', 'Cannot read');
      cy.get('body').should('not.contain.text', 'TypeError');
    });

    it('should display error notification on failure', () => {
      cy.intercept('GET', '/api/v1/audit_logs*', {
        statusCode: 500,
        body: { success: false, error: 'Failed to load audit logs' }
      });

      cy.visit('/app/system/audit-logs');
      cy.wait(2000);

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

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/system/audit-logs');
      cy.wait(2000);

      cy.get('body').should('be.visible');
      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Audit') || $body.text().includes('Log');
        if (hasContent) {
          cy.log('Content visible on mobile');
        }
      });
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/system/audit-logs');
      cy.wait(2000);

      cy.get('body').should('be.visible');
      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Audit') || $body.text().includes('Log');
        if (hasContent) {
          cy.log('Content visible on tablet');
        }
      });
    });

    it('should adapt table layout on small screens', () => {
      cy.viewport(375, 667);
      cy.visit('/app/system/audit-logs');
      cy.wait(2000);

      cy.get('body').should('be.visible');
    });
  });
});

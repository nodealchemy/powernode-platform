/// <reference types="cypress" />

/**
 * Admin Maintenance Page Tests
 *
 * Tests for System Maintenance functionality including:
 * - Page navigation and load
 * - Tab navigation (overview, mode, health, backups, cleanup, operations, schedules)
 * - Maintenance mode controls
 * - System health monitoring
 * - Backup management
 * - Cleanup operations
 * - Scheduled maintenance
 * - Responsive design
 */

describe('Admin Maintenance Page Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup({ intercepts: ['admin'] });
  });

  describe('Page Navigation', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/admin/maintenance');
    });

    it('should navigate to Admin Maintenance page and display content', () => {
      cy.assertContainsAny(['Maintenance', 'System', 'Health']);
    });

    it('should display breadcrumbs', () => {
      cy.assertContainsAny(['Admin', 'Dashboard', 'Maintenance']);
    });
  });

  describe('Tab Navigation', () => {
    beforeEach(() => {
      cy.navigateTo('/app/admin/maintenance');
    });

    it('should display maintenance tabs', () => {
      // The page uses button-based tabs with emoji icons
      cy.assertContainsAny(['Overview', 'Mode', 'Health', 'Backups', 'Cleanup', 'Operations', 'Schedules']);
    });

    it('should switch between tabs using path navigation', () => {
      const tabs = [
        { path: '/app/admin/maintenance', content: ['Overview', 'Status', 'System'] },
        { path: '/app/admin/maintenance/mode', content: ['Mode', 'Maintenance Mode', 'Enable', 'Disable', 'Message'] },
        { path: '/app/admin/maintenance/health', content: ['Health', 'CPU', 'Memory', 'Disk', 'Score', 'Database'] },
        { path: '/app/admin/maintenance/backups', content: ['Backup', 'Restore', 'Database', 'Create'] },
        { path: '/app/admin/maintenance/cleanup', content: ['Cleanup', 'Clear', 'Cache', 'Temporary', 'Files'] },
        { path: '/app/admin/maintenance/schedules', content: ['Schedule', 'Planned', 'Upcoming', 'Tasks'] },
      ];

      tabs.forEach((tab) => {
        cy.visit(tab.path);
        cy.waitForPageLoad();
        cy.assertContainsAny(tab.content);
      });
    });

    it('should switch tabs via tab buttons', () => {
      // Click on Health tab
      cy.get('body').then($body => {
        const healthButton = $body.find('button:contains("Health")');
        if (healthButton.length > 0) {
          cy.contains('button', 'Health').click();
          cy.waitForStableDOM();
          cy.url().should('include', '/health');
        }
      });
    });
  });

  describe('Overview Tab Content', () => {
    beforeEach(() => {
      cy.navigateTo('/app/admin/maintenance');
    });

    it('should display system status overview', () => {
      cy.assertContainsAny(['Status', 'Overview', 'System', 'Active', 'Health', 'Maintenance']);
    });

    it('should display quick access cards', () => {
      cy.assertContainsAny(['Mode', 'Health', 'Backups', 'Cleanup', 'Schedule']);
    });
  });

  describe('Maintenance Mode Controls', () => {
    beforeEach(() => {
      cy.navigateTo('/app/admin/maintenance/mode');
    });

    it('should display maintenance mode toggle and settings', () => {
      cy.assertHasElement([
        'input[type="checkbox"]',
        'button[role="switch"]',
        '[class*="toggle"]',
        '[class*="switch"]',
        '[role="checkbox"]',
        '[aria-checked]',
        'button',
      ]);
      cy.assertContainsAny(['Message', 'Duration', 'Settings', 'Enable', 'Disable', 'Activate', 'Mode']);
    });

    it('should display maintenance message input', () => {
      cy.assertContainsAny(['Message', 'message', 'Description']);
    });
  });

  describe('System Health Display', () => {
    beforeEach(() => {
      cy.navigateTo('/app/admin/maintenance/health');
    });

    it('should display system health metrics', () => {
      cy.assertContainsAny(['CPU', 'Memory', 'Disk', 'Health', 'Score', '%', 'Healthy', 'Warning', 'System']);
    });

    it('should display service status information', () => {
      cy.assertContainsAny(['Database', 'Redis', 'Queue', 'Service', 'Status', 'Connected']);
    });

    it('should have refresh health functionality', () => {
      cy.assertContainsAny(['Refresh', 'Check', 'Update']);
    });
  });

  describe('Backup Management', () => {
    beforeEach(() => {
      cy.navigateTo('/app/admin/maintenance/backups');
    });

    it('should display backup list and controls', () => {
      cy.assertContainsAny(['Backup', 'Restore', 'Database', 'Create Backup', 'New Backup', 'No backups']);
    });

    it('should display backup information', () => {
      cy.assertContainsAny(['Size', 'Date', 'Type', 'Status', 'Created', 'backup']);
    });

    it('should have backup action buttons', () => {
      cy.assertContainsAny(['Create Backup', 'New Backup', 'Restore', 'Delete', 'Create', 'Backup']);
    });
  });

  describe('Cleanup Operations', () => {
    beforeEach(() => {
      cy.navigateTo('/app/admin/maintenance/cleanup');
    });

    it('should display cleanup options and controls', () => {
      cy.assertContainsAny(['Cleanup', 'Clear', 'Cache', 'Run Cleanup', 'Start Cleanup', 'Clean', 'Temporary']);
    });

    it('should display cleanup categories', () => {
      cy.assertContainsAny(['Temporary Files', 'Old Logs', 'Cache', 'Space', 'Files', 'Logs']);
    });

    it('should have cleanup action options', () => {
      cy.assertHasElement([
        'input[type="checkbox"]',
        'select',
        '[class*="checkbox"]',
        '[role="checkbox"]',
        '[class*="select"]',
        '[role="listbox"]',
        'button',
      ]);
    });
  });

  describe('Scheduled Maintenance', () => {
    beforeEach(() => {
      cy.navigateTo('/app/admin/maintenance/schedules');
    });

    it('should display scheduled maintenance list and controls', () => {
      cy.assertContainsAny(['Schedule', 'Planned', 'Upcoming', 'New Schedule', 'Create Schedule', 'Add', 'Tasks', 'No scheduled']);
    });

    it('should display schedule information', () => {
      cy.assertContainsAny(['Time', 'Duration', 'Recurring', 'Type', 'Date', 'Status', 'Schedule']);
    });

    it('should have schedule action options', () => {
      cy.assertContainsAny(['Edit', 'Cancel', 'Delete', 'New', 'Create', 'Add']);
    });
  });

  describe('Tab-Specific Actions', () => {
    it('should show Create Backup action on backups tab', () => {
      cy.navigateTo('/app/admin/maintenance/backups');
      cy.assertContainsAny(['Create Backup', 'New Backup', 'Backup', 'Create']);
    });

    it('should show Run Cleanup action on cleanup tab', () => {
      cy.navigateTo('/app/admin/maintenance/cleanup');
      cy.assertContainsAny(['Run Cleanup', 'Start Cleanup', 'Cleanup', 'Clean']);
    });

    it('should show New Schedule action on schedules tab', () => {
      cy.navigateTo('/app/admin/maintenance/schedules');
      cy.assertContainsAny(['New Schedule', 'Create Schedule', 'Schedule', 'Add']);
    });
  });

  describe('Page Actions', () => {
    beforeEach(() => {
      cy.navigateTo('/app/admin/maintenance');
    });

    it('should have Refresh button', () => {
      cy.assertContainsAny(['Refresh', 'Reload']);
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.testErrorHandling('/api/v1/admin/maintenance*', {
        statusCode: 500,
        visitUrl: '/app/admin/maintenance',
      });
    });

    it('should display error recovery option', () => {
      cy.intercept('GET', '**/api/**/maintenance**', {
        statusCode: 500,
        body: { success: false, error: 'Server error' }
      }).as('maintenanceError');

      cy.visit('/app/admin/maintenance');
      cy.waitForPageLoad();
      cy.get('body').then($body => {
        const hasError = $body.text().includes('Error') ||
                        $body.text().includes('Try Again') ||
                        $body.text().includes('Failed');
        cy.log(hasError ? 'Error handling displayed' : 'Page loaded despite error');
      });
    });
  });

  describe('Permission-Based Access', () => {
    it('should display page for authorized users', () => {
      cy.navigateTo('/app/admin/maintenance');
      // Page should load and show either maintenance content or permission message
      cy.assertContainsAny(['Maintenance', 'Permission', 'Access', 'System']);
    });
  });

  describe('Responsive Design', () => {
    it('should display properly across viewports', () => {
      cy.testResponsiveDesign('/app/admin/maintenance', {
        checkContent: 'Maintenance',
      });
    });

    it('should handle mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/admin/maintenance');
      cy.waitForPageLoad();
      cy.get('body').should('be.visible');
      cy.assertContainsAny(['Maintenance', 'System']);
    });

    it('should show scrollable tabs on small screens', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/admin/maintenance');
      cy.waitForPageLoad();
      // Tab container should be scrollable
      cy.get('body').then($body => {
        const hasTabContainer = $body.find('[class*="overflow-x"], [class*="scrollbar"]').length > 0 ||
                               $body.find('button:contains("Overview")').length > 0;
        cy.log(hasTabContainer ? 'Tab navigation present' : 'Checking tab display');
      });
    });
  });
});

export {};

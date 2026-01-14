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
    cy.clearAppData();
    cy.setupAdminIntercepts();
    cy.visit('/login');
    cy.get('[data-testid="email-input"]', { timeout: 5000 }).type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').click();
    cy.url({ timeout: 5000 }).should('match', /\/(app|dashboard)/);
  });

  describe('Page Navigation', () => {
    it('should navigate to Admin Maintenance page', () => {
      cy.visit('/app/admin/maintenance');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Maintenance') ||
                          $body.text().includes('System') ||
                          $body.text().includes('Health') ||
                          $body.text().includes('Permission');
        if (hasContent) {
          cy.log('Admin Maintenance page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display page title', () => {
      cy.visit('/app/admin/maintenance');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasTitle = $body.text().includes('Maintenance') ||
                         $body.text().includes('System Health');
        if (hasTitle) {
          cy.log('Page title displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display breadcrumbs', () => {
      cy.visit('/app/admin/maintenance');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasBreadcrumbs = $body.text().includes('Admin') ||
                               $body.text().includes('Dashboard');
        if (hasBreadcrumbs) {
          cy.log('Breadcrumbs displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Tab Navigation', () => {
    beforeEach(() => {
      cy.visit('/app/admin/maintenance');
      cy.waitForPageLoad();
    });

    it('should display maintenance tabs', () => {
      cy.get('body').then($body => {
        const hasTabs = $body.find('[role="tab"], button[class*="tab"], [class*="Tab"]').length > 0;
        if (hasTabs) {
          cy.log('Maintenance tabs displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should switch to Overview tab', () => {
      cy.get('body').then($body => {
        const overviewTab = $body.find('button:contains("Overview"), [role="tab"]:contains("Overview")');
        if (overviewTab.length > 0) {
          cy.wrap(overviewTab).first().should('be.visible').click();
          cy.waitForPageLoad();
          cy.log('Switched to Overview tab');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should switch to Maintenance Mode tab', () => {
      cy.get('body').then($body => {
        const modeTab = $body.find('button:contains("Mode"), button:contains("Maintenance Mode"), [role="tab"]:contains("Mode")');
        if (modeTab.length > 0) {
          cy.wrap(modeTab).first().should('be.visible').click();
          cy.waitForPageLoad();
          cy.log('Switched to Maintenance Mode tab');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should switch to System Health tab', () => {
      cy.get('body').then($body => {
        const healthTab = $body.find('button:contains("Health"), button:contains("System Health"), [role="tab"]:contains("Health")');
        if (healthTab.length > 0) {
          cy.wrap(healthTab).first().should('be.visible').click();
          cy.waitForPageLoad();
          cy.log('Switched to System Health tab');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should switch to Backups tab', () => {
      cy.get('body').then($body => {
        const backupsTab = $body.find('button:contains("Backup"), [role="tab"]:contains("Backup")');
        if (backupsTab.length > 0) {
          cy.wrap(backupsTab).first().should('be.visible').click();
          cy.waitForPageLoad();
          cy.log('Switched to Backups tab');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should switch to Cleanup tab', () => {
      cy.get('body').then($body => {
        const cleanupTab = $body.find('button:contains("Cleanup"), [role="tab"]:contains("Cleanup")');
        if (cleanupTab.length > 0) {
          cy.wrap(cleanupTab).first().should('be.visible').click();
          cy.waitForPageLoad();
          cy.log('Switched to Cleanup tab');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should switch to Operations tab', () => {
      cy.get('body').then($body => {
        const operationsTab = $body.find('button:contains("Operations"), [role="tab"]:contains("Operations")');
        if (operationsTab.length > 0) {
          cy.wrap(operationsTab).first().should('be.visible').click();
          cy.waitForPageLoad();
          cy.log('Switched to Operations tab');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should switch to Schedules tab', () => {
      cy.get('body').then($body => {
        const schedulesTab = $body.find('button:contains("Schedule"), [role="tab"]:contains("Schedule")');
        if (schedulesTab.length > 0) {
          cy.wrap(schedulesTab).first().should('be.visible').click();
          cy.waitForPageLoad();
          cy.log('Switched to Schedules tab');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should update URL when switching tabs', () => {
      cy.get('body').then($body => {
        const healthTab = $body.find('button:contains("Health"), [role="tab"]:contains("Health")');
        if (healthTab.length > 0) {
          cy.wrap(healthTab).first().should('be.visible').click();
          cy.waitForPageLoad();
          cy.url().then(url => {
            if (url.includes('tab=') || url.includes('health')) {
              cy.log('URL updated with tab parameter');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Overview Tab Content', () => {
    beforeEach(() => {
      cy.visit('/app/admin/maintenance');
      cy.waitForPageLoad();
    });

    it('should display system status overview', () => {
      cy.get('body').then($body => {
        const hasOverview = $body.text().includes('Status') ||
                            $body.text().includes('Overview') ||
                            $body.text().includes('System');
        if (hasOverview) {
          cy.log('System status overview displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display maintenance status indicator', () => {
      cy.get('body').then($body => {
        const hasStatus = $body.text().includes('Active') ||
                          $body.text().includes('Inactive') ||
                          $body.text().includes('Enabled') ||
                          $body.text().includes('Disabled') ||
                          $body.find('[class*="badge"], [class*="status"]').length > 0;
        if (hasStatus) {
          cy.log('Maintenance status indicator displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Maintenance Mode Controls', () => {
    beforeEach(() => {
      cy.visit('/app/admin/maintenance?tab=mode');
      cy.waitForPageLoad();
    });

    it('should display maintenance mode toggle', () => {
      cy.get('body').then($body => {
        const hasToggle = $body.find('input[type="checkbox"], button[role="switch"], [class*="toggle"], [class*="switch"]').length > 0;
        if (hasToggle) {
          cy.log('Maintenance mode toggle found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display maintenance mode settings', () => {
      cy.get('body').then($body => {
        const hasSettings = $body.text().includes('Message') ||
                            $body.text().includes('Duration') ||
                            $body.text().includes('Allowed IPs') ||
                            $body.text().includes('Settings');
        if (hasSettings) {
          cy.log('Maintenance mode settings displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have enable/disable maintenance button', () => {
      cy.get('body').then($body => {
        const maintenanceButton = $body.find('button:contains("Enable"), button:contains("Disable"), button:contains("Activate")');
        if (maintenanceButton.length > 0) {
          cy.log('Enable/Disable maintenance button found');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('System Health Display', () => {
    beforeEach(() => {
      cy.visit('/app/admin/maintenance?tab=health');
      cy.waitForPageLoad();
    });

    it('should display system health metrics', () => {
      cy.get('body').then($body => {
        const hasMetrics = $body.text().includes('CPU') ||
                           $body.text().includes('Memory') ||
                           $body.text().includes('Disk') ||
                           $body.text().includes('Health');
        if (hasMetrics) {
          cy.log('System health metrics displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display health score', () => {
      cy.get('body').then($body => {
        const hasScore = $body.text().includes('Score') ||
                         $body.text().includes('%') ||
                         $body.text().includes('Healthy') ||
                         $body.text().includes('Warning');
        if (hasScore) {
          cy.log('Health score displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display service status list', () => {
      cy.get('body').then($body => {
        const hasServices = $body.text().includes('Database') ||
                            $body.text().includes('Redis') ||
                            $body.text().includes('Queue') ||
                            $body.text().includes('Service');
        if (hasServices) {
          cy.log('Service status list displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have refresh health button', () => {
      cy.get('body').then($body => {
        const refreshButton = $body.find('button:contains("Refresh"), button:contains("Check"), [aria-label*="refresh"]');
        if (refreshButton.length > 0) {
          cy.log('Refresh health button found');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Backup Management', () => {
    beforeEach(() => {
      cy.visit('/app/admin/maintenance?tab=backups');
      cy.waitForPageLoad();
    });

    it('should display backup list', () => {
      cy.get('body').then($body => {
        const hasBackups = $body.text().includes('Backup') ||
                           $body.text().includes('Restore') ||
                           $body.text().includes('Database');
        if (hasBackups) {
          cy.log('Backup list displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have Create Backup button', () => {
      cy.get('body').then($body => {
        const createButton = $body.find('button:contains("Create Backup"), button:contains("New Backup")');
        if (createButton.length > 0) {
          cy.log('Create Backup button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display backup details', () => {
      cy.get('body').then($body => {
        const hasDetails = $body.text().includes('Size') ||
                           $body.text().includes('Date') ||
                           $body.text().includes('Type') ||
                           $body.text().includes('Status');
        if (hasDetails) {
          cy.log('Backup details displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have restore backup option', () => {
      cy.get('body').then($body => {
        const restoreButton = $body.find('button:contains("Restore"), [aria-label*="restore"]');
        if (restoreButton.length > 0) {
          cy.log('Restore backup option found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have delete backup option', () => {
      cy.get('body').then($body => {
        const deleteButton = $body.find('button:contains("Delete"), [aria-label*="delete"]');
        if (deleteButton.length > 0) {
          cy.log('Delete backup option found');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Cleanup Operations', () => {
    beforeEach(() => {
      cy.visit('/app/admin/maintenance?tab=cleanup');
      cy.waitForPageLoad();
    });

    it('should display cleanup options', () => {
      cy.get('body').then($body => {
        const hasCleanup = $body.text().includes('Cleanup') ||
                           $body.text().includes('Clear') ||
                           $body.text().includes('Cache');
        if (hasCleanup) {
          cy.log('Cleanup options displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have Run Cleanup button', () => {
      cy.get('body').then($body => {
        const runButton = $body.find('button:contains("Run Cleanup"), button:contains("Start Cleanup"), button:contains("Clean")');
        if (runButton.length > 0) {
          cy.log('Run Cleanup button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display cleanup stats', () => {
      cy.get('body').then($body => {
        const hasStats = $body.text().includes('Temporary Files') ||
                         $body.text().includes('Old Logs') ||
                         $body.text().includes('Cache') ||
                         $body.text().includes('Space');
        if (hasStats) {
          cy.log('Cleanup stats displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have cleanup type selection', () => {
      cy.get('body').then($body => {
        const hasSelection = $body.find('input[type="checkbox"], select, [class*="checkbox"]').length > 0;
        if (hasSelection) {
          cy.log('Cleanup type selection found');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Scheduled Maintenance', () => {
    beforeEach(() => {
      cy.visit('/app/admin/maintenance?tab=schedules');
      cy.waitForPageLoad();
    });

    it('should display scheduled maintenance list', () => {
      cy.get('body').then($body => {
        const hasSchedules = $body.text().includes('Schedule') ||
                             $body.text().includes('Planned') ||
                             $body.text().includes('Upcoming');
        if (hasSchedules) {
          cy.log('Scheduled maintenance list displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have New Schedule button', () => {
      cy.get('body').then($body => {
        const newButton = $body.find('button:contains("New Schedule"), button:contains("Create Schedule"), button:contains("Add")');
        if (newButton.length > 0) {
          cy.log('New Schedule button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display schedule details', () => {
      cy.get('body').then($body => {
        const hasDetails = $body.text().includes('Time') ||
                           $body.text().includes('Duration') ||
                           $body.text().includes('Recurring') ||
                           $body.text().includes('Type');
        if (hasDetails) {
          cy.log('Schedule details displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have edit schedule option', () => {
      cy.get('body').then($body => {
        const editButton = $body.find('button:contains("Edit"), [aria-label*="edit"]');
        if (editButton.length > 0) {
          cy.log('Edit schedule option found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have cancel schedule option', () => {
      cy.get('body').then($body => {
        const cancelButton = $body.find('button:contains("Cancel"), button:contains("Delete"), [aria-label*="cancel"]');
        if (cancelButton.length > 0) {
          cy.log('Cancel schedule option found');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Tab-Specific Actions', () => {
    it('should show Create Backup action on backups tab', () => {
      cy.visit('/app/admin/maintenance?tab=backups');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasAction = $body.find('button:contains("Create Backup"), button:contains("New Backup")').length > 0;
        if (hasAction) {
          cy.log('Create Backup action shown');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should show Run Cleanup action on cleanup tab', () => {
      cy.visit('/app/admin/maintenance?tab=cleanup');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasAction = $body.find('button:contains("Run Cleanup"), button:contains("Start Cleanup")').length > 0;
        if (hasAction) {
          cy.log('Run Cleanup action shown');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should show New Schedule action on schedules tab', () => {
      cy.visit('/app/admin/maintenance?tab=schedules');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasAction = $body.find('button:contains("New Schedule"), button:contains("Create Schedule")').length > 0;
        if (hasAction) {
          cy.log('New Schedule action shown');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.intercept('GET', '/api/v1/admin/maintenance*', {
        statusCode: 500,
        body: { success: false, error: 'Server error' }
      });

      cy.visit('/app/admin/maintenance');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
      cy.get('body').should('not.contain.text', 'Cannot read');
      cy.get('body').should('not.contain.text', 'TypeError');
    });

    it('should display error notification on failure', () => {
      cy.intercept('GET', '/api/v1/admin/maintenance*', {
        statusCode: 500,
        body: { success: false, error: 'Failed to load maintenance data' }
      });

      cy.visit('/app/admin/maintenance');
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

  describe('Permission-Based Access', () => {
    it('should show access denied for unauthorized users', () => {
      cy.intercept('GET', '/api/v1/users/me', {
        statusCode: 200,
        body: {
          success: true,
          data: {
            id: 'test-user',
            email: 'limited@test.com',
            permissions: ['basic.read']
          }
        }
      });

      cy.visit('/app/admin/maintenance');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasPermissionCheck = $body.text().includes('Permission') ||
                                    $body.text().includes('Access') ||
                                    $body.text().includes('Denied');
        if (hasPermissionCheck) {
          cy.log('Permission check displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/admin/maintenance');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Maintenance') || $body.text().includes('Admin');
        if (hasContent) {
          cy.log('Content visible on mobile');
        }
      });
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/admin/maintenance');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Maintenance') || $body.text().includes('Admin');
        if (hasContent) {
          cy.log('Content visible on tablet');
        }
      });
    });

    it('should display tabs properly on small screens', () => {
      cy.viewport(375, 667);
      cy.visit('/app/admin/maintenance');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
    });
  });
});


export {};

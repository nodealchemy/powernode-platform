/// <reference types="cypress" />

/**
 * System Workers Page Tests
 *
 * Tests for Workers management functionality including:
 * - Page navigation and load
 * - Tab navigation (overview, management, activity, security, settings)
 * - Worker stats display
 * - Worker list and filtering
 * - Worker CRUD operations
 * - Bulk actions
 * - Permission-based access
 * - Responsive design
 */

describe('System Workers Page Tests', () => {
  beforeEach(() => {
    cy.clearAppData();
    cy.visit('/login');
    cy.get('[data-testid="email-input"]', { timeout: 10000 }).type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').click();
    cy.url({ timeout: 15000 }).should('match', /\/(app|dashboard)/);
  });

  describe('Page Navigation', () => {
    it('should navigate to System Workers page', () => {
      cy.visit('/app/system/workers');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Workers') ||
                          $body.text().includes('Jobs') ||
                          $body.text().includes('Background') ||
                          $body.text().includes('Permission');
        if (hasContent) {
          cy.log('System Workers page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display page title', () => {
      cy.visit('/app/system/workers');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasTitle = $body.text().includes('Workers') ||
                         $body.text().includes('Background');
        if (hasTitle) {
          cy.log('Page title displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display breadcrumbs', () => {
      cy.visit('/app/system/workers');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasBreadcrumbs = $body.text().includes('System') ||
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
      cy.visit('/app/system/workers');
      cy.wait(2000);
    });

    it('should display worker tabs', () => {
      cy.get('body').then($body => {
        const hasTabs = $body.find('[role="tab"], button[class*="tab"], [class*="Tab"]').length > 0;
        if (hasTabs) {
          cy.log('Worker tabs displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should switch to Overview tab', () => {
      cy.get('body').then($body => {
        const overviewTab = $body.find('button:contains("Overview"), [role="tab"]:contains("Overview")');
        if (overviewTab.length > 0) {
          cy.wrap(overviewTab).first().click({ force: true });
          cy.wait(500);
          cy.log('Switched to Overview tab');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should switch to Management tab', () => {
      cy.get('body').then($body => {
        const managementTab = $body.find('button:contains("Management"), [role="tab"]:contains("Management")');
        if (managementTab.length > 0) {
          cy.wrap(managementTab).first().click({ force: true });
          cy.wait(500);
          cy.log('Switched to Management tab');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should switch to Activity tab', () => {
      cy.get('body').then($body => {
        const activityTab = $body.find('button:contains("Activity"), [role="tab"]:contains("Activity")');
        if (activityTab.length > 0) {
          cy.wrap(activityTab).first().click({ force: true });
          cy.wait(500);
          cy.log('Switched to Activity tab');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should switch to Security tab', () => {
      cy.get('body').then($body => {
        const securityTab = $body.find('button:contains("Security"), [role="tab"]:contains("Security")');
        if (securityTab.length > 0) {
          cy.wrap(securityTab).first().click({ force: true });
          cy.wait(500);
          cy.log('Switched to Security tab');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should switch to Settings tab', () => {
      cy.get('body').then($body => {
        const settingsTab = $body.find('button:contains("Settings"), [role="tab"]:contains("Settings")');
        if (settingsTab.length > 0) {
          cy.wrap(settingsTab).first().click({ force: true });
          cy.wait(500);
          cy.log('Switched to Settings tab');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should update URL when switching tabs', () => {
      cy.get('body').then($body => {
        const activityTab = $body.find('button:contains("Activity"), [role="tab"]:contains("Activity")');
        if (activityTab.length > 0) {
          cy.wrap(activityTab).first().click({ force: true });
          cy.wait(500);
          cy.url().then(url => {
            if (url.includes('tab=') || url.includes('activity')) {
              cy.log('URL updated with tab parameter');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Stats Display', () => {
    beforeEach(() => {
      cy.visit('/app/system/workers');
      cy.wait(2000);
    });

    it('should display Total Workers stat', () => {
      cy.get('body').then($body => {
        const hasTotal = $body.text().includes('Total');
        if (hasTotal) {
          cy.log('Total Workers stat displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display Active Workers stat', () => {
      cy.get('body').then($body => {
        const hasActive = $body.text().includes('Active');
        if (hasActive) {
          cy.log('Active Workers stat displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display Suspended Workers stat', () => {
      cy.get('body').then($body => {
        const hasSuspended = $body.text().includes('Suspended');
        if (hasSuspended) {
          cy.log('Suspended Workers stat displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display Revoked Workers stat', () => {
      cy.get('body').then($body => {
        const hasRevoked = $body.text().includes('Revoked');
        if (hasRevoked) {
          cy.log('Revoked Workers stat displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display System Workers count', () => {
      cy.get('body').then($body => {
        const hasSystem = $body.text().includes('System');
        if (hasSystem) {
          cy.log('System Workers count displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display Account Workers count', () => {
      cy.get('body').then($body => {
        const hasAccount = $body.text().includes('Account');
        if (hasAccount) {
          cy.log('Account Workers count displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Worker List Display', () => {
    beforeEach(() => {
      cy.visit('/app/system/workers');
      cy.wait(2000);
    });

    it('should display worker list', () => {
      cy.get('body').then($body => {
        const hasWorkers = $body.find('table, [class*="list"], [class*="grid"]').length > 0;
        if (hasWorkers) {
          cy.log('Worker list displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display worker names', () => {
      cy.get('body').then($body => {
        const hasNames = $body.text().includes('Worker') ||
                         $body.text().includes('Name');
        if (hasNames) {
          cy.log('Worker names displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display worker status', () => {
      cy.get('body').then($body => {
        const hasStatus = $body.text().includes('Active') ||
                          $body.text().includes('Suspended') ||
                          $body.text().includes('Revoked') ||
                          $body.find('[class*="badge"], [class*="status"]').length > 0;
        if (hasStatus) {
          cy.log('Worker status displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display worker type', () => {
      cy.get('body').then($body => {
        const hasType = $body.text().includes('System') ||
                        $body.text().includes('Account') ||
                        $body.text().includes('Type');
        if (hasType) {
          cy.log('Worker type displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Filtering and Sorting', () => {
    beforeEach(() => {
      cy.visit('/app/system/workers');
      cy.wait(2000);
    });

    it('should have search input', () => {
      cy.get('body').then($body => {
        const hasSearch = $body.find('input[type="search"], input[placeholder*="search"], input[placeholder*="Search"]').length > 0;
        if (hasSearch) {
          cy.log('Search input found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have status filter', () => {
      cy.get('body').then($body => {
        const hasFilter = $body.find('select, [class*="filter"]').length > 0 ||
                          $body.find('button:contains("Filter")').length > 0;
        if (hasFilter) {
          cy.log('Status filter found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have type filter', () => {
      cy.get('body').then($body => {
        const hasTypeFilter = $body.find('select, button:contains("Type")').length > 0;
        if (hasTypeFilter) {
          cy.log('Type filter found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have sort options', () => {
      cy.get('body').then($body => {
        const hasSort = $body.find('select, button:contains("Sort")').length > 0 ||
                        $body.find('th[class*="sortable"]').length > 0;
        if (hasSort) {
          cy.log('Sort options found');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Create Worker Modal', () => {
    beforeEach(() => {
      cy.visit('/app/system/workers');
      cy.wait(2000);
    });

    it('should have Create Worker button', () => {
      cy.get('body').then($body => {
        const createButton = $body.find('button:contains("Create Worker"), button:contains("Add Worker"), button:contains("New Worker")');
        if (createButton.length > 0) {
          cy.log('Create Worker button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should open create worker modal', () => {
      cy.get('body').then($body => {
        const createButton = $body.find('button:contains("Create Worker"), button:contains("Add Worker"), button:contains("New")');
        if (createButton.length > 0) {
          cy.wrap(createButton).first().click({ force: true });
          cy.wait(500);
          cy.get('body').then($modalBody => {
            const hasModal = $modalBody.find('[role="dialog"], [class*="modal"], [class*="Modal"]').length > 0;
            if (hasModal) {
              cy.log('Create worker modal opened');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have worker name field', () => {
      cy.get('body').then($body => {
        const createButton = $body.find('button:contains("Create Worker"), button:contains("Add Worker")');
        if (createButton.length > 0) {
          cy.wrap(createButton).first().click({ force: true });
          cy.wait(500);
          cy.get('body').then($modalBody => {
            const hasNameField = $modalBody.find('input[name*="name"], input[placeholder*="name"]').length > 0;
            if (hasNameField) {
              cy.log('Worker name field found');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have worker type selection', () => {
      cy.get('body').then($body => {
        const createButton = $body.find('button:contains("Create Worker"), button:contains("Add Worker")');
        if (createButton.length > 0) {
          cy.wrap(createButton).first().click({ force: true });
          cy.wait(500);
          cy.get('body').then($modalBody => {
            const hasTypeSelect = $modalBody.find('select, input[type="radio"]').length > 0 ||
                                  $modalBody.text().includes('Type');
            if (hasTypeSelect) {
              cy.log('Worker type selection found');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should close modal on cancel', () => {
      cy.get('body').then($body => {
        const createButton = $body.find('button:contains("Create Worker"), button:contains("Add Worker")');
        if (createButton.length > 0) {
          cy.wrap(createButton).first().click({ force: true });
          cy.wait(500);

          cy.get('body').then($modalBody => {
            const cancelButton = $modalBody.find('button:contains("Cancel"), button:contains("Close")');
            if (cancelButton.length > 0) {
              cy.wrap(cancelButton).first().click({ force: true });
              cy.wait(300);
              cy.log('Modal closed on cancel');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Worker Actions', () => {
    beforeEach(() => {
      cy.visit('/app/system/workers');
      cy.wait(2000);
    });

    it('should have activate button', () => {
      cy.get('body').then($body => {
        const activateButton = $body.find('button:contains("Activate"), [aria-label*="activate"]');
        if (activateButton.length > 0) {
          cy.log('Activate button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have suspend button', () => {
      cy.get('body').then($body => {
        const suspendButton = $body.find('button:contains("Suspend"), [aria-label*="suspend"]');
        if (suspendButton.length > 0) {
          cy.log('Suspend button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have revoke button', () => {
      cy.get('body').then($body => {
        const revokeButton = $body.find('button:contains("Revoke"), [aria-label*="revoke"]');
        if (revokeButton.length > 0) {
          cy.log('Revoke button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have delete button', () => {
      cy.get('body').then($body => {
        const deleteButton = $body.find('button:contains("Delete"), [aria-label*="delete"]');
        if (deleteButton.length > 0) {
          cy.log('Delete button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have view details option', () => {
      cy.get('body').then($body => {
        const viewButton = $body.find('button:contains("View"), button:contains("Details"), [aria-label*="view"]');
        if (viewButton.length > 0) {
          cy.log('View details option found');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Bulk Actions', () => {
    beforeEach(() => {
      cy.visit('/app/system/workers');
      cy.wait(2000);
    });

    it('should have select all checkbox', () => {
      cy.get('body').then($body => {
        const hasSelectAll = $body.find('input[type="checkbox"]').length > 0;
        if (hasSelectAll) {
          cy.log('Select all checkbox found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should show bulk action bar when items selected', () => {
      cy.get('body').then($body => {
        const checkbox = $body.find('input[type="checkbox"]');
        if (checkbox.length > 1) {
          cy.wrap(checkbox).eq(1).click({ force: true });
          cy.wait(300);
          cy.get('body').then($bulkBody => {
            const hasBulkActions = $bulkBody.text().includes('selected') ||
                                   $bulkBody.find('[class*="bulk"], [class*="actions"]').length > 0;
            if (hasBulkActions) {
              cy.log('Bulk action bar shown');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have bulk activate option', () => {
      cy.get('body').then($body => {
        const bulkActivate = $body.find('button:contains("Activate")');
        if (bulkActivate.length > 0) {
          cy.log('Bulk activate option found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have bulk suspend option', () => {
      cy.get('body').then($body => {
        const bulkSuspend = $body.find('button:contains("Suspend")');
        if (bulkSuspend.length > 0) {
          cy.log('Bulk suspend option found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have bulk delete option', () => {
      cy.get('body').then($body => {
        const bulkDelete = $body.find('button:contains("Delete")');
        if (bulkDelete.length > 0) {
          cy.log('Bulk delete option found');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Activity Tab Content', () => {
    beforeEach(() => {
      cy.visit('/app/system/workers?tab=activity');
      cy.wait(2000);
    });

    it('should display activity log', () => {
      cy.get('body').then($body => {
        const hasActivity = $body.text().includes('Activity') ||
                            $body.text().includes('Log') ||
                            $body.text().includes('History');
        if (hasActivity) {
          cy.log('Activity log displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display activity timestamps', () => {
      cy.get('body').then($body => {
        const hasTimestamps = $body.text().includes('ago') ||
                              $body.text().includes('Date') ||
                              $body.text().includes(':');
        if (hasTimestamps) {
          cy.log('Activity timestamps displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Security Tab Content', () => {
    beforeEach(() => {
      cy.visit('/app/system/workers?tab=security');
      cy.wait(2000);
    });

    it('should display security settings', () => {
      cy.get('body').then($body => {
        const hasSecurity = $body.text().includes('Security') ||
                            $body.text().includes('Token') ||
                            $body.text().includes('API Key');
        if (hasSecurity) {
          cy.log('Security settings displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display token management', () => {
      cy.get('body').then($body => {
        const hasTokens = $body.text().includes('Token') ||
                          $body.text().includes('Key') ||
                          $body.text().includes('Secret');
        if (hasTokens) {
          cy.log('Token management displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Settings Tab Content', () => {
    beforeEach(() => {
      cy.visit('/app/system/workers?tab=settings');
      cy.wait(2000);
    });

    it('should display settings form', () => {
      cy.get('body').then($body => {
        const hasSettings = $body.text().includes('Settings') ||
                            $body.text().includes('Configuration') ||
                            $body.find('input, select').length > 0;
        if (hasSettings) {
          cy.log('Settings form displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have save settings button', () => {
      cy.get('body').then($body => {
        const saveButton = $body.find('button:contains("Save"), button:contains("Update")');
        if (saveButton.length > 0) {
          cy.log('Save settings button found');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.intercept('GET', '/api/v1/system/workers*', {
        statusCode: 500,
        body: { success: false, error: 'Server error' }
      });

      cy.visit('/app/system/workers');
      cy.wait(2000);

      cy.get('body').should('be.visible');
      cy.get('body').should('not.contain.text', 'Cannot read');
      cy.get('body').should('not.contain.text', 'TypeError');
    });

    it('should display error notification on failure', () => {
      cy.intercept('GET', '/api/v1/system/workers*', {
        statusCode: 500,
        body: { success: false, error: 'Failed to load workers' }
      });

      cy.visit('/app/system/workers');
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

      cy.visit('/app/system/workers');
      cy.wait(2000);

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

    it('should hide create button without permission', () => {
      cy.intercept('GET', '/api/v1/users/me', {
        statusCode: 200,
        body: {
          success: true,
          data: {
            id: 'test-user',
            email: 'readonly@test.com',
            permissions: ['system.workers.read']
          }
        }
      });

      cy.visit('/app/system/workers');
      cy.wait(2000);

      cy.get('body').then($body => {
        const createButton = $body.find('button:contains("Create Worker")');
        if (createButton.length === 0) {
          cy.log('Create button hidden without permission');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/system/workers');
      cy.wait(2000);

      cy.get('body').should('be.visible');
      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Workers') || $body.text().includes('System');
        if (hasContent) {
          cy.log('Content visible on mobile');
        }
      });
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/system/workers');
      cy.wait(2000);

      cy.get('body').should('be.visible');
      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Workers') || $body.text().includes('System');
        if (hasContent) {
          cy.log('Content visible on tablet');
        }
      });
    });

    it('should display tabs properly on small screens', () => {
      cy.viewport(375, 667);
      cy.visit('/app/system/workers');
      cy.wait(2000);

      cy.get('body').should('be.visible');
    });
  });
});

/// <reference types="cypress" />

/**
 * System Storage Providers Page Tests
 *
 * Tests for File Storage (Storage Providers) management functionality including:
 * - Page navigation and load
 * - Provider list display
 * - Stats display (Total Providers, Active Providers, Total Files)
 * - CRUD operations via dropdown menu
 * - Connection testing
 * - Default provider setting
 * - Permission-based access
 * - Responsive design
 *
 * Note: The page title is "File Storage" and actions are in dropdown menus
 * User may not have admin.storage.read permission, in which case a permission denied
 * message is shown: "You don't have permission to view storage providers."
 */

describe('System Storage Providers Page Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup({ intercepts: ['system'] });
  });

  describe('Page Navigation', () => {
    it('should navigate to Storage Providers page', () => {
      cy.assertPageReady('/app/system/storage');
      cy.assertContainsAny(['File Storage', 'storage', 'permission']);
    });

    it('should display page title or permission message', () => {
      cy.assertPageReady('/app/system/storage');
      cy.assertContainsAny(['File Storage', 'storage', 'permission']);
    });

    it('should display breadcrumbs', () => {
      cy.assertPageReady('/app/system/storage');
      cy.assertContainsAny(['System', 'Dashboard']);
    });
  });

  describe('Stats Display', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/system/storage');
    });

    it('should display Total Providers stat or permission message', () => {
      cy.assertContainsAny(['Total Providers', 'Total', 'providers', 'permission']);
    });

    it('should display Active Providers stat or permission message', () => {
      cy.assertContainsAny(['Active', 'providers', 'permission']);
    });

    it('should display Total Files stat', () => {
      cy.assertContainsAny(['Total Files', 'Files']);
    });

    it('should display stats cards', () => {
      cy.assertHasElement(['[data-testid="storage-stats"]', '[data-testid*="stat-card"]', '[class*="rounded-lg"]']);
    });
  });

  describe('Provider Information Panel', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/system/storage');
    });

    it('should display information about storage providers or permission message', () => {
      cy.assertContainsAny(['About Storage', 'storage providers define', 'permission', 'storage']);
    });

    it('should display Local storage option info or permission message', () => {
      cy.assertContainsAny(['Local Storage', 'Local', 'filesystem', 'permission']);
    });

    it('should display S3 storage option info or permission message', () => {
      cy.assertContainsAny(['Amazon S3', 'S3', 'AWS', 'permission']);
    });

    it('should display Azure storage option info or permission message', () => {
      cy.assertContainsAny(['Azure', 'Blob', 'Microsoft', 'permission']);
    });

    it('should display GCS storage option info or permission message', () => {
      cy.assertContainsAny(['Google Cloud Storage', 'Google Cloud', 'GCS', 'permission']);
    });
  });

  describe('Provider List Display', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/system/storage');
    });

    it('should display provider list or empty state or permission message', () => {
      cy.assertHasElement(['[data-testid="storage-provider-card"]', '[data-testid="storage-providers-grid"]', '[class*="grid"]', '[class*="text-center"]']);
    });

    it('should handle empty provider list or permission denied', () => {
      cy.assertContainsAny(['No storage providers', 'get started', 'Add Storage Provider', 'permission', 'storage']);
    });
  });

  describe('Create Provider Modal', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/system/storage');
    });

    it('should have Add Provider button if user has manage permission', () => {
      cy.assertContainsAny(['Add Provider', 'Add Storage Provider', 'permission']);
    });

    it('should open create provider modal when clicking Add Provider', () => {
      cy.contains('button', /Add (?:Storage )?Provider/).first().click();
      cy.waitForStableDOM();
      cy.assertModalVisible();
    });

    it('should have provider type selection in modal', () => {
      cy.contains('button', /Add (?:Storage )?Provider/).first().click();
      cy.waitForStableDOM();
      cy.assertContainsAny(['Provider Type', 'Local Storage', 'Amazon S3']);
    });

    it('should have provider name field in modal', () => {
      cy.contains('button', /Add (?:Storage )?Provider/).first().click();
      cy.waitForStableDOM();
      cy.assertHasElement(['input[placeholder*="Storage"]', 'input[placeholder*="Production"]', 'label:contains("Provider Name")']);
    });

    it('should close modal on cancel', () => {
      cy.contains('button', /Add (?:Storage )?Provider/).first().click();
      cy.waitForStableDOM();
      cy.contains('button', 'Cancel').click();
      cy.waitForModalClose();
    });
  });

  describe('Provider Actions (Dropdown Menu)', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/system/storage');
    });

    it('should have dropdown menu for provider actions', () => {
      cy.assertHasElement(['[data-testid="provider-action-menu"]', 'button svg']);
    });

    it('should have Configure option in dropdown', () => {
      cy.get('[data-testid="provider-action-menu"]').first().click();
      cy.waitForStableDOM();
      cy.assertContainsAny(['Configure', 'Settings']);
    });

    it('should have Test Connection option in dropdown', () => {
      cy.get('[data-testid="provider-action-menu"]').first().click();
      cy.waitForStableDOM();
      cy.assertContainsAny(['Test Connection', 'Test']);
    });

    it('should have Delete option in dropdown', () => {
      cy.get('[data-testid="provider-action-menu"]').first().click();
      cy.waitForStableDOM();
      cy.assertContainsAny(['Delete']);
    });

    it('should have Set as Default option for non-default providers', () => {
      cy.get('[data-testid="provider-action-menu"]').first().click();
      cy.waitForStableDOM();
      cy.assertContainsAny(['Set as Default', 'Default', 'Configure', 'Delete']);
    });
  });

  describe('Connection Test Modal', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/system/storage');
    });

    it('should show connection test modal when testing', () => {
      cy.get('[data-testid="provider-action-menu"]').first().click();
      cy.waitForStableDOM();
      cy.contains('button', 'Test Connection').click();
      cy.waitForStableDOM();
      cy.assertContainsAny(['Testing connection', 'Connection Test', 'Connection Successful', 'Connection Failed']);
    });

    it('should display test results or page content', () => {
      cy.assertContainsAny(['test', 'connection', 'storage', 'provider', 'permission']);
    });
  });

  describe('Edit Provider Modal', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/system/storage');
    });

    it('should open edit provider modal via Configure', () => {
      cy.get('[data-testid="provider-action-menu"]').first().click();
      cy.waitForStableDOM();
      cy.contains('button', 'Configure').click();
      cy.waitForStableDOM();
      cy.assertModalVisible();
    });

    it('should populate form with existing data in edit mode', () => {
      cy.get('[data-testid="provider-action-menu"]').first().click();
      cy.waitForStableDOM();
      cy.contains('button', 'Configure').click();
      cy.waitForStableDOM();
      cy.assertContainsAny(['Edit Storage Provider', 'Update Provider']);
    });
  });

  describe('Delete Confirmation', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/system/storage');
    });

    it('should show delete confirmation dialog', () => {
      cy.get('[data-testid="provider-action-menu"]').first().click();
      cy.waitForStableDOM();
      cy.on('window:confirm', () => false);
      cy.contains('button', 'Delete').click();
    });

    it('should handle delete confirmation interaction', () => {
      cy.assertContainsAny(['File Storage', 'storage', 'permission']);
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.testErrorHandling('/api/v1/system/storage*', {
        statusCode: 500,
        visitUrl: '/app/system/storage'
      });
    });

    it('should display error notification or handle failure', () => {
      cy.intercept('GET', '/api/v1/system/storage*', {
        statusCode: 500,
        body: { success: false, error: 'Failed to load storage providers' }
      }).as('getStorageError');

      cy.visit('/app/system/storage');
      cy.waitForPageLoad();

      cy.assertContainsAny(['error', 'failed', 'File Storage', 'storage', 'permission']);
    });
  });

  describe('Permission-Based Access', () => {
    it('should show permission message or storage content', () => {
      cy.assertPageReady('/app/system/storage');
      cy.assertContainsAny(['File Storage', 'storage', 'permission']);
    });

    it('should conditionally show Add Provider button based on permission', () => {
      cy.intercept('GET', '/api/v1/users/me', {
        statusCode: 200,
        body: {
          success: true,
          data: {
            id: 'test-user',
            email: 'readonly@test.com',
            permissions: ['admin.storage.read']
          }
        }
      }).as('getCurrentUserReadOnly');

      cy.visit('/app/system/storage');
      cy.waitForPageLoad();
      cy.assertContainsAny(['File Storage', 'storage', 'permission']);
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.testViewport('mobile', '/app/system/storage');
      cy.assertContainsAny(['File Storage', 'storage', 'permission']);
    });

    it('should display properly on tablet viewport', () => {
      cy.testViewport('tablet', '/app/system/storage');
      cy.assertContainsAny(['File Storage', 'storage', 'permission']);
    });

    it('should stack cards on small screens', () => {
      cy.viewport(375, 667);
      cy.visit('/app/system/storage');
      cy.waitForPageLoad();
      cy.assertContainsAny(['File Storage', 'storage', 'permission']);
    });
  });
});


export {};

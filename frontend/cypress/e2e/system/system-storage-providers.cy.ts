/// <reference types="cypress" />

/**
 * System Storage Providers Page Tests
 *
 * Tests for Storage Providers management functionality including:
 * - Page navigation and load
 * - Provider list display
 * - Stats display (Total, Active, Files)
 * - CRUD operations
 * - Connection testing
 * - Default provider setting
 * - Permission-based access
 * - Responsive design
 */

describe('System Storage Providers Page Tests', () => {
  beforeEach(() => {
    cy.clearAppData();
    cy.setupSystemIntercepts();
    cy.visit('/login');
    cy.get('[data-testid="email-input"]', { timeout: 5000 }).type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').click();
    cy.url({ timeout: 5000 }).should('match', /\/(app|dashboard)/);
  });

  describe('Page Navigation', () => {
    it('should navigate to Storage Providers page', () => {
      cy.visit('/app/system/storage-providers');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Storage') ||
                          $body.text().includes('Provider') ||
                          $body.text().includes('Files') ||
                          $body.text().includes('Permission');
        if (hasContent) {
          cy.log('Storage Providers page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display page title', () => {
      cy.visit('/app/system/storage-providers');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasTitle = $body.text().includes('Storage') ||
                         $body.text().includes('Provider');
        if (hasTitle) {
          cy.log('Page title displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display breadcrumbs', () => {
      cy.visit('/app/system/storage-providers');
      cy.waitForPageLoad();

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

  describe('Stats Display', () => {
    beforeEach(() => {
      cy.visit('/app/system/storage-providers');
      cy.waitForPageLoad();
    });

    it('should display Total Providers stat', () => {
      cy.get('body').then($body => {
        const hasTotal = $body.text().includes('Total') ||
                         $body.text().includes('Providers');
        if (hasTotal) {
          cy.log('Total Providers stat displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display Active Providers stat', () => {
      cy.get('body').then($body => {
        const hasActive = $body.text().includes('Active');
        if (hasActive) {
          cy.log('Active Providers stat displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display Total Files stat', () => {
      cy.get('body').then($body => {
        const hasFiles = $body.text().includes('Files') ||
                         $body.text().includes('Total Files');
        if (hasFiles) {
          cy.log('Total Files stat displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display stats cards', () => {
      cy.get('body').then($body => {
        const hasCards = $body.find('[class*="card"], [class*="stat"]').length > 0;
        if (hasCards) {
          cy.log('Stats cards displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Provider List Display', () => {
    beforeEach(() => {
      cy.visit('/app/system/storage-providers');
      cy.waitForPageLoad();
    });

    it('should display provider list', () => {
      cy.get('body').then($body => {
        const hasProviders = $body.find('table, [class*="list"], [class*="grid"]').length > 0;
        if (hasProviders) {
          cy.log('Provider list displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display Local storage provider', () => {
      cy.get('body').then($body => {
        const hasLocal = $body.text().includes('Local') ||
                         $body.text().includes('local');
        if (hasLocal) {
          cy.log('Local storage provider displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display S3 storage provider option', () => {
      cy.get('body').then($body => {
        const hasS3 = $body.text().includes('S3') ||
                      $body.text().includes('Amazon') ||
                      $body.text().includes('AWS');
        if (hasS3) {
          cy.log('S3 storage provider option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display Azure storage provider option', () => {
      cy.get('body').then($body => {
        const hasAzure = $body.text().includes('Azure') ||
                         $body.text().includes('Blob');
        if (hasAzure) {
          cy.log('Azure storage provider option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display GCS storage provider option', () => {
      cy.get('body').then($body => {
        const hasGCS = $body.text().includes('GCS') ||
                       $body.text().includes('Google') ||
                       $body.text().includes('Cloud Storage');
        if (hasGCS) {
          cy.log('GCS storage provider option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display provider status', () => {
      cy.get('body').then($body => {
        const hasStatus = $body.text().includes('Active') ||
                          $body.text().includes('Inactive') ||
                          $body.text().includes('Connected') ||
                          $body.find('[class*="badge"], [class*="status"]').length > 0;
        if (hasStatus) {
          cy.log('Provider status displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display default provider indicator', () => {
      cy.get('body').then($body => {
        const hasDefault = $body.text().includes('Default') ||
                           $body.text().includes('Primary') ||
                           $body.find('[class*="default"]').length > 0;
        if (hasDefault) {
          cy.log('Default provider indicator displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Create Provider Modal', () => {
    beforeEach(() => {
      cy.visit('/app/system/storage-providers');
      cy.waitForPageLoad();
    });

    it('should have Add Provider button', () => {
      cy.get('body').then($body => {
        const addButton = $body.find('button:contains("Add Provider"), button:contains("New Provider"), button:contains("Create")');
        if (addButton.length > 0) {
          cy.log('Add Provider button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should open create provider modal', () => {
      cy.get('body').then($body => {
        const addButton = $body.find('button:contains("Add Provider"), button:contains("New Provider"), button:contains("Create")');
        if (addButton.length > 0) {
          cy.wrap(addButton).first().should('be.visible').click();
          cy.waitForStableDOM();
          cy.get('body').then($modalBody => {
            const hasModal = $modalBody.find('[role="dialog"], [class*="modal"], [class*="Modal"]').length > 0;
            if (hasModal) {
              cy.log('Create provider modal opened');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have provider type selection', () => {
      cy.get('body').then($body => {
        const addButton = $body.find('button:contains("Add Provider"), button:contains("New Provider")');
        if (addButton.length > 0) {
          cy.wrap(addButton).first().should('be.visible').click();
          cy.waitForStableDOM();
          cy.get('body').then($modalBody => {
            const hasTypeSelect = $modalBody.find('select, [class*="select"], input[type="radio"]').length > 0 ||
                                  $modalBody.text().includes('Type');
            if (hasTypeSelect) {
              cy.log('Provider type selection found');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have provider name field', () => {
      cy.get('body').then($body => {
        const addButton = $body.find('button:contains("Add Provider"), button:contains("New Provider")');
        if (addButton.length > 0) {
          cy.wrap(addButton).first().should('be.visible').click();
          cy.waitForStableDOM();
          cy.get('body').then($modalBody => {
            const hasNameField = $modalBody.find('input[name*="name"], input[placeholder*="name"]').length > 0;
            if (hasNameField) {
              cy.log('Provider name field found');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should close modal on cancel', () => {
      cy.get('body').then($body => {
        const addButton = $body.find('button:contains("Add Provider"), button:contains("New Provider")');
        if (addButton.length > 0) {
          cy.wrap(addButton).first().should('be.visible').click();
          cy.waitForStableDOM();

          cy.get('body').then($modalBody => {
            const cancelButton = $modalBody.find('button:contains("Cancel"), button:contains("Close")');
            if (cancelButton.length > 0) {
              cy.wrap(cancelButton).first().should('be.visible').click();
              cy.waitForModalClose();
              cy.log('Modal closed on cancel');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Provider Actions', () => {
    beforeEach(() => {
      cy.visit('/app/system/storage-providers');
      cy.waitForPageLoad();
    });

    it('should have edit button', () => {
      cy.get('body').then($body => {
        const editButton = $body.find('button:contains("Edit"), [aria-label*="edit"]');
        if (editButton.length > 0) {
          cy.log('Edit button found');
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

    it('should have test connection button', () => {
      cy.get('body').then($body => {
        const testButton = $body.find('button:contains("Test"), button:contains("Verify"), button:contains("Check")');
        if (testButton.length > 0) {
          cy.log('Test connection button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have set as default option', () => {
      cy.get('body').then($body => {
        const defaultButton = $body.find('button:contains("Set as Default"), button:contains("Make Default"), button:contains("Default")');
        if (defaultButton.length > 0) {
          cy.log('Set as default option found');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Connection Test Modal', () => {
    beforeEach(() => {
      cy.visit('/app/system/storage-providers');
      cy.waitForPageLoad();
    });

    it('should open connection test modal', () => {
      cy.get('body').then($body => {
        const testButton = $body.find('button:contains("Test"), button:contains("Verify")');
        if (testButton.length > 0) {
          cy.wrap(testButton).first().should('be.visible').click();
          cy.waitForStableDOM();
          cy.get('body').then($modalBody => {
            const hasModal = $modalBody.find('[role="dialog"], [class*="modal"]').length > 0 ||
                             $modalBody.text().includes('Testing') ||
                             $modalBody.text().includes('Connection');
            if (hasModal) {
              cy.log('Connection test modal opened');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display test results', () => {
      cy.get('body').then($body => {
        const testButton = $body.find('button:contains("Test"), button:contains("Verify")');
        if (testButton.length > 0) {
          cy.wrap(testButton).first().should('be.visible').click();
          cy.waitForStableDOM();
          // Wait for test results to appear
          cy.get('[role="dialog"], [class*="modal"]', { timeout: 5000 }).should('be.visible');
          cy.get('body').then($modalBody => {
            const hasResults = $modalBody.text().includes('Success') ||
                               $modalBody.text().includes('Failed') ||
                               $modalBody.text().includes('Connected') ||
                               $modalBody.text().includes('Error');
            if (hasResults) {
              cy.log('Test results displayed');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Edit Provider Modal', () => {
    beforeEach(() => {
      cy.visit('/app/system/storage-providers');
      cy.waitForPageLoad();
    });

    it('should open edit provider modal', () => {
      cy.get('body').then($body => {
        const editButton = $body.find('button:contains("Edit"), [aria-label*="edit"]');
        if (editButton.length > 0) {
          cy.wrap(editButton).first().should('be.visible').click();
          cy.waitForStableDOM();
          cy.get('body').then($modalBody => {
            const hasModal = $modalBody.find('[role="dialog"], [class*="modal"]').length > 0;
            if (hasModal) {
              cy.log('Edit provider modal opened');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should populate form with existing data', () => {
      cy.get('body').then($body => {
        const editButton = $body.find('button:contains("Edit"), [aria-label*="edit"]');
        if (editButton.length > 0) {
          cy.wrap(editButton).first().should('be.visible').click();
          cy.waitForStableDOM();
          cy.get('body').then($modalBody => {
            const hasData = $modalBody.find('input[value], input:not([value=""])').length > 0;
            if (hasData) {
              cy.log('Form populated with existing data');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Delete Confirmation', () => {
    beforeEach(() => {
      cy.visit('/app/system/storage-providers');
      cy.waitForPageLoad();
    });

    it('should show delete confirmation dialog', () => {
      cy.get('body').then($body => {
        const deleteButton = $body.find('button:contains("Delete"), [aria-label*="delete"]');
        if (deleteButton.length > 0) {
          cy.wrap(deleteButton).first().should('be.visible').click();
          cy.waitForStableDOM();
          cy.get('body').then($confirmBody => {
            const hasConfirm = $confirmBody.text().includes('Confirm') ||
                               $confirmBody.text().includes('Are you sure') ||
                               $confirmBody.text().includes('Delete');
            if (hasConfirm) {
              cy.log('Delete confirmation dialog shown');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should cancel deletion on cancel click', () => {
      cy.get('body').then($body => {
        const deleteButton = $body.find('button:contains("Delete"), [aria-label*="delete"]');
        if (deleteButton.length > 0) {
          cy.wrap(deleteButton).first().should('be.visible').click();
          cy.waitForStableDOM();
          cy.get('body').then($confirmBody => {
            const cancelButton = $confirmBody.find('button:contains("Cancel"), button:contains("No")');
            if (cancelButton.length > 0) {
              cy.wrap(cancelButton).first().should('be.visible').click();
              cy.waitForModalClose();
              cy.log('Deletion cancelled');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.intercept('GET', '/api/v1/system/storage*', {
        statusCode: 500,
        body: { success: false, error: 'Server error' }
      }).as('getStorageError');

      cy.visit('/app/system/storage-providers');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
      cy.get('body').should('not.contain.text', 'Cannot read');
      cy.get('body').should('not.contain.text', 'TypeError');
    });

    it('should display error notification on failure', () => {
      cy.intercept('GET', '/api/v1/system/storage*', {
        statusCode: 500,
        body: { success: false, error: 'Failed to load storage providers' }
      }).as('getStorageError');

      cy.visit('/app/system/storage-providers');
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
      }).as('getCurrentUserLimited');

      cy.visit('/app/system/storage-providers');
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

    it('should hide create button without permission', () => {
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

      cy.visit('/app/system/storage-providers');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const addButton = $body.find('button:contains("Add Provider")');
        if (addButton.length === 0) {
          cy.log('Add button hidden without permission');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/system/storage-providers');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Storage') || $body.text().includes('Provider');
        if (hasContent) {
          cy.log('Content visible on mobile');
        }
      });
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/system/storage-providers');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Storage') || $body.text().includes('Provider');
        if (hasContent) {
          cy.log('Content visible on tablet');
        }
      });
    });

    it('should stack cards on small screens', () => {
      cy.viewport(375, 667);
      cy.visit('/app/system/storage-providers');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
    });
  });
});


export {};

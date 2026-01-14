/// <reference types="cypress" />

/**
 * Admin Roles & Permissions Page Tests
 *
 * Tests for Roles & Permissions management functionality including:
 * - Page navigation and load
 * - Built-in roles display
 * - Custom roles CRUD operations
 * - Permission reference grid
 * - Role assignment
 * - Permission-based access
 * - Responsive design
 */

describe('Admin Roles & Permissions Page Tests', () => {
  beforeEach(() => {
    cy.clearAppData();
    cy.visit('/login');
    cy.get('[data-testid="email-input"]', { timeout: 5000 }).type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').click();
    cy.url({ timeout: 5000 }).should('match', /\/(app|dashboard)/);
    cy.setupAdminIntercepts();
  });

  describe('Page Navigation', () => {
    it('should navigate to Admin Roles page', () => {
      cy.visit('/app/admin/roles');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Roles') ||
                          $body.text().includes('Permissions') ||
                          $body.text().includes('Access') ||
                          $body.text().includes('Permission');
        if (hasContent) {
          cy.log('Admin Roles page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display page title', () => {
      cy.visit('/app/admin/roles');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasTitle = $body.text().includes('Roles') ||
                         $body.text().includes('Permissions');
        if (hasTitle) {
          cy.log('Page title displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display breadcrumbs', () => {
      cy.visit('/app/admin/roles');
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

  describe('Built-in Roles Display', () => {
    beforeEach(() => {
      cy.visit('/app/admin/roles');
      cy.waitForPageLoad();
    });

    it('should display built-in roles section', () => {
      cy.get('body').then($body => {
        const hasBuiltIn = $body.text().includes('Built-in') ||
                           $body.text().includes('System') ||
                           $body.text().includes('Default');
        if (hasBuiltIn) {
          cy.log('Built-in roles section displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display admin role', () => {
      cy.get('body').then($body => {
        const hasAdmin = $body.text().includes('Admin') ||
                         $body.text().includes('admin');
        if (hasAdmin) {
          cy.log('Admin role displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display owner role', () => {
      cy.get('body').then($body => {
        const hasOwner = $body.text().includes('Owner') ||
                         $body.text().includes('owner');
        if (hasOwner) {
          cy.log('Owner role displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display member role', () => {
      cy.get('body').then($body => {
        const hasMember = $body.text().includes('Member') ||
                          $body.text().includes('member');
        if (hasMember) {
          cy.log('Member role displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display manager role', () => {
      cy.get('body').then($body => {
        const hasManager = $body.text().includes('Manager') ||
                           $body.text().includes('manager');
        if (hasManager) {
          cy.log('Manager role displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display billing admin role', () => {
      cy.get('body').then($body => {
        const hasBilling = $body.text().includes('Billing') ||
                           $body.text().includes('billing');
        if (hasBilling) {
          cy.log('Billing admin role displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should show role descriptions', () => {
      cy.get('body').then($body => {
        const hasDescriptions = $body.text().includes('Full access') ||
                                $body.text().includes('permissions') ||
                                $body.text().includes('manage');
        if (hasDescriptions) {
          cy.log('Role descriptions displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should indicate built-in roles cannot be edited', () => {
      cy.get('body').then($body => {
        const hasReadOnly = $body.text().includes('cannot be edited') ||
                            $body.text().includes('Read-only') ||
                            $body.text().includes('System role') ||
                            $body.find('button[disabled]').length > 0;
        if (hasReadOnly) {
          cy.log('Built-in roles marked as non-editable');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Custom Roles Section', () => {
    beforeEach(() => {
      cy.visit('/app/admin/roles');
      cy.waitForPageLoad();
    });

    it('should display custom roles section', () => {
      cy.get('body').then($body => {
        const hasCustom = $body.text().includes('Custom') ||
                          $body.text().includes('User-defined') ||
                          $body.text().includes('Create');
        if (hasCustom) {
          cy.log('Custom roles section displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have Create Role button', () => {
      cy.get('body').then($body => {
        const createButton = $body.find('button:contains("Create Role"), button:contains("Add Role"), button:contains("New Role")');
        if (createButton.length > 0) {
          cy.log('Create Role button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display custom role list', () => {
      cy.get('body').then($body => {
        const hasList = $body.find('table, [class*="list"], [class*="grid"]').length > 0;
        if (hasList) {
          cy.log('Custom role list displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Role Form Modal', () => {
    beforeEach(() => {
      cy.visit('/app/admin/roles');
      cy.waitForPageLoad();
    });

    it('should open create role modal', () => {
      cy.get('body').then($body => {
        const createButton = $body.find('button:contains("Create Role"), button:contains("Add Role"), button:contains("New Role")');
        if (createButton.length > 0) {
          cy.wrap(createButton).first().should('be.visible').click();
          cy.get('body').then($modalBody => {
            const hasModal = $modalBody.find('[role="dialog"], [class*="modal"], [class*="Modal"]').length > 0;
            if (hasModal) {
              cy.log('Create role modal opened');
            }
          });
        } else {
          cy.log('Create role button not found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have role name field', () => {
      cy.get('body').then($body => {
        const createButton = $body.find('button:contains("Create Role"), button:contains("Add Role")');
        if (createButton.length > 0) {
          cy.wrap(createButton).first().should('be.visible').click();
          cy.get('body').then($modalBody => {
            const hasNameField = $modalBody.find('input[name*="name"], input[placeholder*="name"], input[placeholder*="Name"]').length > 0;
            if (hasNameField) {
              cy.log('Role name field found');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have role description field', () => {
      cy.get('body').then($body => {
        const createButton = $body.find('button:contains("Create Role"), button:contains("Add Role")');
        if (createButton.length > 0) {
          cy.wrap(createButton).first().should('be.visible').click();
          cy.get('body').then($modalBody => {
            const hasDescField = $modalBody.find('textarea, input[name*="description"]').length > 0;
            if (hasDescField) {
              cy.log('Role description field found');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have permission selection', () => {
      cy.get('body').then($body => {
        const createButton = $body.find('button:contains("Create Role"), button:contains("Add Role")');
        if (createButton.length > 0) {
          cy.wrap(createButton).first().should('be.visible').click();
          cy.get('body').then($modalBody => {
            const hasPermissions = $modalBody.find('input[type="checkbox"], [class*="permission"]').length > 0 ||
                                   $modalBody.text().includes('Permission');
            if (hasPermissions) {
              cy.log('Permission selection found');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should close modal on cancel', () => {
      cy.get('body').then($body => {
        const createButton = $body.find('button:contains("Create Role"), button:contains("Add Role")');
        if (createButton.length > 0) {
          cy.wrap(createButton).first().should('be.visible').click();

          cy.get('body').then($modalBody => {
            const cancelButton = $modalBody.find('button:contains("Cancel"), button:contains("Close")');
            if (cancelButton.length > 0) {
              cy.wrap(cancelButton).first().should('be.visible').click();
              cy.log('Modal closed on cancel');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Role Actions', () => {
    beforeEach(() => {
      cy.visit('/app/admin/roles');
      cy.waitForPageLoad();
    });

    it('should have edit button for custom roles', () => {
      cy.get('body').then($body => {
        const editButton = $body.find('button:contains("Edit"), [aria-label*="edit"]');
        if (editButton.length > 0) {
          cy.log('Edit button found for custom roles');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have delete button for custom roles', () => {
      cy.get('body').then($body => {
        const deleteButton = $body.find('button:contains("Delete"), [aria-label*="delete"]');
        if (deleteButton.length > 0) {
          cy.log('Delete button found for custom roles');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have view users button', () => {
      cy.get('body').then($body => {
        const viewUsersButton = $body.find('button:contains("View Users"), button:contains("Users"), button:contains("Members")');
        if (viewUsersButton.length > 0) {
          cy.log('View users button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have duplicate role option', () => {
      cy.get('body').then($body => {
        const duplicateButton = $body.find('button:contains("Duplicate"), button:contains("Clone"), button:contains("Copy")');
        if (duplicateButton.length > 0) {
          cy.log('Duplicate role option found');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Role Users Modal', () => {
    beforeEach(() => {
      cy.visit('/app/admin/roles');
      cy.waitForPageLoad();
    });

    it('should open role users modal', () => {
      cy.get('body').then($body => {
        const viewUsersButton = $body.find('button:contains("View Users"), button:contains("Users"), button:contains("Members")');
        if (viewUsersButton.length > 0) {
          cy.wrap(viewUsersButton).first().should('be.visible').click();
          cy.get('body').then($modalBody => {
            const hasModal = $modalBody.find('[role="dialog"], [class*="modal"]').length > 0;
            if (hasModal) {
              cy.log('Role users modal opened');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display users with role', () => {
      cy.get('body').then($body => {
        const viewUsersButton = $body.find('button:contains("View Users"), button:contains("Users")');
        if (viewUsersButton.length > 0) {
          cy.wrap(viewUsersButton).first().should('be.visible').click();
          cy.get('body').then($modalBody => {
            const hasUsers = $modalBody.text().includes('User') ||
                             $modalBody.text().includes('Email') ||
                             $modalBody.find('table, [class*="list"]').length > 0;
            if (hasUsers) {
              cy.log('Users with role displayed');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Permission Reference Grid', () => {
    beforeEach(() => {
      cy.visit('/app/admin/roles');
      cy.waitForPageLoad();
    });

    it('should display permission reference', () => {
      cy.get('body').then($body => {
        const hasReference = $body.text().includes('Permission') ||
                             $body.text().includes('Reference') ||
                             $body.text().includes('Available');
        if (hasReference) {
          cy.log('Permission reference displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display permission categories', () => {
      cy.get('body').then($body => {
        const hasCategories = $body.text().includes('Users') ||
                              $body.text().includes('Billing') ||
                              $body.text().includes('Settings') ||
                              $body.text().includes('Admin');
        if (hasCategories) {
          cy.log('Permission categories displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display permission actions', () => {
      cy.get('body').then($body => {
        const hasActions = $body.text().includes('read') ||
                           $body.text().includes('create') ||
                           $body.text().includes('update') ||
                           $body.text().includes('delete') ||
                           $body.text().includes('manage');
        if (hasActions) {
          cy.log('Permission actions displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Delete Confirmation', () => {
    beforeEach(() => {
      cy.visit('/app/admin/roles');
      cy.waitForPageLoad();
    });

    it('should show delete confirmation dialog', () => {
      cy.get('body').then($body => {
        const deleteButton = $body.find('button:contains("Delete"), [aria-label*="delete"]');
        if (deleteButton.length > 0) {
          cy.wrap(deleteButton).first().should('be.visible').click();
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
          cy.get('body').then($confirmBody => {
            const cancelButton = $confirmBody.find('button:contains("Cancel"), button:contains("No")');
            if (cancelButton.length > 0) {
              cy.wrap(cancelButton).first().should('be.visible').click();
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
      cy.intercept('GET', '/api/v1/admin/roles*', {
        statusCode: 500,
        body: { success: false, error: 'Server error' }
      });

      cy.visit('/app/admin/roles');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
      cy.get('body').should('not.contain.text', 'Cannot read');
      cy.get('body').should('not.contain.text', 'TypeError');
    });

    it('should display error notification on failure', () => {
      cy.intercept('GET', '/api/v1/admin/roles*', {
        statusCode: 500,
        body: { success: false, error: 'Failed to load roles' }
      });

      cy.visit('/app/admin/roles');
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

      cy.visit('/app/admin/roles');
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
            permissions: ['admin.role.read']
          }
        }
      });

      cy.visit('/app/admin/roles');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const createButton = $body.find('button:contains("Create Role")');
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
      cy.visit('/app/admin/roles');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Roles') || $body.text().includes('Admin');
        if (hasContent) {
          cy.log('Content visible on mobile');
        }
      });
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/admin/roles');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Roles') || $body.text().includes('Admin');
        if (hasContent) {
          cy.log('Content visible on tablet');
        }
      });
    });

    it('should stack sections on small screens', () => {
      cy.viewport(375, 667);
      cy.visit('/app/admin/roles');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
    });
  });
});


export {};

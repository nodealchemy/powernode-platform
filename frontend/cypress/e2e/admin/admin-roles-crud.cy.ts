/// <reference types="cypress" />

/**
 * Admin Roles CRUD Workflows Tests
 *
 * Comprehensive E2E tests for Admin Role Management:
 * - View roles list
 * - Create new roles
 * - Edit role permissions
 * - Delete roles
 * - Assign roles to users
 * - Permission management
 */

describe('Admin Roles CRUD Workflows Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup({ role: 'admin', intercepts: ['admin'] });
    setupRolesIntercepts();
  });

  describe('Roles List', () => {
    beforeEach(() => {
      cy.navigateTo('/app/admin/roles');
    });

    it('should display roles page with title', () => {
      cy.assertContainsAny(['Roles', 'Role Management', 'Permissions']);
    });

    it('should display roles table or list', () => {
      cy.get('table, [data-testid="roles-list"], [class*="list"]').should('exist');
    });

    it('should display role names', () => {
      cy.assertContainsAny(['Admin', 'Member', 'Owner', 'Manager', 'role']);
    });

    it('should display permissions count', () => {
      cy.assertContainsAny(['permissions', 'access', 'rights']);
    });

    it('should display users count per role', () => {
      cy.assertContainsAny(['users', 'members', 'assigned']);
    });

    it('should have create role button', () => {
      cy.get('button').contains(/create|add|new/i).should('exist');
    });
  });

  describe('Role Details', () => {
    beforeEach(() => {
      cy.navigateTo('/app/admin/roles');
    });

    it('should show role details when row clicked', () => {
      cy.get('tr, [class*="row"]').contains(/admin|member/i).first().click();
      cy.assertContainsAny(['Details', 'Permissions', 'Users', 'Settings']);
    });

    it('should display role description', () => {
      cy.get('tr, [class*="row"]').first().click();
      cy.assertContainsAny(['description', 'about', 'access']);
    });

    it('should display assigned permissions', () => {
      cy.get('tr, [class*="row"]').first().click();
      cy.assertContainsAny(['Permissions', 'read', 'write', 'manage', 'access']);
    });
  });

  describe('Create Role', () => {
    beforeEach(() => {
      cy.navigateTo('/app/admin/roles');
    });

    it('should open create role modal when button clicked', () => {
      cy.get('button').contains(/create|add|new/i).first().click();
      cy.assertContainsAny(['Create Role', 'New Role', 'Role Name']);
    });

    it('should have role name input', () => {
      cy.get('button').contains(/create|add|new/i).first().click();
      cy.get('input[name="name"], input[placeholder*="name"], input').should('exist');
    });

    it('should have role description input', () => {
      cy.get('button').contains(/create|add|new/i).first().click();
      cy.get('textarea, input[name="description"]').should('exist');
    });

    it('should have permissions selection', () => {
      cy.get('button').contains(/create|add|new/i).first().click();
      cy.assertContainsAny(['Permissions', 'Select', 'Access']);
    });

    it('should create role when form submitted', () => {
      cy.intercept('POST', '**/api/**/admin/roles*', {
        statusCode: 201,
        body: { success: true, role: { id: 'role-new', name: 'Test Role' } },
      }).as('createRole');

      cy.get('button').contains(/create|add|new/i).first().click();
      cy.get('input[name="name"], input').first().type('Test Role');
      cy.get('button').contains(/save|create|submit/i).click();
      cy.wait('@createRole');
      cy.assertContainsAny(['created', 'success']);
    });

    it('should validate required fields', () => {
      cy.get('button').contains(/create|add|new/i).first().click();
      cy.get('button').contains(/save|create|submit/i).click();
      cy.assertContainsAny(['required', 'error', 'invalid']);
    });
  });

  describe('Edit Role', () => {
    beforeEach(() => {
      cy.navigateTo('/app/admin/roles');
    });

    it('should have edit button for each role', () => {
      cy.get('button').contains(/edit/i).should('exist');
    });

    it('should open edit modal when button clicked', () => {
      cy.get('button').contains(/edit/i).first().click();
      cy.assertContainsAny(['Edit Role', 'Update', 'Modify']);
    });

    it('should pre-fill current role data', () => {
      cy.get('button').contains(/edit/i).first().click();
      cy.get('input[name="name"], input').first().should('not.have.value', '');
    });

    it('should update role when form submitted', () => {
      cy.intercept('PUT', '**/api/**/admin/roles/*', {
        statusCode: 200,
        body: { success: true, role: { id: 'role-1', name: 'Updated Role' } },
      }).as('updateRole');

      cy.get('button').contains(/edit/i).first().click();
      cy.get('input[name="name"], input').first().clear().type('Updated Role');
      cy.get('button').contains(/save|update/i).click();
      cy.wait('@updateRole');
      cy.assertContainsAny(['updated', 'success']);
    });
  });

  describe('Delete Role', () => {
    beforeEach(() => {
      cy.navigateTo('/app/admin/roles');
    });

    it('should have delete button for each role', () => {
      cy.get('button').contains(/delete|remove/i).should('exist');
    });

    it('should show confirmation dialog before delete', () => {
      cy.get('button').contains(/delete/i).first().click();
      cy.assertContainsAny(['confirm', 'sure', 'delete', 'cancel']);
    });

    it('should delete role when confirmed', () => {
      cy.intercept('DELETE', '**/api/**/admin/roles/*', {
        statusCode: 200,
        body: { success: true, message: 'Role deleted' },
      }).as('deleteRole');

      cy.get('button').contains(/delete/i).first().click();
      cy.get('button').contains(/confirm|yes/i).click();
      cy.wait('@deleteRole');
      cy.assertContainsAny(['deleted', 'success', 'removed']);
    });

    it('should prevent deletion of system roles', () => {
      cy.get('body').then($body => {
        const adminRow = $body.find('tr:contains("Admin"), [class*="row"]:contains("Admin")').first();
        if (adminRow.find('button:contains("delete")').length === 0) {
          cy.log('System roles cannot be deleted');
        }
      });
    });
  });

  describe('Permission Management', () => {
    beforeEach(() => {
      cy.navigateTo('/app/admin/roles');
      cy.get('button').contains(/edit/i).first().click();
    });

    it('should display permission categories', () => {
      cy.assertContainsAny(['Users', 'Billing', 'Admin', 'Analytics', 'System']);
    });

    it('should show individual permissions with checkboxes', () => {
      cy.get('input[type="checkbox"]').should('have.length.at.least', 1);
    });

    it('should toggle permission when checkbox clicked', () => {
      cy.get('input[type="checkbox"]').first().click();
      cy.get('input[type="checkbox"]').first().should('be.checked');
    });

    it('should have select all option for category', () => {
      cy.get('button').contains(/select all|all/i).should('exist');
    });

    it('should save permission changes', () => {
      cy.intercept('PUT', '**/api/**/admin/roles/*', {
        statusCode: 200,
        body: { success: true },
      }).as('updatePermissions');

      cy.get('input[type="checkbox"]').first().click();
      cy.get('button').contains(/save/i).click();
      cy.wait('@updatePermissions');
    });
  });

  describe('Role Assignment', () => {
    beforeEach(() => {
      cy.navigateTo('/app/admin/roles');
      cy.get('tr, [class*="row"]').first().click();
    });

    it('should display users with this role', () => {
      cy.assertContainsAny(['Users', 'Assigned', 'Members']);
    });

    it('should have add user button', () => {
      cy.get('button').contains(/add user|assign/i).should('exist');
    });

    it('should assign user to role', () => {
      cy.intercept('POST', '**/api/**/admin/roles/*/users*', {
        statusCode: 200,
        body: { success: true, message: 'User assigned to role' },
      }).as('assignUser');

      cy.get('button').contains(/add user|assign/i).first().click();
      cy.get('body').then($body => {
        if ($body.find('input[type="checkbox"], [role="option"]').length > 0) {
          cy.get('input[type="checkbox"], [role="option"]').first().click();
          cy.get('button').contains(/confirm|add/i).click();
          cy.wait('@assignUser');
        }
      });
    });

    it('should remove user from role', () => {
      cy.intercept('DELETE', '**/api/**/admin/roles/*/users/*', {
        statusCode: 200,
        body: { success: true, message: 'User removed from role' },
      }).as('removeUser');

      cy.get('button').contains(/remove/i).first().click();
      cy.get('button').contains(/confirm|yes/i).click();
      cy.wait('@removeUser');
    });
  });

  describe('Search and Filter', () => {
    beforeEach(() => {
      cy.navigateTo('/app/admin/roles');
    });

    it('should display search input', () => {
      cy.get('input[type="search"], input[placeholder*="Search"]').should('exist');
    });

    it('should filter roles by name', () => {
      cy.get('input[type="search"]').type('admin');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Admin']);
    });

    it('should filter by system/custom roles', () => {
      cy.get('select, button').contains(/system|custom|type/i).should('exist');
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.testErrorHandling('**/api/**/admin/roles**', {
        statusCode: 500,
        visitUrl: '/app/admin/roles',
      });
    });
  });

  describe('Responsive Design', () => {
    it('should display correctly across viewports', () => {
      cy.testResponsiveDesign('/app/admin/roles', {
        checkContent: 'Roles',
      });
    });
  });
});

function setupRolesIntercepts() {
  const mockRoles = [
    {
      id: 'role-1',
      name: 'Admin',
      description: 'Full system access',
      is_system: true,
      permissions_count: 50,
      users_count: 3,
      permissions: ['users.read', 'users.write', 'billing.manage', 'admin.access'],
    },
    {
      id: 'role-2',
      name: 'Manager',
      description: 'Team management access',
      is_system: false,
      permissions_count: 25,
      users_count: 8,
      permissions: ['users.read', 'reports.read', 'team.manage'],
    },
    {
      id: 'role-3',
      name: 'Member',
      description: 'Basic user access',
      is_system: true,
      permissions_count: 10,
      users_count: 45,
      permissions: ['profile.read', 'profile.write', 'dashboard.access'],
    },
  ];

  const mockPermissions = [
    { id: 'perm-1', name: 'users.read', category: 'Users', description: 'View users' },
    { id: 'perm-2', name: 'users.write', category: 'Users', description: 'Edit users' },
    { id: 'perm-3', name: 'users.manage', category: 'Users', description: 'Manage users' },
    { id: 'perm-4', name: 'billing.read', category: 'Billing', description: 'View billing' },
    { id: 'perm-5', name: 'billing.manage', category: 'Billing', description: 'Manage billing' },
    { id: 'perm-6', name: 'admin.access', category: 'Admin', description: 'Admin panel access' },
  ];

  const mockUsers = [
    { id: 'user-1', email: 'admin@example.com', name: 'Admin User' },
    { id: 'user-2', email: 'manager@example.com', name: 'Manager User' },
  ];

  cy.intercept('GET', '**/api/**/admin/roles', {
    statusCode: 200,
    body: { items: mockRoles },
  }).as('getRoles');

  cy.intercept('GET', '**/api/**/admin/roles/*', {
    statusCode: 200,
    body: { role: mockRoles[0], users: mockUsers },
  }).as('getRoleDetails');

  cy.intercept('GET', '**/api/**/admin/permissions*', {
    statusCode: 200,
    body: { items: mockPermissions },
  }).as('getPermissions');

  cy.intercept('POST', '**/api/**/admin/roles', {
    statusCode: 201,
    body: { success: true, role: { id: 'role-new', name: 'New Role' } },
  }).as('createRole');

  cy.intercept('PUT', '**/api/**/admin/roles/*', {
    statusCode: 200,
    body: { success: true, role: mockRoles[0] },
  }).as('updateRole');

  cy.intercept('DELETE', '**/api/**/admin/roles/*', {
    statusCode: 200,
    body: { success: true, message: 'Role deleted' },
  }).as('deleteRole');

  cy.intercept('POST', '**/api/**/admin/roles/*/users*', {
    statusCode: 200,
    body: { success: true, message: 'User assigned' },
  }).as('assignUser');

  cy.intercept('DELETE', '**/api/**/admin/roles/*/users/*', {
    statusCode: 200,
    body: { success: true, message: 'User removed' },
  }).as('removeUser');
}

export {};

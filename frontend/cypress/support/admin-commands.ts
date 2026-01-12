/// <reference types="cypress" />

// Admin-related custom commands for Powernode E2E testing

declare global {
  namespace Cypress {
    interface Chainable {
      /**
       * Navigate to admin users page
       * @example cy.visitAdminUsers()
       */
      visitAdminUsers(): Chainable<void>;

      /**
       * Navigate to admin roles page
       * @example cy.visitAdminRoles()
       */
      visitAdminRoles(): Chainable<void>;

      /**
       * Navigate to admin settings page
       * @example cy.visitAdminSettings()
       */
      visitAdminSettings(): Chainable<void>;

      /**
       * Create a test user via API
       * @example cy.createTestUser({ email: 'test@example.com', firstName: 'Test', lastName: 'User' })
       */
      createTestUser(userData?: Partial<TestUser>): Chainable<TestUser>;

      /**
       * Create a test role via API
       * @example cy.createTestRole({ name: 'Test Role', permissions: ['users.read'] })
       */
      createTestRole(roleData?: Partial<TestRole>): Chainable<TestRole>;

      /**
       * Set up admin API intercepts for predictable testing
       * @example cy.interceptAdminApi()
       */
      interceptAdminApi(): Chainable<void>;

      /**
       * Start user impersonation
       * @example cy.startImpersonation('user-id-123')
       */
      startImpersonation(userId: string): Chainable<void>;

      /**
       * End user impersonation
       * @example cy.endImpersonation()
       */
      endImpersonation(): Chainable<void>;

      /**
       * Get user table rows
       * @example cy.getUserTableRows()
       */
      getUserTableRows(): Chainable<JQuery<HTMLElement>>;

      /**
       * Get role cards
       * @example cy.getRoleCards()
       */
      getRoleCards(): Chainable<JQuery<HTMLElement>>;

      /**
       * Open create user modal
       * @example cy.openCreateUserModal()
       */
      openCreateUserModal(): Chainable<void>;

      /**
       * Open create role modal
       * @example cy.openCreateRoleModal()
       */
      openCreateRoleModal(): Chainable<void>;

      /**
       * Search users by query
       * @example cy.searchUsers('john@example.com')
       */
      searchUsers(query: string): Chainable<void>;

      /**
       * Filter users by role
       * @example cy.filterUsersByRole('account.manager')
       */
      filterUsersByRole(role: string): Chainable<void>;
    }
  }
}

interface TestUser {
  id: string;
  email: string;
  first_name: string;
  last_name: string;
  roles: string[];
  permissions: string[];
  status: 'active' | 'inactive' | 'pending';
  created_at: string;
}

interface TestRole {
  id: string;
  name: string;
  slug: string;
  description: string;
  permissions: string[];
  user_count: number;
}

// Navigate to admin users page
Cypress.Commands.add('visitAdminUsers', () => {
  cy.visit('/admin/users');
  cy.url().should('include', '/admin/users');
  cy.get('[data-testid="admin-users-page"], .admin-users-container, [class*="users"]', { timeout: 10000 })
    .should('exist');
});

// Navigate to admin roles page
Cypress.Commands.add('visitAdminRoles', () => {
  cy.visit('/admin/roles');
  cy.url().should('include', '/admin/roles');
  cy.get('[data-testid="admin-roles-page"], .admin-roles-container, [class*="roles"]', { timeout: 10000 })
    .should('exist');
});

// Navigate to admin settings page
Cypress.Commands.add('visitAdminSettings', () => {
  cy.visit('/admin/settings');
  cy.url().should('include', '/admin/settings');
  cy.get('[data-testid="admin-settings-page"], .admin-settings-container, [class*="settings"]', { timeout: 10000 })
    .should('exist');
});

// Create test user via API
Cypress.Commands.add('createTestUser', (userData = {}) => {
  const defaultUser: TestUser = {
    id: `user_${Date.now()}`,
    email: `testuser_${Date.now()}@example.com`,
    first_name: 'Test',
    last_name: 'User',
    roles: ['account.member'],
    permissions: ['dashboard.read'],
    status: 'active',
    created_at: new Date().toISOString(),
    ...userData,
  };

  return cy.request({
    method: 'POST',
    url: `${Cypress.env('apiUrl')}/admin/users`,
    headers: {
      Authorization: `Bearer ${window.localStorage.getItem('accessToken')}`,
    },
    body: {
      user: {
        email: defaultUser.email,
        first_name: defaultUser.first_name,
        last_name: defaultUser.last_name,
        password: 'TestPassword123!',
        password_confirmation: 'TestPassword123!',
        role_slugs: defaultUser.roles,
      },
    },
    failOnStatusCode: false,
  }).then((response) => {
    if (response.status === 201 || response.status === 200) {
      return response.body.data;
    }
    return defaultUser;
  });
});

// Create test role via API
Cypress.Commands.add('createTestRole', (roleData = {}) => {
  const defaultRole: TestRole = {
    id: `role_${Date.now()}`,
    name: `Test Role ${Date.now()}`,
    slug: `test-role-${Date.now()}`,
    description: 'A test role for E2E testing',
    permissions: ['dashboard.read', 'users.read'],
    user_count: 0,
    ...roleData,
  };

  return cy.request({
    method: 'POST',
    url: `${Cypress.env('apiUrl')}/roles`,
    headers: {
      Authorization: `Bearer ${window.localStorage.getItem('accessToken')}`,
    },
    body: {
      role: {
        name: defaultRole.name,
        description: defaultRole.description,
        permission_slugs: defaultRole.permissions,
      },
    },
    failOnStatusCode: false,
  }).then((response) => {
    if (response.status === 201 || response.status === 200) {
      return response.body.data;
    }
    return defaultRole;
  });
});

// Set up admin API intercepts
Cypress.Commands.add('interceptAdminApi', () => {
  // Intercept users list
  cy.intercept('GET', '**/api/v1/admin/users**', {
    fixture: 'admin/users.json',
  }).as('usersList');

  // Intercept roles list
  cy.intercept('GET', '**/api/v1/roles**', {
    fixture: 'admin/roles.json',
  }).as('rolesList');

  // Intercept permissions list
  cy.intercept('GET', '**/api/v1/permissions**', {
    fixture: 'admin/permissions.json',
  }).as('permissionsList');

  // Intercept user creation
  cy.intercept('POST', '**/api/v1/admin/users', {
    statusCode: 201,
    body: {
      success: true,
      data: {
        id: 'new-user-123',
        email: 'newuser@example.com',
        first_name: 'New',
        last_name: 'User',
        status: 'active',
      },
    },
  }).as('createUser');

  // Intercept user update
  cy.intercept('PATCH', '**/api/v1/admin/users/*', {
    statusCode: 200,
    body: {
      success: true,
      data: {
        id: 'updated-user-123',
        status: 'active',
      },
    },
  }).as('updateUser');

  // Intercept user deletion
  cy.intercept('DELETE', '**/api/v1/admin/users/*', {
    statusCode: 200,
    body: {
      success: true,
      message: 'User deleted successfully',
    },
  }).as('deleteUser');

  // Intercept role creation
  cy.intercept('POST', '**/api/v1/roles', {
    statusCode: 201,
    body: {
      success: true,
      data: {
        id: 'new-role-123',
        name: 'New Role',
        slug: 'new-role',
      },
    },
  }).as('createRole');

  // Intercept role update
  cy.intercept('PATCH', '**/api/v1/roles/*', {
    statusCode: 200,
    body: {
      success: true,
      data: {
        id: 'updated-role-123',
      },
    },
  }).as('updateRole');

  // Intercept role deletion
  cy.intercept('DELETE', '**/api/v1/roles/*', {
    statusCode: 200,
    body: {
      success: true,
      message: 'Role deleted successfully',
    },
  }).as('deleteRole');

  // Intercept impersonation start
  cy.intercept('POST', '**/api/v1/admin/impersonation', {
    statusCode: 200,
    body: {
      success: true,
      data: {
        token: 'impersonation-token-123',
        impersonated_user: {
          id: 'user-123',
          email: 'impersonated@example.com',
        },
      },
    },
  }).as('startImpersonation');

  // Intercept impersonation end
  cy.intercept('DELETE', '**/api/v1/admin/impersonation', {
    statusCode: 200,
    body: {
      success: true,
      message: 'Impersonation ended',
    },
  }).as('endImpersonation');

  // Intercept email settings
  cy.intercept('GET', '**/api/v1/admin/settings/email**', {
    fixture: 'admin/email-settings.json',
  }).as('emailSettings');

  // Intercept system settings
  cy.intercept('GET', '**/api/v1/admin/settings**', {
    fixture: 'admin/system-settings.json',
  }).as('systemSettings');
});

// Start user impersonation
Cypress.Commands.add('startImpersonation', (userId: string) => {
  cy.request({
    method: 'POST',
    url: `${Cypress.env('apiUrl')}/admin/impersonation`,
    headers: {
      Authorization: `Bearer ${window.localStorage.getItem('accessToken')}`,
    },
    body: { user_id: userId },
    failOnStatusCode: false,
  }).then((response) => {
    if (response.status === 200 && response.body.data?.token) {
      // Store original token
      const originalToken = window.localStorage.getItem('accessToken');
      window.localStorage.setItem('originalAccessToken', originalToken || '');
      // Set impersonation token
      window.localStorage.setItem('accessToken', response.body.data.token);
      window.localStorage.setItem('isImpersonating', 'true');
    }
  });
});

// End user impersonation
Cypress.Commands.add('endImpersonation', () => {
  cy.request({
    method: 'DELETE',
    url: `${Cypress.env('apiUrl')}/admin/impersonation`,
    headers: {
      Authorization: `Bearer ${window.localStorage.getItem('accessToken')}`,
    },
    failOnStatusCode: false,
  }).then(() => {
    // Restore original token
    const originalToken = window.localStorage.getItem('originalAccessToken');
    if (originalToken) {
      window.localStorage.setItem('accessToken', originalToken);
    }
    window.localStorage.removeItem('originalAccessToken');
    window.localStorage.removeItem('isImpersonating');
  });
});

// Get user table rows
Cypress.Commands.add('getUserTableRows', () => {
  return cy.get('[data-testid="users-table"] tbody tr, .users-table tbody tr, table tbody tr');
});

// Get role cards
Cypress.Commands.add('getRoleCards', () => {
  return cy.get('[data-testid="role-card"], .role-card, [class*="role-card"]');
});

// Open create user modal
Cypress.Commands.add('openCreateUserModal', () => {
  cy.get('[data-testid="create-user-btn"], button:contains("Create User"), button:contains("Add User")').click();
  cy.get('[data-testid="create-user-modal"], .modal, [role="dialog"]', { timeout: 5000 })
    .should('be.visible');
});

// Open create role modal
Cypress.Commands.add('openCreateRoleModal', () => {
  cy.get('[data-testid="create-role-btn"], button:contains("Create Role"), button:contains("Add Role")').click();
  cy.get('[data-testid="create-role-modal"], .modal, [role="dialog"]', { timeout: 5000 })
    .should('be.visible');
});

// Search users
Cypress.Commands.add('searchUsers', (query: string) => {
  cy.get('[data-testid="users-search"], input[placeholder*="Search"], input[type="search"]')
    .clear()
    .type(query);
  // Wait for debounced search
  cy.wait(500);
});

// Filter users by role
Cypress.Commands.add('filterUsersByRole', (role: string) => {
  cy.get('[data-testid="role-filter"], select[name="role"], [data-testid="filter-dropdown"]').click();
  cy.get(`[data-testid="role-option-${role}"], option[value="${role}"], li:contains("${role}")`).click();
});

export {};

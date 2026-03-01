/// <reference types="cypress" />

/**
 * Role & Permission Management E2E Tests
 *
 * Simplified tests for role and permission verification
 */

describe('Role & Permission Management', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('User Authentication', () => {
    it('should display authenticated user session', () => {
      cy.assertContainsAny(['Dashboard', 'Welcome']);
      cy.url().should('match', /\/(app|dashboard)/);
    });

    it('should show user information in UI', () => {
      cy.assertHasElement(['[data-testid="user-menu"]', '[class*="avatar"]', '[class*="user"]']);
    });
  });

  describe('Navigation Access', () => {
    it('should display navigation based on permissions', () => {
      cy.get('nav, [role="navigation"], aside, [class*="sidebar"]')
        .should('exist');
    });

    it('should have accessible navigation links', () => {
      cy.get('nav a, aside a, [role="navigation"] a')
        .should('have.length.at.least', 1);
    });

    it('should allow navigation to permitted pages', () => {
      cy.get('nav a, aside a').first().should('be.visible').click();
      cy.waitForPageLoad();
      cy.assertContainsAny(['Dashboard', 'Settings', 'Admin']);
    });
  });

  describe('Dashboard Access', () => {
    it('should display dashboard content', () => {
      cy.visit('/app');
      cy.waitForPageLoad();
      cy.get('main, [role="main"], .main-content, [class*="container"]')
        .should('exist');
    });

    it('should not show error for permitted routes', () => {
      cy.get('body')
        .should('not.contain.text', 'Access Denied')
        .and('not.contain.text', 'Forbidden')
        .and('not.contain.text', '403');
    });
  });

  describe('Settings Access', () => {
    it('should access settings page', () => {
      cy.get('a[href*="settings"], a[href*="profile"], [data-testid="nav-settings"]').first().should('be.visible').click();
      cy.waitForPageLoad();
      cy.url().should('match', /\/(app|dashboard|settings|profile)/);
    });

    it('should display settings content', () => {
      cy.visit('/app/profile');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Profile', 'Settings']);
    });
  });

  describe('User Menu Permissions', () => {
    it('should display user dropdown with options', () => {
      cy.get('[data-testid="user-menu"], button[aria-haspopup="true"], [class*="avatar"], header button').first().should('be.visible').click();
      cy.assertContainsAny(['Settings', 'Profile', 'Sign Out', 'Logout', 'Account']);
    });

    it('should allow accessing profile from user menu', () => {
      cy.get('[data-testid="user-menu"], [class*="avatar"]').first().should('be.visible').click();
      cy.assertContainsAny(['Profile', 'Settings']);
      cy.waitForPageLoad();
    });
  });

  // Note: Plans Access tests moved to separate describe block below (no login required)

  describe('Logout Functionality', () => {
    it('should allow user to logout', () => {
      cy.logout();
    });

    it('should redirect to login after logout', () => {
      // Clear session manually
      cy.clearAppData();
      cy.visit('/app');
      cy.url({ timeout: 5000 }).should('include', '/login');
    });
  });

  describe('Protected Route Access', () => {
    it('should redirect unauthenticated users to login', () => {
      cy.clearAppData();
      cy.visit('/app');
      cy.url({ timeout: 5000 }).should('include', '/login');
    });

    it('should maintain session across page navigation', () => {
      cy.visit('/app');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Dashboard', 'Welcome']);
      cy.url().should('match', /\/(app|dashboard)/);

      // Navigate to another page
      cy.visit('/plans');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Plans', 'Pricing']);

      // Return to app
      cy.visit('/app');
      cy.waitForPageLoad();
      cy.url().should('match', /\/(app|dashboard)/);
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.testErrorHandling('**/api/**/admin/roles*', {
        statusCode: 500,
        visitUrl: '/app/admin/roles',
      });
    });
  });

  describe('Permission Check', () => {
    it('should require admin permissions', () => {
      cy.testPermissionDenied('/app/admin/roles');
    });
  });
});

// Separate describe block for public pages - no login required
describe('Public Plans Access', () => {
  beforeEach(() => {
    // Clear any existing session for public access testing
    cy.clearAppData();
  });

  it('should access plans page', () => {
    cy.visit('/plans');
    cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 5000 })
      .should('have.length.at.least', 1);
  });

  it('should display plan information', () => {
    cy.visit('/plans');
    cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 5000 })
      .first()
      .should('be.visible');
  });
});


export {};

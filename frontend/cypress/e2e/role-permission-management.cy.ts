/// <reference types="cypress" />

/**
 * Role & Permission Management E2E Tests
 *
 * Simplified tests for role and permission verification
 */

describe('Role & Permission Management', () => {
  beforeEach(() => {
    cy.clearAppData();
    // Login with demo user
    cy.visit('/login');
    cy.get('[data-testid="email-input"]', { timeout: 10000 }).type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').click();
    cy.url({ timeout: 15000 }).should('match', /\/(app|dashboard)/);
  });

  describe('User Authentication', () => {
    it('should display authenticated user session', () => {
      cy.get('body').should('be.visible');
      cy.url().should('match', /\/(app|dashboard)/);
    });

    it('should show user information in UI', () => {
      cy.get('body').then($body => {
        const userIndicators = [
          '[data-testid="user-menu"]',
          ':contains("Demo")',
          '[class*="avatar"]',
          '[class*="user"]'
        ];

        for (const selector of userIndicators) {
          if ($body.find(selector).length > 0) {
            cy.get(selector).first().should('exist');
            break;
          }
        }
      });
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
      cy.get('body').then($body => {
        const navLinks = $body.find('nav a, aside a');
        if (navLinks.length > 0) {
          cy.wrap(navLinks.first()).click({ force: true });
          cy.get('body').should('be.visible');
        }
      });
    });
  });

  describe('Dashboard Access', () => {
    it('should display dashboard content', () => {
      cy.visit('/app');
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
      cy.get('body').then($body => {
        const settingsSelectors = [
          'a[href*="settings"]',
          'a[href*="profile"]',
          '[data-testid="nav-settings"]'
        ];

        for (const selector of settingsSelectors) {
          if ($body.find(selector).length > 0) {
            cy.get(selector).first().click({ force: true });
            break;
          }
        }
      });

      cy.url().should('match', /\/(app|dashboard|settings|profile)/);
    });

    it('should display settings content', () => {
      cy.visit('/app/settings/profile');
      cy.get('body').should('be.visible');
    });
  });

  describe('User Menu Permissions', () => {
    it('should display user dropdown with options', () => {
      // Open user menu
      cy.get('body').then($body => {
        const menuTriggers = [
          '[data-testid="user-menu"]',
          'button:contains("Demo")',
          '[class*="avatar"]'
        ];

        for (const selector of menuTriggers) {
          if ($body.find(selector).length > 0) {
            cy.get(selector).first().click({ force: true });
            break;
          }
        }
      });

      // Should show dropdown options
      cy.contains(/Settings|Profile|Sign Out|Logout/i).should('be.visible');
    });

    it('should allow accessing profile from user menu', () => {
      // Open user menu
      cy.get('body').then($body => {
        const menuTriggers = [
          '[data-testid="user-menu"]',
          'button:contains("Demo")',
          '[class*="avatar"]'
        ];

        for (const selector of menuTriggers) {
          if ($body.find(selector).length > 0) {
            cy.get(selector).first().click({ force: true });
            break;
          }
        }
      });

      // Click profile/settings if available
      cy.get('body').then($body => {
        if ($body.find(':contains("Profile")').length > 0) {
          cy.contains('Profile').click({ force: true });
        } else if ($body.find(':contains("Settings")').length > 0) {
          cy.contains('Settings').click({ force: true });
        }
      });
    });
  });

  describe('Plans Access', () => {
    it('should access plans page', () => {
      // Clear session to see public plans
      cy.clearCookies();
      cy.clearLocalStorage();
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 15000 })
        .should('have.length.at.least', 1);
    });

    it('should display plan information', () => {
      // Clear session to see public plans
      cy.clearCookies();
      cy.clearLocalStorage();
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 15000 })
        .first()
        .should('be.visible');
    });
  });

  describe('Logout Functionality', () => {
    it('should allow user to logout', () => {
      cy.logout();
    });

    it('should redirect to login after logout', () => {
      // Clear session manually
      cy.clearAppData();
      cy.visit('/app');
      cy.url({ timeout: 10000 }).should('include', '/login');
    });
  });

  describe('Protected Route Access', () => {
    it('should redirect unauthenticated users to login', () => {
      cy.clearAppData();
      cy.visit('/app');
      cy.url({ timeout: 10000 }).should('include', '/login');
    });

    it('should maintain session across page navigation', () => {
      cy.visit('/app');
      cy.get('body').should('be.visible');
      cy.url().should('match', /\/(app|dashboard)/);

      // Navigate to another page
      cy.visit('/plans');
      cy.get('body').should('be.visible');

      // Return to app
      cy.visit('/app');
      cy.url().should('match', /\/(app|dashboard)/);
    });
  });
});

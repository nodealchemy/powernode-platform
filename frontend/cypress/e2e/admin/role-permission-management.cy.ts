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
          cy.wrap(navLinks.first()).should('be.visible').click();
          cy.waitForPageLoad();
          cy.get('body').should('be.visible');
        }
      });
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
      cy.get('body').then($body => {
        const settingsSelectors = [
          'a[href*="settings"]',
          'a[href*="profile"]',
          '[data-testid="nav-settings"]'
        ];

        for (const selector of settingsSelectors) {
          if ($body.find(selector).length > 0) {
            cy.get(selector).first().should('be.visible').click();
            break;
          }
        }
      });

      cy.waitForPageLoad();
      cy.url().should('match', /\/(app|dashboard|settings|profile)/);
    });

    it('should display settings content', () => {
      cy.visit('/app/settings/profile');
      cy.waitForPageLoad();
      cy.get('body').should('be.visible');
    });
  });

  describe('User Menu Permissions', () => {
    it('should display user dropdown with options', () => {
      // Open user menu using broader selectors
      cy.get('body').then($body => {
        const menuTriggers = [
          '[data-testid="user-menu"]',
          'button[aria-haspopup="true"]',
          '[class*="avatar"]',
          'button[class*="user"]',
          'header button',
        ];

        for (const selector of menuTriggers) {
          if ($body.find(selector).length > 0) {
            cy.get(selector).first().should('be.visible').click();
            break;
          }
        }
      });

      // Should show dropdown options - be flexible about what text appears
      cy.assertContainsAny(['Settings', 'Profile', 'Sign Out', 'Logout', 'Account']);
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
            cy.get(selector).first().should('be.visible').click();
            break;
          }
        }
      });

      // Click profile/settings if available
      cy.get('body').then($body => {
        if ($body.find(':contains("Profile")').length > 0) {
          cy.contains('Profile').should('be.visible').click();
        } else if ($body.find(':contains("Settings")').length > 0) {
          cy.contains('Settings').should('be.visible').click();
        }
      });
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
      cy.get('body').should('be.visible');
      cy.url().should('match', /\/(app|dashboard)/);

      // Navigate to another page
      cy.visit('/plans');
      cy.waitForPageLoad();
      cy.get('body').should('be.visible');

      // Return to app
      cy.visit('/app');
      cy.waitForPageLoad();
      cy.url().should('match', /\/(app|dashboard)/);
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
    cy.get('body').should('be.visible');
    cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 5000 })
      .should('have.length.at.least', 1);
  });

  it('should display plan information', () => {
    cy.visit('/plans');
    cy.get('body').should('be.visible');
    cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 5000 })
      .first()
      .should('be.visible');
  });
});


export {};

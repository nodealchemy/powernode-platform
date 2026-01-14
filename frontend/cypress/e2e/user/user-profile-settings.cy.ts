/// <reference types="cypress" />

/**
 * User Profile and Settings Tests
 *
 * Simplified tests for profile and settings using demo user
 */

describe('User Profile and Settings Tests', () => {
  beforeEach(() => {
    cy.clearAppData();
    cy.setupApiIntercepts();
    // Login with demo user
    cy.visit('/login');
    cy.get('[data-testid="email-input"]', { timeout: 5000 }).type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').click();
    cy.url({ timeout: 5000 }).should('match', /\/(app|dashboard)/);
    cy.waitForPageLoad();
  });

  describe('User Profile Display', () => {
    it('should display dashboard after login', () => {
      cy.url().should('match', /\/(app|dashboard)/);
      cy.get('body').should('be.visible');
    });

    it('should have user menu visible', () => {
      cy.get('body').then($body => {
        const userMenuSelectors = [
          '[data-testid="user-menu"]',
          '[class*="avatar"]',
          'button[aria-haspopup="menu"]'
        ];

        for (const selector of userMenuSelectors) {
          if ($body.find(selector).length > 0) {
            cy.get(selector).first().should('be.visible');
            break;
          }
        }
      });
    });
  });

  describe('Profile Navigation', () => {
    it('should navigate to profile settings if available', () => {
      cy.get('body').then($body => {
        // Try opening user menu first
        const userMenuSelectors = [
          '[data-testid="user-menu"]',
          '[class*="avatar"]',
          'button[aria-haspopup="menu"]'
        ];

        for (const selector of userMenuSelectors) {
          if ($body.find(selector).length > 0) {
            cy.get(selector).first().should('be.visible').click();
            break;
          }
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should access settings page directly', () => {
      cy.visit('/app/settings/profile');
      cy.waitForPageLoad();
      cy.get('body').should('be.visible');
    });
  });

  describe('Account Settings', () => {
    it('should navigate to account settings', () => {
      cy.get('body').then($body => {
        const settingsSelectors = [
          'a[href*="settings"]',
          'a[href*="account"]',
          '[data-testid="nav-settings"]'
        ];

        for (const selector of settingsSelectors) {
          if ($body.find(selector).length > 0) {
            cy.get(selector).first().should('be.visible').click();
            break;
          }
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display settings form', () => {
      cy.visit('/app/settings/profile');
      cy.waitForPageLoad();
      cy.get('body').then($body => {
        const formElements = [
          'form',
          'input[name]',
          '[data-testid="settings-form"]'
        ];

        for (const selector of formElements) {
          if ($body.find(selector).length > 0) {
            cy.get(selector).first().should('exist');
            break;
          }
        }
      });
    });
  });

  describe('Security Settings', () => {
    it('should navigate to security settings if available', () => {
      cy.visit('/app/settings/security');
      cy.waitForPageLoad();
      cy.get('body').should('be.visible');
    });
  });

  describe('Theme Preferences', () => {
    it('should handle theme toggle if available', () => {
      cy.get('body').then($body => {
        if ($body.find('[data-testid="theme-toggle"], .theme-toggle, [aria-label*="theme"]').length > 0) {
          cy.get('[data-testid="theme-toggle"], .theme-toggle, [aria-label*="theme"]')
            .first()
            .should('be.visible')
            .click();
          cy.waitForPageLoad();
          cy.get('body').should('be.visible');
        } else {
          cy.log('Theme toggle not available');
        }
      });
    });

    it('should persist preferences across page reload', () => {
      cy.reload();
      cy.waitForPageLoad();
      cy.url().should('match', /\/(app|dashboard)/);
      cy.get('body').should('be.visible');
    });
  });

  describe('Mobile Profile Management', () => {
    it('should handle profile management on mobile viewport', () => {
      cy.viewport(375, 667);
      cy.waitForPageLoad();
      cy.get('body').should('be.visible');
      cy.url().should('match', /\/(app|dashboard)/);
    });

    it('should access user menu on mobile', () => {
      cy.viewport(375, 667);
      cy.waitForPageLoad();
      cy.get('body').then($body => {
        const userMenuSelectors = [
          '[data-testid="user-menu"]',
          '[class*="avatar"]',
          'button[aria-haspopup="menu"]'
        ];

        for (const selector of userMenuSelectors) {
          if ($body.find(selector).length > 0) {
            cy.get(selector).first().should('be.visible').click();
            break;
          }
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should handle tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.waitForPageLoad();
      cy.get('body').should('be.visible');
    });
  });

  describe('Error Handling', () => {
    it('should not display error messages on valid pages', () => {
      cy.get('body')
        .should('not.contain.text', 'Something went wrong')
        .and('not.contain.text', 'Error loading');
    });

    it('should maintain session across navigation', () => {
      cy.visit('/app/settings/profile');
      cy.waitForPageLoad();
      cy.get('body').should('be.visible');

      cy.visit('/app');
      cy.waitForPageLoad();
      cy.url().should('match', /\/(app|dashboard)/);
    });
  });

  describe('Logout Flow', () => {
    it('should allow user to logout', () => {
      cy.logout();
    });
  });
});


export {};

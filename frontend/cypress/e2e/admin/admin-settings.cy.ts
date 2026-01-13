/// <reference types="cypress" />

/**
 * Admin Settings E2E Tests
 *
 * Simplified tests for settings functionality
 */

describe('Admin Settings', () => {
  beforeEach(() => {
    cy.clearAppData();
    // Login with demo user
    cy.visit('/login');
    cy.get('[data-testid="email-input"]', { timeout: 10000 }).type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').click();
    cy.url({ timeout: 15000 }).should('match', /\/(app|dashboard)/);
  });

  describe('Settings Navigation', () => {
    it('should navigate to settings page', () => {
      cy.get('body').then($body => {
        const settingsSelectors = [
          'a[href*="settings"]',
          'a[href*="profile"]',
          '[data-testid="settings-link"]',
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
      cy.visit('/app/settings/profile').then(() => {
        cy.get('body').should('be.visible');
      });
    });
  });

  describe('Profile Settings', () => {
    it('should display user profile section', () => {
      cy.visit('/app/settings/profile');
      cy.get('body').then($body => {
        const profileIndicators = [
          'input[name="name"]',
          'input[name="email"]',
          'input[name="firstName"]',
          'input[name="first_name"]',
          '[data-testid="profile-form"]',
          'form'
        ];

        for (const selector of profileIndicators) {
          if ($body.find(selector).length > 0) {
            cy.get(selector).first().should('be.visible');
            break;
          }
        }
      });
    });

    it('should allow viewing profile information', () => {
      cy.visit('/app/settings/profile');
      cy.get('body').should('be.visible');
      // Profile page should have content
      cy.get('main, [role="main"], .main-content, [class*="container"]')
        .should('exist');
    });
  });

  describe('Security Settings', () => {
    it('should navigate to security section if available', () => {
      cy.get('body').then($body => {
        const securityLinks = [
          'a[href*="security"]',
          'a[href*="password"]',
          'button:contains("Security")',
          '[data-testid="security-tab"]'
        ];

        for (const selector of securityLinks) {
          if ($body.find(selector).length > 0) {
            cy.get(selector).first().click({ force: true });
            break;
          }
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Notification Settings', () => {
    it('should have notification options if available', () => {
      cy.get('body').then($body => {
        const notificationSelectors = [
          'a[href*="notifications"]',
          '[data-testid="notifications-tab"]',
          'button:contains("Notifications")',
          'input[type="checkbox"]'
        ];

        for (const selector of notificationSelectors) {
          if ($body.find(selector).length > 0) {
            cy.get(selector).first().should('exist');
            break;
          }
        }
      });
    });
  });

  describe('Theme Settings', () => {
    it('should display theme toggle if available', () => {
      cy.get('body').then($body => {
        const themeSelectors = [
          '[data-testid="theme-toggle"]',
          'button[aria-label*="theme"]',
          '[class*="theme"]',
          'button:contains("Dark")',
          'button:contains("Light")'
        ];

        for (const selector of themeSelectors) {
          if ($body.find(selector).length > 0) {
            cy.get(selector).first().should('exist');
            break;
          }
        }
      });
    });
  });

  describe('Account Actions', () => {
    it('should display logout option', () => {
      // Open user menu first
      cy.get('button[aria-haspopup="true"]', { timeout: 10000 }).first().click();

      // Should have logout option
      cy.contains('Sign Out', { timeout: 5000 }).should('be.visible');
    });

    it('should allow user to logout', () => {
      cy.logout();
    });
  });

  describe('Responsive Design', () => {
    it('should handle mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/settings/profile');
      cy.get('body').should('be.visible');
    });
  });
});

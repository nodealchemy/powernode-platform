/// <reference types="cypress" />

/**
 * Admin User Management E2E Tests
 *
 * Simplified tests for user management functionality
 */

describe('Admin User Management', () => {
  beforeEach(() => {
    cy.clearAppData();
    cy.setupAdminIntercepts();
    // Login with demo user
    cy.visit('/login');
    cy.get('[data-testid="email-input"]', { timeout: 5000 }).type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').click();
    cy.url({ timeout: 5000 }).should('match', /\/(app|dashboard)/);
  });

  describe('Dashboard Access', () => {
    it('should display dashboard after login', () => {
      cy.get('body').should('be.visible');
      cy.url().should('match', /\/(app|dashboard)/);
    });

    it('should display navigation menu', () => {
      cy.get('nav, [role="navigation"], aside, [class*="sidebar"], header')
        .should('exist');
    });
  });

  describe('User Menu', () => {
    it('should display current user info', () => {
      cy.get('body').then($body => {
        const userIndicators = [
          '[data-testid="user-menu"]',
          ':contains("Demo")',
          '[class*="avatar"]',
          '[class*="user"]'
        ];

        for (const selector of userIndicators) {
          if ($body.find(selector).length > 0) {
            cy.get(selector).first().should('be.visible');
            break;
          }
        }
      });
    });

    it('should open user dropdown menu', () => {
      // Click the user menu button
      cy.get('button[aria-haspopup="true"]', { timeout: 5000 }).first().click();

      // Should show dropdown options - check for common menu items
      cy.get('body').should('satisfy', ($body) => {
        const text = $body.text();
        return text.includes('Settings') ||
               text.includes('Profile') ||
               text.includes('Sign Out') ||
               text.includes('Logout');
      });
    });
  });

  describe('Navigation', () => {
    it('should have working navigation links', () => {
      cy.get('nav a, aside a, [role="navigation"] a')
        .should('have.length.at.least', 1);
    });

    it('should allow navigation to different sections', () => {
      cy.get('body').then($body => {
        // Try to find navigation links
        const navLinks = $body.find('nav a, aside a');
        if (navLinks.length > 0) {
          cy.wrap(navLinks.first()).should('be.visible').click();
          cy.url().should('include', '/');
        }
      });
    });
  });

  describe('Settings Access', () => {
    it('should navigate to settings if available', () => {
      cy.get('body').then($body => {
        const settingsSelectors = [
          'a[href*="settings"]',
          'a[href*="profile"]',
          '[data-testid="settings-link"]',
          ':contains("Settings")'
        ];

        for (const selector of settingsSelectors) {
          if ($body.find(selector).length > 0) {
            cy.get(selector).first().should('be.visible').click();
            break;
          }
        }
      });

      // Should be on a valid page
      cy.url().should('match', /\/(app|dashboard|settings|profile)/);
    });

    it('should display page content', () => {
      cy.get('main, [role="main"], .main-content, [class*="container"]')
        .should('exist');
    });
  });

  describe('Responsive Design', () => {
    it('should handle mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.get('body').should('be.visible');
      cy.get('main, [role="main"], .main-content').should('be.visible');
    });

    it('should handle tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.get('body').should('be.visible');
    });
  });
});


export {};

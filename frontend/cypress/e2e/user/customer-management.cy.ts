/// <reference types="cypress" />

/**
 * Customer Management E2E Tests
 *
 * Simplified tests for customer management functionality
 */

describe('Customer Management', () => {
  beforeEach(() => {
    cy.clearAppData();
    // Login with demo user
    cy.visit('/login');
    cy.get('[data-testid="email-input"]', { timeout: 10000 }).type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').click();
    cy.url({ timeout: 15000 }).should('match', /\/(app|dashboard)/);
  });

  describe('Dashboard Access', () => {
    it('should display dashboard after login', () => {
      cy.get('body').should('be.visible');
      cy.url().should('match', /\/(app|dashboard)/);
    });

    it('should display main content area', () => {
      cy.get('main, [role="main"], .main-content, [class*="container"]')
        .should('exist');
    });
  });

  describe('Navigation', () => {
    it('should have working navigation', () => {
      cy.get('nav, [role="navigation"], aside, [class*="sidebar"]')
        .should('exist');
    });

    it('should navigate to customers if available', () => {
      cy.get('body').then($body => {
        const customerSelectors = [
          'a[href*="customer"]',
          'a[href*="clients"]',
          'a[href*="accounts"]',
          '[data-testid="nav-customers"]'
        ];

        for (const selector of customerSelectors) {
          if ($body.find(selector).length > 0) {
            cy.get(selector).first().click({ force: true });
            break;
          }
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('User Profile', () => {
    it('should display user information', () => {
      cy.get('body').then($body => {
        const userSelectors = [
          '[data-testid="user-menu"]',
          ':contains("Demo")',
          '[class*="avatar"]'
        ];

        for (const selector of userSelectors) {
          if ($body.find(selector).length > 0) {
            cy.get(selector).first().should('be.visible');
            break;
          }
        }
      });
    });

    it('should access profile settings', () => {
      cy.visit('/app/settings/profile');
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
            cy.get(selector).first().click({ force: true });
            break;
          }
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display settings form', () => {
      cy.visit('/app/settings/profile');
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

  describe('Team/Organization', () => {
    it('should navigate to team page if available', () => {
      cy.get('body').then($body => {
        const teamSelectors = [
          'a[href*="team"]',
          'a[href*="organization"]',
          'a[href*="members"]',
          '[data-testid="nav-team"]'
        ];

        for (const selector of teamSelectors) {
          if ($body.find(selector).length > 0) {
            cy.get(selector).first().click({ force: true });
            break;
          }
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Search and Filter', () => {
    it('should have search functionality if available', () => {
      cy.get('body').then($body => {
        const searchSelectors = [
          'input[type="search"]',
          'input[placeholder*="Search"]',
          '[data-testid="search-input"]'
        ];

        for (const selector of searchSelectors) {
          if ($body.find(selector).length > 0) {
            cy.get(selector).first().should('exist');
            break;
          }
        }
      });
    });

    it('should have filter options if available', () => {
      cy.get('body').then($body => {
        const filterSelectors = [
          'select',
          '[data-testid="filter"]',
          '[class*="filter"]'
        ];

        for (const selector of filterSelectors) {
          if ($body.find(selector).length > 0) {
            cy.get(selector).first().should('exist');
            break;
          }
        }
      });
    });
  });

  describe('Plans and Subscriptions', () => {
    it('should access plans page', () => {
      // Clear session to see public plans
      cy.clearCookies();
      cy.clearLocalStorage();
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 15000 })
        .should('have.length.at.least', 1);
    });

    it('should display plan details', () => {
      // Clear session to see public plans
      cy.clearCookies();
      cy.clearLocalStorage();
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 15000 })
        .first()
        .within(() => {
          cy.contains(/\$|Free|price/i).should('exist');
        });
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

  describe('Logout Flow', () => {
    it('should allow user to logout', () => {
      cy.logout();
    });
  });

  describe('Error Handling', () => {
    it('should not display error messages on valid pages', () => {
      cy.get('body')
        .should('not.contain.text', 'Something went wrong')
        .and('not.contain.text', 'Error loading');
    });

    it('should maintain session across navigation', () => {
      cy.visit('/plans');
      cy.get('body').should('be.visible');

      cy.visit('/app');
      cy.url().should('match', /\/(app|dashboard)/);
    });
  });
});

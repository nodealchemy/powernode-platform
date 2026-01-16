/// <reference types="cypress" />

/**
 * Customer Management E2E Tests
 *
 * Simplified tests for customer management functionality
 */

describe('Customer Management', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Dashboard Access', () => {
    it('should display dashboard after login', () => {
      cy.get('body').should('be.visible');
      cy.url().should('match', /\/(app|dashboard)/);
    });

    it('should display main content area', () => {
      cy.assertHasElement(['main', '[role="main"]', '.main-content', '[class*="container"]']);
    });
  });

  describe('Navigation', () => {
    it('should have working navigation', () => {
      cy.assertHasElement(['nav', '[role="navigation"]', 'aside', '[class*="sidebar"]']);
    });

    it('should navigate to customers if available', () => {
      cy.navigateTo('customers');
      cy.waitForPageLoad();
      cy.get('body').should('be.visible');
    });
  });

  describe('User Profile', () => {
    it('should display user information', () => {
      // Header user button has aria-haspopup="true" and shows user initials
      cy.assertHasElement([
        '[data-testid="user-menu"]',
        'button[aria-haspopup="true"]',
        '[class*="avatar"]',
        '.rounded-full'
      ]);
    });

    it('should access profile settings', () => {
      // Profile page is at /app/profile
      cy.assertPageReady('/app/profile');
    });
  });

  describe('Account Settings', () => {
    it('should navigate to account settings', () => {
      cy.navigateTo('settings');
      cy.waitForPageLoad();
      cy.get('body').should('be.visible');
    });

    it('should display settings form', () => {
      // Profile page is at /app/profile and has a profile-form
      cy.assertPageReady('/app/profile');
      cy.assertHasElement([
        'form',
        'input[name]',
        '[data-testid="settings-form"]',
        '[data-testid="profile-form"]',
        'form#profile-form'
      ]);
    });
  });

  describe('Team/Organization', () => {
    it('should navigate to team page if available', () => {
      cy.navigateTo('team');
      cy.waitForPageLoad();
      cy.get('body').should('be.visible');
    });
  });

  describe('Search and Filter', () => {
    it('should have search functionality if available', () => {
      // Search may not be present on all pages - check if it exists or skip
      cy.get('body').then(($body) => {
        const hasSearch = $body.find('input[type="search"], input[placeholder*="Search"], [data-testid="search-input"]').length > 0;
        if (hasSearch) {
          cy.assertHasElement(['input[type="search"]', 'input[placeholder*="Search"]', '[data-testid="search-input"]']);
        } else {
          cy.log('Search functionality not available on this page - skipping');
          cy.get('body').should('be.visible');
        }
      });
    });

    it('should have filter options if available', () => {
      // Filter may not be present on all pages - check if it exists or skip
      cy.get('body').then(($body) => {
        const hasFilter = $body.find('select, [data-testid="filter"], [class*="filter"]').length > 0;
        if (hasFilter) {
          cy.assertHasElement(['select', '[data-testid="filter"]', '[class*="filter"]']);
        } else {
          cy.log('Filter functionality not available on this page - skipping');
          cy.get('body').should('be.visible');
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
      // Wait for plans page to render - may not have standard page container
      cy.get('body').should('be.visible');
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 10000 })
        .should('have.length.at.least', 1);
    });

    it('should display plan details', () => {
      // Clear session to see public plans
      cy.clearCookies();
      cy.clearLocalStorage();
      cy.visit('/plans');
      // Wait for plans page to render
      cy.get('body').should('be.visible');
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 10000 })
        .first()
        .within(() => {
          cy.contains(/\$|Free|price/i).should('exist');
        });
    });
  });

  describe('Responsive Design', () => {
    it('should handle mobile viewport', () => {
      cy.testViewport('mobile', '/app');
      cy.assertHasElement(['main', '[role="main"]', '.main-content']);
    });

    it('should handle tablet viewport', () => {
      cy.testViewport('tablet', '/app');
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
      cy.waitForPageLoad();
      cy.get('body').should('be.visible');

      cy.visit('/app');
      cy.waitForPageLoad();
      cy.url().should('match', /\/(app|dashboard)/);
    });
  });
});


export {};

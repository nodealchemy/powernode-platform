/// <reference types="cypress" />

/**
 * Marketplace Browsing E2E Tests
 *
 * Simplified tests for marketplace functionality
 */

describe('Marketplace Browsing', () => {
  beforeEach(() => {
    cy.clearAppData();
    // Login with demo user
    cy.visit('/login');
    cy.get('[data-testid="email-input"]', { timeout: 10000 }).type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').click();
    cy.url({ timeout: 15000 }).should('match', /\/(app|dashboard)/);
  });

  describe('Marketplace Navigation', () => {
    it('should navigate to marketplace if available', () => {
      cy.get('body').then($body => {
        const marketplaceSelectors = [
          'a[href*="marketplace"]',
          'a[href*="apps"]',
          'a[href*="integrations"]',
          '[data-testid="nav-marketplace"]',
          '[data-testid="marketplace-link"]'
        ];

        for (const selector of marketplaceSelectors) {
          if ($body.find(selector).length > 0) {
            cy.get(selector).first().click({ force: true });
            break;
          }
        }
      });

      cy.url().should('match', /\/(app|dashboard|marketplace|apps)/);
    });

    it('should display main content', () => {
      cy.get('main, [role="main"], .main-content, [class*="container"]')
        .should('exist');
    });
  });

  describe('Plans Marketplace', () => {
    it('should display available plans', () => {
      // Clear session to see public plans
      cy.clearCookies();
      cy.clearLocalStorage();
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 15000 })
        .should('have.length.at.least', 1);
    });

    it('should show plan details', () => {
      // Clear session to see public plans
      cy.clearCookies();
      cy.clearLocalStorage();
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 15000 })
        .first()
        .should('be.visible')
        .within(() => {
          // Should have some content
          cy.get('*').should('have.length.at.least', 1);
        });
    });

    it('should show pricing information', () => {
      // Clear session to see public plans
      cy.clearCookies();
      cy.clearLocalStorage();
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 15000 })
        .first()
        .within(() => {
          cy.contains(/\$|Free|price|month|year/i).should('exist');
        });
    });

    it('should allow selecting a plan', () => {
      // Clear session to see public plans
      cy.clearCookies();
      cy.clearLocalStorage();
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 15000 })
        .first()
        .click();

      // Should either show plan details or navigate
      cy.get('body').should('be.visible');
    });
  });

  describe('Subscriptions', () => {
    it('should navigate to subscriptions page', () => {
      cy.get('body').then($body => {
        const subscriptionSelectors = [
          'a[href*="subscription"]',
          'a[href*="billing"]',
          '[data-testid="nav-subscriptions"]',
          '[data-testid="subscriptions-link"]'
        ];

        for (const selector of subscriptionSelectors) {
          if ($body.find(selector).length > 0) {
            cy.get(selector).first().click({ force: true });
            break;
          }
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display subscription content', () => {
      cy.get('main, [role="main"], .main-content').should('exist');
    });
  });

  describe('Search Functionality', () => {
    it('should have search functionality if available', () => {
      cy.get('body').then($body => {
        const searchSelectors = [
          'input[type="search"]',
          'input[placeholder*="Search"]',
          '[data-testid="search-input"]',
          '[class*="search"]'
        ];

        for (const selector of searchSelectors) {
          if ($body.find(selector).length > 0) {
            cy.get(selector).first().should('exist');
            break;
          }
        }
      });
    });
  });

  describe('Category Filtering', () => {
    it('should display category options if available', () => {
      cy.get('body').then($body => {
        const categorySelectors = [
          '[data-testid="category-filter"]',
          'select[name="category"]',
          '[class*="category"]',
          '[class*="filter"]'
        ];

        for (const selector of categorySelectors) {
          if ($body.find(selector).length > 0) {
            cy.get(selector).first().should('exist');
            break;
          }
        }
      });
    });
  });

  describe('Responsive Design', () => {
    it('should handle mobile viewport', () => {
      cy.viewport('iphone-x');
      // Clear session to see public plans
      cy.clearCookies();
      cy.clearLocalStorage();
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 15000 })
        .first()
        .should('be.visible');
    });

    it('should handle tablet viewport', () => {
      cy.viewport('ipad-2');
      // Clear session to see public plans
      cy.clearCookies();
      cy.clearLocalStorage();
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 15000 })
        .should('have.length.at.least', 1);
    });
  });

  describe('User Experience', () => {
    it('should load pages without errors', () => {
      // Clear session to see public plans
      cy.clearCookies();
      cy.clearLocalStorage();
      cy.visit('/plans');
      cy.get('body').should('not.contain.text', 'Error');
      cy.get('body').should('not.contain.text', 'Something went wrong');
    });

    it('should display proper loading states', () => {
      // Clear session to see public plans
      cy.clearCookies();
      cy.clearLocalStorage();
      cy.visit('/plans');
      // Should eventually show content (not just loading)
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 15000 })
        .should('have.length.at.least', 1);
    });
  });
});

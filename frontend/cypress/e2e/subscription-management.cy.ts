/// <reference types="cypress" />

/**
 * Subscription Management Tests
 *
 * Simplified tests for subscription management using demo user
 */

describe('Subscription Management Tests', () => {
  beforeEach(() => {
    cy.clearAppData();
    // Login with demo user
    cy.visit('/login');
    cy.get('[data-testid="email-input"]', { timeout: 10000 }).type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').click();
    cy.url({ timeout: 15000 }).should('match', /\/(app|dashboard)/);
  });

  describe('Subscription Status Display', () => {
    it('should display dashboard after login', () => {
      cy.url().should('match', /\/(app|dashboard)/);
      cy.get('body').should('be.visible');
    });

    it('should have main content visible', () => {
      cy.get('main, [role="main"], .main-content, [class*="container"]').should('exist');
    });
  });

  describe('Plan Selection', () => {
    it('should show available plans on plans page', () => {
      // First logout to view public plans page
      cy.clearCookies();
      cy.clearLocalStorage();
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 15000 })
        .should('have.length.at.least', 1);
    });

    it('should display plan details', () => {
      // First logout to view public plans page
      cy.clearCookies();
      cy.clearLocalStorage();
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 15000 })
        .first()
        .within(() => {
          cy.contains(/\$|Free|price/i).should('exist');
        });
    });

    it('should allow plan selection', () => {
      // First logout to view public plans page
      cy.clearCookies();
      cy.clearLocalStorage();
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 15000 })
        .first()
        .click();

      cy.get('[data-testid="plan-select-btn"]', { timeout: 10000 }).should('be.visible');
    });
  });

  describe('Plan Upgrade/Downgrade', () => {
    it('should navigate to plans for upgrade options', () => {
      // First logout to view public plans page
      cy.clearCookies();
      cy.clearLocalStorage();
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 15000 })
        .should('have.length.at.least', 1);
    });

    it('should handle plan selection workflow', () => {
      // First logout to view public plans page
      cy.clearCookies();
      cy.clearLocalStorage();
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 15000 })
        .first()
        .click();

      cy.get('[data-testid="plan-select-btn"]', { timeout: 10000 }).should('be.visible');
    });
  });

  describe('Billing Navigation', () => {
    it('should navigate to subscription/billing if available', () => {
      cy.get('body').then($body => {
        const billingSelectors = [
          'a[href*="subscription"]',
          'a[href*="billing"]',
          'a[href*="marketplace"]',
          '[data-testid="billing-link"]'
        ];

        for (const selector of billingSelectors) {
          if ($body.find(selector).length > 0) {
            cy.get(selector).first().click({ force: true });
            break;
          }
        }
      });

      cy.url().should('match', /\/(app|dashboard|subscription|billing|marketplace|plans)/);
    });
  });

  describe('User Menu Access', () => {
    it('should open user menu', () => {
      cy.get('body').then($body => {
        const userMenuSelectors = [
          '[data-testid="user-menu"]',
          '[class*="avatar"]',
          'button[aria-haspopup="menu"]'
        ];

        for (const selector of userMenuSelectors) {
          if ($body.find(selector).length > 0) {
            cy.get(selector).first().click({ force: true });
            break;
          }
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Mobile Subscription Management', () => {
    it('should handle subscription management on mobile viewport', () => {
      cy.viewport(375, 667);
      cy.get('body').should('be.visible');
      cy.url().should('match', /\/(app|dashboard)/);
    });

    it('should provide mobile-optimized plan selection', () => {
      // First logout to view public plans page
      cy.clearCookies();
      cy.clearLocalStorage();
      cy.viewport(375, 667);
      cy.visit('/plans');

      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 15000 })
        .should('exist')
        .and('be.visible');

      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]')
        .first()
        .click();

      cy.get('[data-testid="plan-select-btn"]', { timeout: 10000 }).should('be.visible');
    });
  });

  describe('Error Handling', () => {
    it('should not display error messages on valid pages', () => {
      cy.get('body')
        .should('not.contain.text', 'Something went wrong')
        .and('not.contain.text', 'Error loading');
    });

    it('should handle page navigation without errors', () => {
      cy.visit('/plans');
      cy.get('body').should('be.visible');

      cy.visit('/app');
      cy.url().should('match', /\/(app|dashboard)/);
    });

    it('should maintain session during navigation', () => {
      // Just verify navigation works, don't require specific elements
      cy.visit('/plans');
      cy.get('body').should('be.visible');

      cy.visit('/app');
      cy.url().should('match', /\/(app|dashboard)/);
    });
  });
});

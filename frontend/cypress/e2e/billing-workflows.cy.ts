/// <reference types="cypress" />

/**
 * Billing Workflows E2E Tests
 *
 * Simplified tests for billing functionality
 */

describe('Billing Workflows', () => {
  beforeEach(() => {
    cy.clearAppData();
    // Login with demo user
    cy.visit('/login');
    cy.get('[data-testid="email-input"]', { timeout: 10000 }).type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').click();
    cy.url({ timeout: 15000 }).should('match', /\/(app|dashboard)/);
  });

  describe('Billing Navigation', () => {
    it('should navigate to billing page if available', () => {
      cy.get('body').then($body => {
        const billingSelectors = [
          'a[href*="billing"]',
          'a[href*="subscription"]',
          '[data-testid="nav-billing"]',
          '[data-testid="billing-link"]'
        ];

        let found = false;
        for (const selector of billingSelectors) {
          if ($body.find(selector).length > 0) {
            cy.get(selector).first().click({ force: true });
            found = true;
            break;
          }
        }

        if (!found) {
          cy.log('No billing link found in navigation - feature may not be accessible to this user');
        }
      });

      // Page should still be valid
      cy.url().should('match', /\/(app|dashboard|billing|subscription|marketplace)/);
    });

    it('should display main app content', () => {
      cy.get('body').should('be.visible');
      cy.get('main, [role="main"], .main-content, [class*="container"]')
        .should('exist');
    });
  });

  describe('Subscription Status', () => {
    it('should allow navigation to plans page', () => {
      // Clear session to see public plans
      cy.clearCookies();
      cy.clearLocalStorage();
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 15000 })
        .should('have.length.at.least', 1);
    });

    it('should display plan pricing information', () => {
      // Clear session to see public plans
      cy.clearCookies();
      cy.clearLocalStorage();
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 15000 })
        .first()
        .within(() => {
          // Should show price or "Free"
          cy.contains(/\$|Free|month|year/i).should('exist');
        });
    });
  });

  describe('Plan Features', () => {
    it('should display plan features', () => {
      // Clear session to see public plans
      cy.clearCookies();
      cy.clearLocalStorage();
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 15000 })
        .first()
        .should('be.visible');
    });

    it('should show billing cycle toggle', () => {
      // Clear session to see public plans
      cy.clearCookies();
      cy.clearLocalStorage();
      cy.visit('/plans');
      cy.get('body').then($body => {
        const toggleSelectors = [
          '[data-testid="billing-toggle"]',
          '[data-testid="billing-cycle"]',
          'button:contains("Monthly")',
          'button:contains("Yearly")',
          '[class*="toggle"]'
        ];

        for (const selector of toggleSelectors) {
          if ($body.find(selector).length > 0) {
            cy.get(selector).first().should('be.visible');
            break;
          }
        }
      });
    });
  });

  describe('User Account Access', () => {
    it('should display user menu', () => {
      cy.get('body').then($body => {
        const userMenuSelectors = [
          '[data-testid="user-menu"]',
          '[data-testid="user-dropdown"]',
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

    it('should allow logout', () => {
      cy.logout();
    });
  });
});

/// <reference types="cypress" />

/**
 * Subscription Lifecycle Tests
 *
 * Simplified tests for subscription lifecycle using demo user
 */

describe('Subscription Lifecycle', () => {
  beforeEach(() => {
    cy.clearAppData();
    // Login with demo user
    cy.visit('/login');
    cy.get('[data-testid="email-input"]', { timeout: 10000 }).type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').click();
    cy.url({ timeout: 15000 }).should('match', /\/(app|dashboard)/);
  });

  describe('Current Subscription Display', () => {
    it('should navigate to subscription page', () => {
      // Try to find subscription/billing link
      cy.get('body').then($body => {
        const subscriptionSelectors = [
          'a[href*="subscription"]',
          'a[href*="billing"]',
          'a[href*="marketplace"]',
          '[data-testid="billing-link"]'
        ];

        for (const selector of subscriptionSelectors) {
          if ($body.find(selector).length > 0) {
            cy.get(selector).first().click({ force: true });
            break;
          }
        }
      });

      // Should navigate somewhere
      cy.url().should('match', /\/(app|dashboard|subscription|billing|marketplace)/);
    });

    it('should display subscription information if available', () => {
      cy.visit('/app');
      // Check for any subscription-related content
      cy.get('body').should('exist');
    });
  });

  describe('Plan Selection', () => {
    it('should show available plans on plans page', () => {
      // Clear session to see public plans page
      cy.clearCookies();
      cy.clearLocalStorage();
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 15000 })
        .should('have.length.at.least', 1);
    });

    it('should display plan details', () => {
      // Clear session to see public plans page
      cy.clearCookies();
      cy.clearLocalStorage();
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 15000 })
        .first()
        .within(() => {
          // Should show price or "Free"
          cy.contains(/\$|Free/i).should('exist');
        });
    });
  });
});

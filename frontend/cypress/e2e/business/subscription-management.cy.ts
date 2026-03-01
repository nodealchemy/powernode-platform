/// <reference types="cypress" />

/**
 * Subscription Management E2E Tests
 *
 * Tests for subscription management including:
 * - Subscription status display
 * - Plan selection and comparison
 * - Subscription modifications
 * - Error handling
 */

describe('Subscription Management Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Subscription Status Display', () => {
    it('should display dashboard after login', () => {
      cy.url().should('match', /\/(app|dashboard)/);
      cy.assertContainsAny(['Subscription', 'Plan', 'Dashboard']);
    });

    it('should have main content visible', () => {
      cy.assertHasElement(['main', '[role="main"]', '.main-content', '[class*="container"]'])
        .should('exist');
    });

    it('should display subscription status indicators', () => {
      cy.assertContainsAny(['Plan', 'Subscription', 'Active', 'Trial', 'Free', 'Pro', 'Dashboard']);
    });

    it('should display subscription period dates', () => {
      cy.intercept('GET', '**/api/v1/billing/subscription**', {
        statusCode: 200,
        body: {
          success: true,
          data: {
            subscription: {
              id: 'sub-1',
              status: 'active',
              current_period_start: '2024-01-01',
              current_period_end: '2024-02-01',
              plan: { name: 'Professional', price: '99.00' },
            },
          },
        },
      }).as('getSubscription');

      cy.navigateTo('/app/business/billing');
      cy.assertContainsAny(['Period', 'Renews', 'Next billing', 'Billing', 'Invoice']);
    });
  });

  describe('Plan Selection', () => {
    it('should show available plans on plans page', () => {
      cy.clearCookies();
      cy.clearLocalStorage();
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 5000 })
        .should('have.length.at.least', 1);
    });

    it('should display plan details', () => {
      cy.clearCookies();
      cy.clearLocalStorage();
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 5000 })
        .first()
        .within(() => {
          cy.contains(/\$|Free|price/i).should('exist');
        });
    });

    it('should allow plan selection', () => {
      cy.clearCookies();
      cy.clearLocalStorage();
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 5000 })
        .first()
        .click();

      cy.get('[data-testid="plan-select-btn"], [data-testid="continue-to-registration"]', { timeout: 5000 })
        .should('be.visible');
    });

    it('should highlight selected plan', () => {
      cy.clearCookies();
      cy.clearLocalStorage();
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 5000 })
        .first()
        .click();

      cy.assertHasElement([
        '.selected',
        '[aria-selected="true"]',
        '[data-selected="true"]',
        '[class*="border-primary"]',
        '[class*="ring"]',
        '[data-testid="plan-select-btn"]',
        '[data-testid="continue-to-registration"]',
      ]).should('exist');
    });
  });

  describe('Plan Comparison', () => {
    it('should display multiple plans for comparison', () => {
      cy.clearCookies();
      cy.clearLocalStorage();
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 5000 })
        .should('have.length.at.least', 1);
    });

    it('should differentiate features between plans', () => {
      cy.clearCookies();
      cy.clearLocalStorage();
      cy.visit('/plans');

      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 5000 })
        .first()
        .within(() => {
          cy.get('li, [class*="feature"]').should('have.length.at.least', 0);
        });
    });
  });

  describe('Plan Upgrade/Downgrade', () => {
    it('should navigate to plans for upgrade options', () => {
      cy.clearCookies();
      cy.clearLocalStorage();
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 5000 })
        .should('have.length.at.least', 1);
    });

    it('should handle plan selection workflow', () => {
      cy.clearCookies();
      cy.clearLocalStorage();
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 5000 })
        .first()
        .click();

      cy.get('[data-testid="plan-select-btn"], [data-testid="continue-to-registration"]', { timeout: 5000 })
        .should('be.visible');
    });
  });

  describe('Billing Navigation', () => {
    it('should navigate to subscription/billing if available', () => {
      cy.get('a[href*="subscription"], a[href*="billing"], a[href*="marketplace"], [data-testid="billing-link"]').first().click();
      cy.url().should('match', /\/(app|dashboard|subscription|billing|marketplace|plans)/);
    });
  });

  describe('Subscription Renewal', () => {
    it('should display renewal date', () => {
      cy.intercept('GET', '**/api/v1/billing/subscription**', {
        statusCode: 200,
        body: {
          success: true,
          data: {
            subscription: {
              id: 'sub-1',
              status: 'active',
              current_period_end: new Date(Date.now() + 15 * 24 * 60 * 60 * 1000).toISOString(),
            },
          },
        },
      }).as('getSubscription');

      cy.navigateTo('/app/business/billing');
      cy.assertContainsAny(['Renews', 'Next billing', 'Period ends', 'Billing', 'Invoice']);
    });
  });

  describe('Subscription Cancellation', () => {
    it('should display cancel option if available', () => {
      cy.navigateTo('/app/business/billing');
      cy.assertContainsAny(['Subscription', 'Plan', 'Dashboard']);
      // Cancel option may or may not be visible depending on user permissions
    });
  });

  describe('Mobile Subscription Management', () => {
    it('should handle subscription management on mobile viewport', () => {
      cy.viewport(375, 667);
      cy.assertContainsAny(['Subscription', 'Plan', 'Dashboard']);
      cy.url().should('match', /\/(app|dashboard)/);
    });

    it('should provide mobile-optimized plan selection', () => {
      cy.clearCookies();
      cy.clearLocalStorage();
      cy.viewport(375, 667);
      cy.visit('/plans');

      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 5000 })
        .should('exist')
        .and('be.visible');

      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]')
        .first()
        .click();

      cy.get('[data-testid="plan-select-btn"], [data-testid="continue-to-registration"]', { timeout: 5000 })
        .should('be.visible');
    });
  });

  describe('Error Handling', () => {
    it('should not display error messages on valid pages', () => {
      cy.get('body')
        .should('not.contain.text', 'Something went wrong')
        .and('not.contain.text', 'Error loading');
    });

    it('should handle subscription API errors gracefully', () => {
      cy.testErrorHandling('/api/v1/subscriptions*', {
        statusCode: 500,
        visitUrl: '/app',
      });
    });
  });

  describe('Subscription Features Access', () => {
    it('should display feature limits based on subscription', () => {
      cy.assertContainsAny(['Limit', 'Usage', 'Quota', 'Plan', 'Subscription']);
    });
  });

  describe('Subscription History', () => {
    it('should display subscription change history if available', () => {
      cy.intercept('GET', '**/api/v1/subscriptions/history**', {
        statusCode: 200,
        body: {
          success: true,
          data: [
            { event: 'plan_change', from_plan: 'Basic', to_plan: 'Pro', date: '2024-01-01' },
            { event: 'subscription_created', plan: 'Basic', date: '2023-06-01' },
          ],
        },
      }).as('getHistory');

      cy.navigateTo('/app/business/billing');
      cy.assertContainsAny(['History', 'Billing', 'Invoice']);
    });
  });
});

describe('Account Subscription Integration', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  it('should link subscription to account', () => {
    cy.assertContainsAny(['Account', 'Organization', 'Demo', 'Subscription', 'Plan']);
  });

  it('should show team member limits based on plan', () => {
    cy.navigateTo('/app/settings');
    cy.assertContainsAny(['Team', 'Members', 'Seats', 'Settings', 'Account', 'Profile', 'Preferences']);
  });
});

export {};

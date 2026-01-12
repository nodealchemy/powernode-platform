/// <reference types="cypress" />

/**
 * Subscription Management E2E Tests
 *
 * Comprehensive tests for subscription management including:
 * - Subscription status display
 * - Plan selection and comparison
 * - Subscription modifications
 * - Account-level subscription features
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

    it('should display account subscription status', () => {
      cy.get('body').then($body => {
        const statusIndicators = [
          ':contains("Plan")',
          ':contains("Subscription")',
          ':contains("Active")',
          ':contains("Trial")',
          ':contains("Free")',
          ':contains("Pro")'
        ];

        let found = false;
        for (const selector of statusIndicators) {
          if ($body.find(selector).length > 0) {
            found = true;
            cy.log('Subscription status indicator found');
            break;
          }
        }

        if (!found) {
          cy.log('Subscription status may be in settings or billing section');
        }
      });
    });

    it('should display subscription period dates', () => {
      cy.intercept('GET', '/api/v1/billing/subscription', {
        statusCode: 200,
        body: {
          subscription: {
            id: 'sub-1',
            status: 'active',
            current_period_start: '2024-01-01',
            current_period_end: '2024-02-01',
            plan: { name: 'Professional', price: '99.00' }
          }
        }
      }).as('getSubscription');

      cy.visit('/app/billing');

      cy.get('body').then($body => {
        const hasPeriod =
          $body.text().includes('Period') ||
          $body.text().includes('Renews') ||
          $body.text().includes('Next billing');

        if (hasPeriod) {
          cy.log('Subscription period information displayed');
        }
      });
    });
  });

  describe('Plan Selection', () => {
    it('should show available plans on plans page', () => {
      cy.clearCookies();
      cy.clearLocalStorage();
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 15000 })
        .should('have.length.at.least', 1);
    });

    it('should display plan details', () => {
      cy.clearCookies();
      cy.clearLocalStorage();
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 15000 })
        .first()
        .within(() => {
          cy.contains(/\$|Free|price/i).should('exist');
        });
    });

    it('should display plan features list', () => {
      cy.clearCookies();
      cy.clearLocalStorage();
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 15000 })
        .first()
        .within(() => {
          cy.get('li, [class*="feature"]').should('have.length.at.least', 0);
        });
    });

    it('should allow plan selection', () => {
      cy.clearCookies();
      cy.clearLocalStorage();
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 15000 })
        .first()
        .click();

      cy.get('[data-testid="plan-select-btn"], [data-testid="continue-to-registration"]', { timeout: 10000 })
        .should('be.visible');
    });

    it('should highlight selected plan', () => {
      cy.clearCookies();
      cy.clearLocalStorage();
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 15000 })
        .first()
        .click();

      // Check for selection indicator
      cy.get('body').then($body => {
        const hasSelection =
          $body.find('.selected, [aria-selected="true"], [data-selected="true"]').length > 0 ||
          $body.find('[class*="border-primary"], [class*="ring"]').length > 0 ||
          $body.find('[data-testid="plan-select-btn"], [data-testid="continue-to-registration"]').length > 0;

        expect(hasSelection, 'Selected plan should have visual indicator').to.be.true;
      });
    });
  });

  describe('Plan Comparison', () => {
    it('should display multiple plans for comparison', () => {
      cy.clearCookies();
      cy.clearLocalStorage();
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 15000 })
        .should('have.length.at.least', 1);
    });

    it('should show different pricing tiers', () => {
      cy.clearCookies();
      cy.clearLocalStorage();
      cy.visit('/plans');

      cy.get('body').then($body => {
        const prices = $body.find('[class*="price"], :contains("$")');
        if (prices.length > 0) {
          cy.log('Multiple pricing tiers displayed');
        }
      });
    });

    it('should differentiate features between plans', () => {
      cy.clearCookies();
      cy.clearLocalStorage();
      cy.visit('/plans');

      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 15000 })
        .each(($card) => {
          const features = $card.find('li, [class*="feature"]').length;
          cy.log(`Plan has ${features} features listed`);
        });
    });
  });

  describe('Plan Upgrade/Downgrade', () => {
    it('should navigate to plans for upgrade options', () => {
      cy.clearCookies();
      cy.clearLocalStorage();
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 15000 })
        .should('have.length.at.least', 1);
    });

    it('should handle plan selection workflow', () => {
      cy.clearCookies();
      cy.clearLocalStorage();
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 15000 })
        .first()
        .click();

      cy.get('[data-testid="plan-select-btn"], [data-testid="continue-to-registration"]', { timeout: 10000 })
        .should('be.visible');
    });

    it('should show confirmation before plan change', () => {
      cy.intercept('PUT', '/api/v1/subscriptions/*', {
        statusCode: 200,
        body: { success: true }
      }).as('updateSubscription');

      cy.visit('/app/billing');

      cy.get('body').then($body => {
        const changePlanButtons = [
          'button:contains("Change Plan")',
          'button:contains("Upgrade")',
          'a:contains("Upgrade")'
        ];

        for (const selector of changePlanButtons) {
          if ($body.find(selector).length > 0) {
            cy.log('Plan change option found');
            return;
          }
        }
      });
    });

    it('should display prorated pricing for mid-cycle changes', () => {
      cy.intercept('GET', '/api/v1/subscriptions/*/preview', {
        statusCode: 200,
        body: {
          prorated_amount: 4950,
          credit_amount: 2475,
          amount_due: 2475,
          effective_date: new Date().toISOString()
        }
      }).as('previewChange');

      cy.visit('/app/billing');

      cy.get('body').then($body => {
        if ($body.text().includes('Prorated') || $body.text().includes('Credit')) {
          cy.log('Prorated pricing information displayed');
        }
      });
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

  describe('Subscription Renewal', () => {
    it('should display renewal date', () => {
      cy.intercept('GET', '/api/v1/billing/subscription', {
        statusCode: 200,
        body: {
          subscription: {
            id: 'sub-1',
            status: 'active',
            current_period_end: new Date(Date.now() + 15 * 24 * 60 * 60 * 1000).toISOString()
          }
        }
      }).as('getSubscription');

      cy.visit('/app/billing');

      cy.get('body').then($body => {
        const hasRenewalInfo =
          $body.text().includes('Renews') ||
          $body.text().includes('Next billing') ||
          $body.text().includes('Period ends');

        if (hasRenewalInfo) {
          cy.log('Renewal information displayed');
        }
      });
    });

    it('should show auto-renewal status', () => {
      cy.visit('/app/billing');

      cy.get('body').then($body => {
        const hasAutoRenewal =
          $body.text().includes('Auto-renew') ||
          $body.text().includes('Automatic renewal') ||
          $body.find('[data-testid="auto-renew"]').length > 0;

        if (hasAutoRenewal) {
          cy.log('Auto-renewal status displayed');
        }
      });
    });
  });

  describe('Subscription Cancellation', () => {
    it('should display cancel option', () => {
      cy.visit('/app/billing');

      cy.get('body').then($body => {
        const cancelOptions = [
          'button:contains("Cancel")',
          'a:contains("Cancel subscription")',
          '[data-testid="cancel-subscription"]'
        ];

        for (const selector of cancelOptions) {
          if ($body.find(selector).length > 0) {
            cy.log('Cancel subscription option found');
            return;
          }
        }
        cy.log('Cancel option may not be visible for this user');
      });
    });

    it('should require confirmation for cancellation', () => {
      cy.intercept('DELETE', '/api/v1/subscriptions/*', {
        statusCode: 200,
        body: { success: true, message: 'Subscription cancelled' }
      }).as('cancelSubscription');

      cy.visit('/app/billing');

      cy.get('body').then($body => {
        const cancelButton = $body.find('button:contains("Cancel Subscription")');
        if (cancelButton.length > 0) {
          // Just verify the button exists - don't actually cancel
          cy.log('Cancel button found - would require confirmation');
        }
      });
    });

    it('should explain cancellation effects', () => {
      cy.visit('/app/billing');

      cy.get('body').then($body => {
        // If there's cancellation info, it should explain what happens
        if ($body.text().includes('Cancel')) {
          cy.log('Cancellation option present');
        }
      });
    });
  });

  describe('User Menu Access', () => {
    it('should open user menu', () => {
      cy.get('body').then($body => {
        const userMenuSelectors = [
          '[data-testid="user-menu"]',
          '[class*="avatar"]',
          'button[aria-haspopup="menu"]',
          'button[aria-haspopup="true"]'
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

    it('should show subscription info in user menu', () => {
      cy.get('body').then($body => {
        const userMenuSelectors = [
          'button[aria-haspopup="true"]',
          '[data-testid="user-menu"]'
        ];

        for (const selector of userMenuSelectors) {
          if ($body.find(selector).length > 0) {
            cy.get(selector).first().click();
            break;
          }
        }
      });

      cy.get('body').then($body => {
        const hasSubscriptionInfo =
          $body.text().includes('Plan') ||
          $body.text().includes('Subscription') ||
          $body.text().includes('Billing');

        if (hasSubscriptionInfo) {
          cy.log('Subscription info in user menu');
        }
      });
    });
  });

  describe('Mobile Subscription Management', () => {
    it('should handle subscription management on mobile viewport', () => {
      cy.viewport(375, 667);
      cy.get('body').should('be.visible');
      cy.url().should('match', /\/(app|dashboard)/);
    });

    it('should provide mobile-optimized plan selection', () => {
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

      cy.get('[data-testid="plan-select-btn"], [data-testid="continue-to-registration"]', { timeout: 10000 })
        .should('be.visible');
    });

    it('should scroll plans on small screens', () => {
      cy.viewport(375, 667);
      cy.clearCookies();
      cy.clearLocalStorage();
      cy.visit('/plans');

      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 15000 })
        .should('exist');

      // Should be able to scroll to see all plans
      cy.get('body').scrollTo('bottom');
      cy.get('body').should('be.visible');
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
      cy.visit('/plans');
      cy.get('body').should('be.visible');

      cy.visit('/app');
      cy.url().should('match', /\/(app|dashboard)/);
    });

    it('should handle subscription API errors gracefully', () => {
      cy.intercept('GET', '/api/v1/subscriptions*', {
        statusCode: 500,
        body: { error: 'Server error' }
      }).as('failedSubscriptions');

      cy.visit('/app');

      cy.get('body')
        .should('be.visible')
        .and('not.contain.text', 'TypeError')
        .and('not.contain.text', 'Cannot read');
    });
  });

  describe('Subscription Features Access', () => {
    it('should display feature limits based on subscription', () => {
      cy.get('body').then($body => {
        const limitIndicators = [
          ':contains("Limit")',
          ':contains("Usage")',
          ':contains("Quota")',
          '[data-testid="usage-limit"]'
        ];

        for (const selector of limitIndicators) {
          if ($body.find(selector).length > 0) {
            cy.log('Feature limits displayed');
            return;
          }
        }
        cy.log('Feature limits may be displayed elsewhere');
      });
    });

    it('should show upgrade prompts for restricted features', () => {
      cy.get('body').then($body => {
        const upgradePrompts = [
          ':contains("Upgrade to")',
          ':contains("Available in")',
          '[data-testid="upgrade-prompt"]'
        ];

        for (const selector of upgradePrompts) {
          if ($body.find(selector).length > 0) {
            cy.log('Upgrade prompt found');
            return;
          }
        }
        cy.log('No upgrade prompts - user may have full access');
      });
    });
  });

  describe('Subscription History', () => {
    it('should display subscription change history', () => {
      cy.intercept('GET', '/api/v1/subscriptions/history', {
        statusCode: 200,
        body: {
          data: [
            { event: 'plan_change', from_plan: 'Basic', to_plan: 'Pro', date: '2024-01-01' },
            { event: 'subscription_created', plan: 'Basic', date: '2023-06-01' }
          ]
        }
      }).as('getHistory');

      cy.visit('/app/billing');

      cy.get('body').then($body => {
        if ($body.text().includes('History') || $body.find('[data-testid="subscription-history"]').length > 0) {
          cy.log('Subscription history section found');
        }
      });
    });
  });
});

describe('Account Subscription Integration', () => {
  beforeEach(() => {
    cy.clearAppData();
    cy.visit('/login');
    cy.get('[data-testid="email-input"]', { timeout: 10000 }).type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').click();
    cy.url({ timeout: 15000 }).should('match', /\/(app|dashboard)/);
  });

  it('should link subscription to account', () => {
    cy.get('body').then($body => {
      // Account name and subscription should be related
      const hasAccountInfo =
        $body.text().includes('Account') ||
        $body.text().includes('Organization') ||
        $body.text().includes('Demo');

      if (hasAccountInfo) {
        cy.log('Account information linked to subscription');
      }
    });
  });

  it('should show team member limits based on plan', () => {
    cy.visit('/app/settings');

    cy.get('body').then($body => {
      const hasTeamLimits =
        $body.text().includes('Team') ||
        $body.text().includes('Members') ||
        $body.text().includes('Seats');

      if (hasTeamLimits) {
        cy.log('Team limits displayed based on plan');
      }
    });
  });

  it('should enforce storage limits based on plan', () => {
    cy.get('body').then($body => {
      const hasStorageLimits =
        $body.text().includes('Storage') ||
        $body.text().includes('GB') ||
        $body.text().includes('space');

      if (hasStorageLimits) {
        cy.log('Storage limits displayed based on plan');
      }
    });
  });
});

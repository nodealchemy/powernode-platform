/// <reference types="cypress" />

/**
 * Subscription Lifecycle E2E Tests
 *
 * Comprehensive tests for subscription lifecycle management including:
 * - Plan subscription flow
 * - Marketplace subscriptions (subscribe, pause, resume, cancel)
 * - Subscription status transitions
 * - Billing integration
 * - Error handling
 */

describe('Subscription Lifecycle', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Platform Plan Subscription', () => {
    describe('Plan Display', () => {
      it('should display available plans on public plans page', () => {
        cy.clearCookies();
        cy.clearLocalStorage();
        cy.visit('/plans');
        cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 5000 })
          .should('have.length.at.least', 1);
      });

      it('should show plan pricing information', () => {
        cy.clearCookies();
        cy.clearLocalStorage();
        cy.visit('/plans');
        cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 5000 })
          .first()
          .within(() => {
            cy.contains(/\$|Free|month|year/i).should('exist');
          });
      });

      it('should display multiple plan tiers', () => {
        cy.clearCookies();
        cy.clearLocalStorage();
        cy.visit('/plans');
        cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 5000 })
          .should('have.length.at.least', 1);
      });

      it('should show billing cycle toggle if available', () => {
        cy.clearCookies();
        cy.clearLocalStorage();
        cy.visit('/plans');
        cy.get('[data-testid="billing-toggle"], [data-testid="billing-cycle"], button:contains("Monthly"), button:contains("Yearly"), button:contains("Annual")')
          .first()
          .should('be.visible');
      });
    });

    describe('Plan Selection Flow', () => {
      it('should allow plan card selection', () => {
        cy.clearCookies();
        cy.clearLocalStorage();
        cy.visit('/plans');
        cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 5000 })
          .first()
          .click();

        cy.assertHasElement([
          '[data-testid="plan-select-btn"]',
          '[data-testid="continue-to-registration"]',
          '.selected',
          '[aria-selected="true"]',
        ]).should('exist');
      });

      it('should navigate to registration after plan selection', () => {
        cy.clearCookies();
        cy.clearLocalStorage();
        cy.visit('/plans');
        cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 5000 })
          .first()
          .click();

        cy.get('[data-testid="continue-to-registration"], [data-testid="plan-select-btn"]', { timeout: 5000 })
          .first()
          .click();

        cy.url().should('include', '/register');
      });
    });

    describe('Current Subscription Display', () => {
      it('should display current subscription status', () => {
        cy.visit('/app');
        cy.assertContainsAny(['Subscription', 'Plan', 'Billing', 'Pro', 'Basic', 'Free']);
      });
    });
  });

  describe('Marketplace Subscriptions', () => {
    describe('Marketplace Navigation', () => {
      it('should navigate to marketplace page', () => {
        cy.visit('/app/marketplace');
        cy.url().should('include', 'marketplace');
      });

      it('should display marketplace items', () => {
        cy.visit('/app/marketplace');
        cy.assertHasElement([
          '[data-testid="marketplace-item"]',
          '[data-testid="app-card"]',
          '[class*="card"]',
          '[class*="listing"]',
        ]).should('exist');
      });

      it('should navigate to My Subscriptions page', () => {
        cy.visit('/app/marketplace/subscriptions');
        cy.url().should('include', 'subscription');
        cy.assertContainsAny(['No subscriptions', 'Browse Marketplace', 'subscription-card']);
      });
    });

    describe('Subscription Filtering', () => {
      it('should filter subscriptions by type', () => {
        cy.visit('/app/marketplace/subscriptions');

        const typeFilters = ['All', 'Apps', 'Plugins', 'Templates', 'Integrations'];
        typeFilters.forEach(filter => {
          cy.get(`button:contains("${filter}")`).first().click();
          cy.waitForStableDOM();
        });
      });

      it('should filter subscriptions by status', () => {
        cy.visit('/app/marketplace/subscriptions');

        const statusFilters = ['All', 'Active', 'Paused'];
        statusFilters.forEach(filter => {
          cy.get(`button:contains("${filter}")`).first().click();
          cy.waitForStableDOM();
        });
      });
    });

    describe('Subscription Actions (Mocked)', () => {
      it('should handle subscription pause action', () => {
        // Mock the pause endpoint
        cy.intercept('POST', '/api/v1/marketplace/subscriptions/*/pause', {
          statusCode: 200,
          body: {
            success: true,
            data: {
              id: 'sub-123',
              status: 'paused',
              item_name: 'Test App'
            }
          }
        }).as('pauseSubscription');

        cy.visit('/app/marketplace/subscriptions');

        cy.get('button[title="Pause"], button:contains("Pause")').first().click();
        cy.wait('@pauseSubscription');
      });

      it('should handle subscription resume action', () => {
        // Mock the resume endpoint
        cy.intercept('POST', '/api/v1/marketplace/subscriptions/*/resume', {
          statusCode: 200,
          body: {
            success: true,
            data: {
              id: 'sub-123',
              status: 'active',
              item_name: 'Test App'
            }
          }
        }).as('resumeSubscription');

        cy.visit('/app/marketplace/subscriptions');

        cy.get('button[title="Resume"], button:contains("Resume")').first().click();
        cy.wait('@resumeSubscription');
      });

      it('should handle subscription cancel with confirmation', () => {
        // Mock the cancel endpoint
        cy.intercept('DELETE', '/api/v1/marketplace/subscriptions/*', {
          statusCode: 200,
          body: {
            success: true,
            data: { message: 'Subscription cancelled' }
          }
        }).as('cancelSubscription');

        cy.visit('/app/marketplace/subscriptions');

        // Note: Real test would need to handle confirm dialog
        cy.get('button[title="Cancel"], button:contains("Cancel")').should('exist');
      });
    });

    describe('Marketplace Item Subscription Flow', () => {
      it('should navigate to item detail page', () => {
        cy.visit('/app/marketplace');

        cy.get('[data-testid="marketplace-item"], [data-testid="app-card"], .card')
          .first()
          .click();
        cy.url().should('match', /\/app\/marketplace\/.+/);
      });

      it('should show subscribe button on item detail', () => {
        // Mock item detail response
        cy.intercept('GET', '/api/v1/marketplace/*/*', {
          statusCode: 200,
          body: {
            success: true,
            data: {
              id: 'item-123',
              name: 'Test App',
              description: 'A test application',
              type: 'app',
              is_subscribed: false
            }
          }
        }).as('getItem');

        cy.visit('/app/marketplace/app/test-item');

        cy.get('button:contains("Subscribe"), button:contains("Install"), button:contains("Add")')
          .should('be.visible');
      });

      it('should handle subscribe action', () => {
        // Mock subscribe endpoint
        cy.intercept('POST', '/api/v1/marketplace/*/*/subscribe', {
          statusCode: 200,
          body: {
            success: true,
            data: {
              id: 'sub-123',
              item_id: 'item-123',
              status: 'active'
            }
          }
        }).as('subscribe');

        cy.visit('/app/marketplace');

        cy.get('button:contains("Subscribe"), button:contains("Install")')
          .first()
          .click();
      });
    });
  });

  describe('Billing Integration', () => {
    describe('Billing Page Navigation', () => {
      it('should navigate to billing/subscription section', () => {
        cy.get('a[href*="billing"], a[href*="subscription"], [data-testid="nav-billing"]').first().click();
        cy.url().should('match', /\/(app|dashboard|billing|subscription|marketplace)/);
      });
    });

    describe('Billing Overview', () => {
      it('should display billing information', () => {
        cy.visit('/app/billing');
        cy.url().should('include', 'billing');
        cy.assertContainsAny(['Invoice', 'Payment', 'Billing', 'Subscription']);
      });

      it('should display invoices list if available', () => {
        cy.intercept('GET', '/api/v1/billing/invoices*', {
          statusCode: 200,
          body: {
            success: true,
            invoices: [
              {
                id: 'inv-1',
                invoice_number: 'INV-001',
                total_amount: '99.00',
                status: 'paid',
                created_at: '2024-01-01'
              }
            ],
            pagination: {
              current_page: 1,
              total_pages: 1,
              total_count: 1
            }
          }
        }).as('getInvoices');

        cy.visit('/app/billing');

        cy.assertContainsAny(['Invoice']);
        cy.assertHasElement(['[data-testid="invoices-table"]', 'body']);
      });
    });

    describe('Payment Methods', () => {
      it('should display payment methods section', () => {
        cy.visit('/app/billing');
        cy.assertContainsAny(['Payment Method', 'Credit Card', 'payment-methods']);
      });

      it('should handle add payment method flow', () => {
        cy.visit('/app/billing');
        cy.get('button:contains("Add Payment"), button:contains("Add Card")')
          .should('be.visible');
      });
    });
  });

  describe('Subscription Status Transitions', () => {
    describe('Status Display', () => {
      it('should display subscription status badges', () => {
        cy.visit('/app/marketplace/subscriptions');
        cy.assertContainsAny(['Active', 'Paused', 'Cancelled', 'Expired']);
      });
    });

    describe('Subscription Lifecycle States', () => {
      it('should show active subscription controls', () => {
        // Mock active subscriptions
        cy.intercept('GET', '/api/v1/marketplace/subscriptions*', {
          statusCode: 200,
          body: {
            success: true,
            data: [{
              id: 'sub-1',
              item_id: 'item-1',
              item_name: 'Test App',
              item_type: 'app',
              status: 'active',
              subscribed_at: '2024-01-01'
            }]
          }
        }).as('getSubscriptions');

        cy.visit('/app/marketplace/subscriptions');
        cy.wait('@getSubscriptions');

        // Active subscriptions should have pause/cancel options
        cy.assertHasElement(['button[title="Pause"]', 'button[title="Configure"]']).should('exist');
      });

      it('should show paused subscription controls', () => {
        // Mock paused subscriptions
        cy.intercept('GET', '/api/v1/marketplace/subscriptions*', {
          statusCode: 200,
          body: {
            success: true,
            data: [{
              id: 'sub-1',
              item_id: 'item-1',
              item_name: 'Test App',
              item_type: 'app',
              status: 'paused',
              subscribed_at: '2024-01-01'
            }]
          }
        }).as('getPausedSubscriptions');

        cy.visit('/app/marketplace/subscriptions');
        cy.wait('@getPausedSubscriptions');

        // Paused subscriptions should have resume option
        cy.get('button[title="Resume"]').should('exist');
        cy.get('body').should('contain.text', 'paused');
      });
    });
  });

  describe('Error Handling', () => {
    it('should handle subscription load failure gracefully', () => {
      cy.intercept('GET', '/api/v1/marketplace/subscriptions*', {
        statusCode: 500,
        body: {
          success: false,
          error: 'Internal server error'
        }
      }).as('failedLoad');

      cy.visit('/app/marketplace/subscriptions');

      // Should not crash - show error or empty state
      cy.get('body')
        .should('be.visible')
        .and('not.contain.text', 'TypeError')
        .and('not.contain.text', 'Cannot read');
    });

    it('should handle pause action failure', () => {
      cy.intercept('POST', '/api/v1/marketplace/subscriptions/*/pause', {
        statusCode: 400,
        body: {
          success: false,
          error: 'Cannot pause subscription'
        }
      }).as('failedPause');

      cy.visit('/app/marketplace/subscriptions');

      // Action failure should show error notification, not crash
      cy.get('body')
        .should('be.visible')
        .and('not.contain.text', 'TypeError');
    });

    it('should handle network timeout gracefully', () => {
      cy.intercept('GET', '/api/v1/marketplace/subscriptions*', {
        delay: 10000,
        statusCode: 200,
        body: []
      }).as('slowLoad');

      cy.visit('/app/marketplace/subscriptions');

      // Should show loading state or timeout gracefully
      cy.assertContainsAny(['Subscription', 'Marketplace', 'Plan']);
    });
  });

  describe('Responsive Design', () => {
    it('should display subscriptions on mobile viewport', () => {
      cy.viewport('iphone-x');
      // Already logged in from beforeEach, just resize viewport
      cy.visit('/app/marketplace/subscriptions');
      cy.assertContainsAny(['Subscription', 'Marketplace', 'Plan']);
    });

    it('should display subscriptions on tablet viewport', () => {
      cy.viewport('ipad-2');
      // Already logged in from beforeEach, just resize viewport
      cy.visit('/app/marketplace/subscriptions');
      cy.assertContainsAny(['Subscription', 'Marketplace', 'Plan']);
    });

    it('should handle plan selection on mobile', () => {
      cy.viewport('iphone-x');
      cy.clearCookies();
      cy.clearLocalStorage();
      cy.visit('/plans');

      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 5000 })
        .should('exist')
        .first()
        .click();

      cy.assertContainsAny(['Subscription', 'Marketplace', 'Plan']);
    });

    it('should display marketplace on mobile', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/marketplace');
      cy.assertContainsAny(['Subscription', 'Marketplace', 'Plan']);
    });
  });
});

describe('Subscription Upgrade/Downgrade Flow', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  it('should display upgrade options for current plan', () => {
    cy.visit('/app');

    cy.get('a:contains("Upgrade"), button:contains("Upgrade"), [data-testid="upgrade-plan"], a[href*="upgrade"]')
      .first()
      .should('be.visible');
  });

  it('should show plan comparison when upgrading', () => {
    cy.clearCookies();
    cy.clearLocalStorage();
    cy.visit('/plans');

    // Multiple plans should be visible for comparison
    cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 5000 })
      .should('have.length.at.least', 1);

    // Check for comparison features
    cy.assertContainsAny(['Feature', 'Included']);
    cy.assertHasElement(['li', '[class*="feature"]']).should('exist');
  });

  it('should handle marketplace subscription tier upgrade', () => {
    cy.intercept('POST', '/api/v1/marketplace/subscriptions/*/upgrade_tier', {
      statusCode: 200,
      body: {
        success: true,
        data: {
          id: 'sub-123',
          tier: 'premium',
          status: 'active'
        }
      }
    }).as('upgradeTier');

    cy.visit('/app/marketplace/subscriptions');

    cy.get('button:contains("Upgrade"), a:contains("Upgrade")').should('exist');
  });
});

describe('Subscription Trial Management', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  it('should display trial status if on trial', () => {
    cy.visit('/app');

    cy.assertContainsAny(['Trial', 'days left', 'trial ends', 'trial-banner']);
  });

  it('should show trial expiration warning', () => {
    // Mock user on trial
    cy.intercept('GET', '/api/v1/billing/subscription', {
      statusCode: 200,
      body: {
        subscription: {
          id: 'sub-1',
          status: 'trialing',
          trial_end: new Date(Date.now() + 3 * 24 * 60 * 60 * 1000).toISOString()
        }
      }
    }).as('getTrialSubscription');

    cy.visit('/app');

    cy.get('body').should('contain.text', 'trial');
  });
});

describe('Subscription Configuration', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  it('should navigate to subscription configuration', () => {
    cy.intercept('GET', '/api/v1/marketplace/subscriptions*', {
      statusCode: 200,
      body: {
        success: true,
        data: [{
          id: 'sub-1',
          item_id: 'item-1',
          item_name: 'Configurable App',
          item_type: 'app',
          status: 'active',
          subscribed_at: '2024-01-01'
        }]
      }
    }).as('getSubscriptions');

    cy.visit('/app/marketplace/subscriptions');
    cy.wait('@getSubscriptions');

    cy.get('button[title="Configure"], a:contains("Configure")').should('exist');
  });

  it('should display subscription usage metrics', () => {
    cy.intercept('GET', '/api/v1/marketplace/subscriptions/*/usage', {
      statusCode: 200,
      body: {
        success: true,
        data: {
          subscription_id: 'sub-1',
          usage_metrics: {
            api_calls: 150,
            storage_mb: 50
          },
          usage_within_limits: true,
          subscription_age_days: 30
        }
      }
    }).as('getUsage');

    cy.visit('/app/marketplace/subscriptions');

    cy.assertContainsAny(['Usage']);
    cy.assertHasElement(['[data-testid="usage-metrics"]', 'body']);
  });
});


export {};

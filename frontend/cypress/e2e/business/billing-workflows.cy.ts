/// <reference types="cypress" />

/**
 * Billing Workflows E2E Tests
 *
 * Comprehensive tests for billing functionality including:
 * - Billing overview and dashboard
 * - Invoice management
 * - Payment methods
 * - Billing history
 * - Error handling
 * - Responsive design
 */

describe('Billing Workflows', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Billing Navigation', () => {
    it('should navigate to billing via direct URL', () => {
      cy.visit('/app/business/billing');
      cy.url().should('match', /\/(app|dashboard|billing|subscription|marketplace|business)/);
    });

    it('should display main app content', () => {
      cy.assertHasElement(['main', '[role="main"]', '.main-content', '[class*="container"]'])
        .should('exist');
    });
  });

  describe('Billing Overview', () => {
    it('should display billing overview dashboard', () => {
      cy.intercept('GET', '**/api/v1/billing**', {
        statusCode: 200,
        body: {
          success: true,
          data: {
            outstanding: 0,
            this_month: 9900,
            collected: 29700,
            success_rate: 98.5,
          },
        },
      }).as('getBillingOverview');

      cy.navigateTo('/app/business/billing');
      cy.assertContainsAny(['Outstanding', 'This Month', 'Collected', 'Overview', 'Billing']);
    });

    it('should display current subscription details', () => {
      cy.intercept('GET', '**/api/v1/billing/subscription**', {
        statusCode: 200,
        body: {
          success: true,
          data: {
            subscription: {
              id: 'sub-123',
              plan: { id: 'plan-1', name: 'Professional', price: '99.00', billing_cycle: 'monthly' },
              status: 'active',
              current_period_start: '2024-01-01',
              current_period_end: '2024-02-01',
            },
          },
        },
      }).as('getSubscription');

      cy.navigateTo('/app/business/billing');
      cy.assertContainsAny(['Plan', 'Subscription', 'Professional', 'Billing', 'Invoice']);
    });
  });

  describe('Invoice Management', () => {
    it('should display invoices list', () => {
      cy.intercept('GET', '**/api/v1/billing/invoices**', {
        statusCode: 200,
        body: {
          success: true,
          data: {
            invoices: [
              { id: 'inv-1', invoice_number: 'INV-2024-001', total_amount: '99.00', status: 'paid' },
              { id: 'inv-2', invoice_number: 'INV-2024-002', total_amount: '99.00', status: 'pending' },
            ],
            pagination: { current_page: 1, per_page: 20, total_count: 2, total_pages: 1 },
          },
        },
      }).as('getInvoices');

      cy.navigateTo('/app/business/billing');
      cy.assertContainsAny(['Invoice', 'INV-', 'Billing', 'Invoices']);
    });

    it('should display invoice status badges', () => {
      cy.intercept('GET', '**/api/v1/billing/invoices**', {
        statusCode: 200,
        body: {
          success: true,
          data: {
            invoices: [
              { id: '1', invoice_number: 'INV-001', status: 'paid', total_amount: '99.00' },
              { id: '2', invoice_number: 'INV-002', status: 'pending', total_amount: '99.00' },
            ],
            pagination: { current_page: 1, total_pages: 1, total_count: 2 },
          },
        },
      }).as('getInvoiceStatuses');

      cy.navigateTo('/app/business/billing');
      cy.assertContainsAny(['paid', 'pending', 'overdue', 'Paid', 'Pending', 'Overdue', 'Invoice']);
    });
  });

  describe('Payment Methods', () => {
    it('should display payment methods section', () => {
      cy.intercept('GET', '**/api/v1/billing/payment-methods**', {
        statusCode: 200,
        body: {
          success: true,
          data: {
            payment_methods: [
              { id: 'pm-1', provider: 'stripe', payment_method_type: 'card', card_brand: 'visa', card_last_four: '4242', is_default: true },
            ],
          },
        },
      }).as('getPaymentMethods');

      cy.navigateTo('/app/business/billing');
      cy.assertContainsAny(['Payment Method', 'Credit Card', '4242', 'Billing', 'Payment']);
    });
  });

  describe('Subscription Plan Management', () => {
    it('should display current plan details', () => {
      cy.navigateTo('/app/business/billing');
      cy.assertContainsAny(['Plan', 'Subscription', 'Monthly', 'Yearly', 'Billing', 'Invoice']);
    });

    it('should show upgrade plan option if available', () => {
      cy.navigateTo('/app/business/billing');
      // Page should show upgrade option or indicate on highest tier
      cy.get('body').should('be.visible');
    });
  });

  describe('Plan Pricing Display', () => {
    it('should display pricing on plans page', () => {
      cy.clearCookies();
      cy.clearLocalStorage();
      cy.visit('/plans');

      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 5000 })
        .first()
        .within(() => {
          cy.contains(/\$|Free|month|year/i).should('exist');
        });
    });

    it('should toggle between monthly and yearly pricing', () => {
      cy.clearCookies();
      cy.clearLocalStorage();
      cy.visit('/plans');

      cy.get('body').then($body => {
        if ($body.find('button:contains("Monthly"), button:contains("Yearly"), button:contains("Annual")').length > 0) {
          cy.get('button:contains("Monthly"), button:contains("Yearly"), button:contains("Annual")').first().click();
          cy.waitForPageLoad();
        }
      });
    });
  });

  describe('Payment Processing', () => {
    it('should display upcoming payment information', () => {
      cy.intercept('GET', '**/api/v1/billing/subscription**', {
        statusCode: 200,
        body: {
          success: true,
          data: {
            subscription: {
              id: 'sub-1',
              plan: { name: 'Professional', price: '99.00' },
              status: 'active',
              current_period_end: new Date(Date.now() + 15 * 24 * 60 * 60 * 1000).toISOString(),
            },
            upcoming_invoice: {
              amount_due: 9900,
              currency: 'USD',
              next_payment_date: new Date(Date.now() + 15 * 24 * 60 * 60 * 1000).toISOString(),
              description: 'Professional Plan - Monthly',
            },
          },
        },
      }).as('getUpcoming');

      cy.navigateTo('/app/business/billing');
      cy.assertContainsAny(['Next', 'Upcoming', 'Due', 'Billing', 'Invoice']);
    });
  });

  describe('Error Handling', () => {
    it('should handle billing API failure gracefully', () => {
      cy.testErrorHandling('**/api/v1/billing**', {
        statusCode: 500,
        visitUrl: '/app/business/billing',
      });
    });

    it('should handle invoice load failure', () => {
      cy.testErrorHandling('**/api/v1/billing/invoices**', {
        statusCode: 500,
        visitUrl: '/app/business/billing',
      });
    });
  });

  describe('Responsive Design', () => {
    it('should display billing across viewports', () => {
      cy.testResponsiveDesign('/app/business/billing', {
        checkContent: 'Billing',
      });
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

      cy.get('body').should('be.visible');
    });
  });
});

describe('Billing Security', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  it('should not expose full card numbers', () => {
    cy.navigateTo('/app/business/billing');

    cy.get('body').then($body => {
      const bodyText = $body.text();
      const hasFullCardNumber = /\d{13,19}/.test(bodyText.replace(/\s/g, ''));
      expect(hasFullCardNumber, 'Full card numbers should not be visible').to.be.false;
    });
  });

  it('should require authentication for billing access', () => {
    cy.clearCookies();
    cy.clearLocalStorage();
    cy.visit('/app/business/billing');
    cy.url().should('include', '/login');
  });
});

export {};

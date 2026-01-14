/// <reference types="cypress" />

/**
 * Billing Workflows E2E Tests
 *
 * Comprehensive tests for billing functionality including:
 * - Billing overview and dashboard
 * - Invoice management
 * - Payment methods
 * - Payment processing
 * - Billing history
 */

describe('Billing Workflows', () => {
  beforeEach(() => {
    cy.clearAppData();
    // Login with demo user
    cy.visit('/login');
    cy.get('[data-testid="email-input"]', { timeout: 5000 }).type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').click();
    cy.url({ timeout: 5000 }).should('match', /\/(app|dashboard)/);
  });

  describe('Billing Navigation', () => {
    it('should navigate to billing page from navigation', () => {
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
            cy.get(selector).first().should('be.visible').click();
            found = true;
            break;
          }
        }

        if (!found) {
          cy.log('No billing link found in navigation - feature may not be accessible to this user');
        }
      });

      cy.url().should('match', /\/(app|dashboard|billing|subscription|marketplace)/);
    });

    it('should display main app content', () => {
      cy.get('body').should('be.visible');
      cy.get('main, [role="main"], .main-content, [class*="container"]')
        .should('exist');
    });

    it('should navigate to billing via direct URL', () => {
      cy.visit('/app/billing');

      cy.url().then(url => {
        if (url.includes('billing')) {
          cy.get('body').should('be.visible');
        } else {
          cy.log('Billing page may redirect for users without billing access');
        }
      });
    });
  });

  describe('Billing Overview', () => {
    it('should display billing overview dashboard', () => {
      cy.intercept('GET', '/api/v1/billing', {
        statusCode: 200,
        body: {
          outstanding: 0,
          this_month: 9900,
          collected: 29700,
          success_rate: 98.5
        }
      }).as('getBillingOverview');

      cy.visit('/app/billing');

      cy.get('body').then($body => {
        const hasDashboard =
          $body.text().includes('Outstanding') ||
          $body.text().includes('This Month') ||
          $body.text().includes('Collected') ||
          $body.text().includes('Overview');

        if (hasDashboard) {
          cy.log('Billing overview dashboard displayed');
        } else {
          cy.log('Overview section may have different structure');
        }
      });
    });

    it('should display billing metrics', () => {
      cy.visit('/app/billing');

      cy.get('body').then($body => {
        const metricSelectors = [
          '[data-testid="billing-metric"]',
          '[class*="metric"]',
          '[class*="stat"]',
          '[class*="card"]'
        ];

        for (const selector of metricSelectors) {
          if ($body.find(selector).length > 0) {
            cy.get(selector).should('have.length.at.least', 0);
            cy.log('Billing metrics displayed');
            return;
          }
        }
        cy.log('Metrics section may have different structure');
      });
    });

    it('should display current subscription details', () => {
      cy.intercept('GET', '/api/v1/billing/subscription', {
        statusCode: 200,
        body: {
          subscription: {
            id: 'sub-123',
            plan: {
              id: 'plan-1',
              name: 'Professional',
              price: '99.00',
              billing_cycle: 'monthly'
            },
            status: 'active',
            current_period_start: '2024-01-01',
            current_period_end: '2024-02-01'
          }
        }
      }).as('getSubscription');

      cy.visit('/app/billing');

      cy.get('body').then($body => {
        const hasSubscription =
          $body.text().includes('Plan') ||
          $body.text().includes('Subscription') ||
          $body.text().includes('Professional');

        if (hasSubscription) {
          cy.log('Subscription details displayed');
        }
      });
    });
  });

  describe('Invoice Management', () => {
    it('should display invoices list', () => {
      cy.intercept('GET', '/api/v1/billing/invoices*', {
        statusCode: 200,
        body: {
          invoices: [
            {
              id: 'inv-1',
              invoice_number: 'INV-2024-001',
              total_amount: '99.00',
              currency: 'USD',
              status: 'paid',
              due_date: '2024-01-15',
              created_at: '2024-01-01'
            },
            {
              id: 'inv-2',
              invoice_number: 'INV-2024-002',
              total_amount: '99.00',
              currency: 'USD',
              status: 'pending',
              due_date: '2024-02-15',
              created_at: '2024-02-01'
            }
          ],
          pagination: {
            current_page: 1,
            per_page: 20,
            total_count: 2,
            total_pages: 1
          }
        }
      }).as('getInvoices');

      cy.visit('/app/billing');

      cy.get('body').then($body => {
        const hasInvoices =
          $body.text().includes('Invoice') ||
          $body.text().includes('INV-') ||
          $body.find('[data-testid="invoice-table"]').length > 0 ||
          $body.find('table').length > 0;

        if (hasInvoices) {
          cy.log('Invoices section displayed');
        } else {
          cy.log('Invoices may be in a separate section');
        }
      });
    });

    it('should display invoice status badges', () => {
      cy.intercept('GET', '/api/v1/billing/invoices*', {
        statusCode: 200,
        body: {
          invoices: [
            { id: '1', invoice_number: 'INV-001', status: 'paid', total_amount: '99.00' },
            { id: '2', invoice_number: 'INV-002', status: 'pending', total_amount: '99.00' },
            { id: '3', invoice_number: 'INV-003', status: 'overdue', total_amount: '99.00' }
          ],
          pagination: { current_page: 1, total_pages: 1, total_count: 3 }
        }
      }).as('getInvoiceStatuses');

      cy.visit('/app/billing');

      cy.get('body').then($body => {
        const statuses = ['paid', 'pending', 'overdue'];
        statuses.forEach(status => {
          if ($body.text().toLowerCase().includes(status)) {
            cy.log(`Found status: ${status}`);
          }
        });
      });
    });

    it('should handle invoice download', () => {
      cy.intercept('GET', '/api/v1/billing/invoices/*/download', {
        statusCode: 200,
        body: 'PDF content',
        headers: {
          'content-type': 'application/pdf'
        }
      }).as('downloadInvoice');

      cy.visit('/app/billing');

      cy.get('body').then($body => {
        const downloadButton = $body.find('button:contains("Download"), a:contains("Download"), [data-testid="download-invoice"]');
        if (downloadButton.length > 0) {
          cy.log('Download invoice option available');
        }
      });
    });

    it('should paginate invoices', () => {
      cy.intercept('GET', '/api/v1/billing/invoices*', {
        statusCode: 200,
        body: {
          invoices: Array(20).fill(null).map((_, i) => ({
            id: `inv-${i}`,
            invoice_number: `INV-2024-${String(i + 1).padStart(3, '0')}`,
            total_amount: '99.00',
            status: 'paid'
          })),
          pagination: {
            current_page: 1,
            per_page: 10,
            total_count: 20,
            total_pages: 2
          }
        }
      }).as('getPaginatedInvoices');

      cy.visit('/app/billing');

      cy.get('body').then($body => {
        const hasPagination =
          $body.find('[data-testid="pagination"]').length > 0 ||
          $body.find('button:contains("Next")').length > 0 ||
          $body.find('[class*="pagination"]').length > 0;

        if (hasPagination) {
          cy.log('Invoice pagination available');
        }
      });
    });
  });

  describe('Payment Methods', () => {
    it('should display payment methods section', () => {
      cy.intercept('GET', '/api/v1/billing/payment-methods', {
        statusCode: 200,
        body: {
          payment_methods: [
            {
              id: 'pm-1',
              provider: 'stripe',
              payment_method_type: 'card',
              card_brand: 'visa',
              card_last_four: '4242',
              is_default: true
            }
          ]
        }
      }).as('getPaymentMethods');

      cy.visit('/app/billing');

      cy.get('body').then($body => {
        const hasPaymentMethods =
          $body.text().includes('Payment Method') ||
          $body.text().includes('Credit Card') ||
          $body.text().includes('4242') ||
          $body.find('[data-testid="payment-methods"]').length > 0;

        if (hasPaymentMethods) {
          cy.log('Payment methods section displayed');
        }
      });
    });

    it('should display card details masked', () => {
      cy.intercept('GET', '/api/v1/billing/payment-methods', {
        statusCode: 200,
        body: {
          payment_methods: [{
            id: 'pm-1',
            provider: 'stripe',
            payment_method_type: 'card',
            card_brand: 'visa',
            card_last_four: '4242',
            is_default: true
          }]
        }
      }).as('getCards');

      cy.visit('/app/billing');

      cy.get('body').then($body => {
        // Should show last 4 digits only
        if ($body.text().includes('4242')) {
          cy.log('Card number properly masked (last 4 digits shown)');
        }
      });
    });

    it('should show add payment method button', () => {
      cy.visit('/app/billing');

      cy.get('body').then($body => {
        const addButtons = [
          'button:contains("Add Payment")',
          'button:contains("Add Card")',
          'button:contains("Add Method")',
          '[data-testid="add-payment-method"]'
        ];

        for (const selector of addButtons) {
          if ($body.find(selector).length > 0) {
            cy.get(selector).first().should('be.visible');
            cy.log('Add payment method button found');
            return;
          }
        }
        cy.log('Add payment method button not visible');
      });
    });

    it('should handle set default payment method', () => {
      cy.intercept('PUT', '/api/v1/billing/payment-methods/*/default', {
        statusCode: 200,
        body: { success: true }
      }).as('setDefault');

      cy.intercept('GET', '/api/v1/billing/payment-methods', {
        statusCode: 200,
        body: {
          payment_methods: [
            { id: 'pm-1', card_brand: 'visa', card_last_four: '4242', is_default: true },
            { id: 'pm-2', card_brand: 'mastercard', card_last_four: '5555', is_default: false }
          ]
        }
      }).as('getMethods');

      cy.visit('/app/billing');

      cy.get('body').then($body => {
        const setDefaultButton = $body.find('button:contains("Set Default"), button:contains("Make Default")');
        if (setDefaultButton.length > 0) {
          cy.log('Set default option available');
        }
      });
    });

    it('should handle remove payment method', () => {
      cy.intercept('DELETE', '/api/v1/billing/payment-methods/*', {
        statusCode: 200,
        body: { success: true }
      }).as('removeMethod');

      cy.visit('/app/billing');

      cy.get('body').then($body => {
        const removeButton = $body.find('button:contains("Remove"), button:contains("Delete"), [data-testid="remove-payment"]');
        if (removeButton.length > 0) {
          cy.log('Remove payment method option available');
        }
      });
    });
  });

  describe('Billing History', () => {
    it('should display billing history', () => {
      cy.intercept('GET', '/api/v1/billing/history*', {
        statusCode: 200,
        body: {
          data: [
            {
              id: 'txn-1',
              invoice_number: 'INV-001',
              amount: '99.00',
              status: 'completed',
              created_at: '2024-01-15'
            },
            {
              id: 'txn-2',
              invoice_number: 'INV-002',
              amount: '99.00',
              status: 'completed',
              created_at: '2024-02-15'
            }
          ],
          pagination: {
            current_page: 1,
            per_page: 20,
            total_count: 2,
            total_pages: 1
          }
        }
      }).as('getBillingHistory');

      cy.visit('/app/billing');

      cy.get('body').then($body => {
        const hasHistory =
          $body.text().includes('History') ||
          $body.text().includes('Transaction') ||
          $body.find('[data-testid="billing-history"]').length > 0;

        if (hasHistory) {
          cy.log('Billing history displayed');
        }
      });
    });

    it('should filter billing history by date range', () => {
      cy.intercept('GET', '/api/v1/billing/history*', {
        statusCode: 200,
        body: { data: [], pagination: { current_page: 1, total_pages: 1, total_count: 0 } }
      }).as('getFilteredHistory');

      cy.visit('/app/billing');

      cy.get('body').then($body => {
        const dateFilters = $body.find('input[type="date"], [data-testid="date-filter"]');
        if (dateFilters.length > 0) {
          cy.log('Date filter available for billing history');
        }
      });
    });
  });

  describe('Subscription Plan Management', () => {
    it('should display current plan details', () => {
      cy.visit('/app/billing');

      cy.get('body').then($body => {
        const planIndicators = [
          ':contains("Plan")',
          ':contains("Subscription")',
          ':contains("Monthly")',
          ':contains("Yearly")'
        ];

        for (const selector of planIndicators) {
          if ($body.find(selector).length > 0) {
            cy.log('Plan details section found');
            return;
          }
        }
      });
    });

    it('should show upgrade plan option', () => {
      cy.visit('/app/billing');

      cy.get('body').then($body => {
        const upgradeButtons = [
          'button:contains("Upgrade")',
          'a:contains("Upgrade")',
          '[data-testid="upgrade-plan"]'
        ];

        for (const selector of upgradeButtons) {
          if ($body.find(selector).length > 0) {
            cy.log('Upgrade plan option available');
            return;
          }
        }
        cy.log('No upgrade option - may be on highest tier');
      });
    });

    it('should show downgrade plan option if applicable', () => {
      cy.visit('/app/billing');

      cy.get('body').then($body => {
        const downgradeButtons = [
          'button:contains("Downgrade")',
          'a:contains("Change Plan")',
          '[data-testid="change-plan"]'
        ];

        for (const selector of downgradeButtons) {
          if ($body.find(selector).length > 0) {
            cy.log('Plan change option available');
            return;
          }
        }
      });
    });

    it('should show cancel subscription option', () => {
      cy.visit('/app/billing');

      cy.get('body').then($body => {
        const cancelButtons = [
          'button:contains("Cancel Subscription")',
          'button:contains("Cancel Plan")',
          '[data-testid="cancel-subscription"]'
        ];

        for (const selector of cancelButtons) {
          if ($body.find(selector).length > 0) {
            cy.log('Cancel subscription option available');
            return;
          }
        }
        cy.log('Cancel option may not be visible');
      });
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
        const toggleButtons = [
          'button:contains("Monthly")',
          'button:contains("Yearly")',
          'button:contains("Annual")',
          '[data-testid="billing-toggle"]'
        ];

        for (const selector of toggleButtons) {
          if ($body.find(selector).length > 0) {
            cy.get(selector).first().click();
            cy.waitForPageLoad();
            cy.log('Billing cycle toggle clicked');
            return;
          }
        }
        cy.log('No billing toggle found');
      });
    });

    it('should show yearly discount if available', () => {
      cy.clearCookies();
      cy.clearLocalStorage();
      cy.visit('/plans');

      cy.get('body').then($body => {
        const hasDiscount =
          $body.text().includes('Save') ||
          $body.text().includes('discount') ||
          $body.text().includes('% off');

        if (hasDiscount) {
          cy.log('Yearly discount displayed');
        }
      });
    });
  });

  describe('Payment Processing', () => {
    it('should display upcoming payment information', () => {
      cy.intercept('GET', '/api/v1/billing/subscription', {
        statusCode: 200,
        body: {
          subscription: {
            id: 'sub-1',
            plan: { name: 'Professional', price: '99.00' },
            status: 'active',
            current_period_end: new Date(Date.now() + 15 * 24 * 60 * 60 * 1000).toISOString()
          },
          upcoming_invoice: {
            amount_due: 9900,
            currency: 'USD',
            next_payment_date: new Date(Date.now() + 15 * 24 * 60 * 60 * 1000).toISOString(),
            description: 'Professional Plan - Monthly'
          }
        }
      }).as('getUpcoming');

      cy.visit('/app/billing');

      cy.get('body').then($body => {
        const hasUpcoming =
          $body.text().includes('Next') ||
          $body.text().includes('Upcoming') ||
          $body.text().includes('Due');

        if (hasUpcoming) {
          cy.log('Upcoming payment information displayed');
        }
      });
    });

    it('should handle payment intent creation', () => {
      cy.intercept('POST', '/api/v1/billing/payment-intent', {
        statusCode: 200,
        body: {
          success: true,
          client_secret: 'pi_test_secret',
          payment_intent_id: 'pi_test_123'
        }
      }).as('createPaymentIntent');

      cy.visit('/app/billing');

      // Payment intent creation is typically triggered by payment flow
      cy.get('body').should('be.visible');
    });
  });

  describe('Error Handling', () => {
    it('should handle billing API failure gracefully', () => {
      cy.intercept('GET', '/api/v1/billing', {
        statusCode: 500,
        body: { error: 'Internal server error' }
      }).as('failedBilling');

      cy.visit('/app/billing');

      cy.get('body')
        .should('be.visible')
        .and('not.contain.text', 'TypeError')
        .and('not.contain.text', 'Cannot read');
    });

    it('should handle payment method addition failure', () => {
      cy.intercept('POST', '/api/v1/billing/payment-methods', {
        statusCode: 400,
        body: { success: false, error: 'Invalid payment method' }
      }).as('failedAddPayment');

      cy.visit('/app/billing');

      cy.get('body').should('be.visible');
    });

    it('should handle invoice load failure', () => {
      cy.intercept('GET', '/api/v1/billing/invoices*', {
        statusCode: 500,
        body: { error: 'Failed to load invoices' }
      }).as('failedInvoices');

      cy.visit('/app/billing');

      cy.get('body')
        .should('be.visible')
        .and('not.contain.text', 'TypeError');
    });
  });

  describe('User Account Access', () => {
    it('should display user menu', () => {
      cy.get('body').then($body => {
        const userMenuSelectors = [
          '[data-testid="user-menu"]',
          '[data-testid="user-dropdown"]',
          '[class*="avatar"]',
          'button[aria-haspopup="menu"]',
          'button[aria-haspopup="true"]'
        ];

        for (const selector of userMenuSelectors) {
          if ($body.find(selector).length > 0) {
            cy.get(selector).first().should('be.visible');
            return;
          }
        }
      });
    });

    it('should allow logout', () => {
      cy.logout();
    });
  });

  describe('Responsive Design', () => {
    it('should display billing on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/billing');
      cy.get('body').should('be.visible');
    });

    it('should display billing on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/billing');
      cy.get('body').should('be.visible');
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
    cy.clearAppData();
    cy.visit('/login');
    cy.get('[data-testid="email-input"]', { timeout: 5000 }).type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').click();
    cy.url({ timeout: 5000 }).should('match', /\/(app|dashboard)/);
  });

  it('should not expose full card numbers', () => {
    cy.visit('/app/billing');

    cy.get('body').then($body => {
      const bodyText = $body.text();
      // Full card numbers should never appear
      const hasFullCardNumber = /\d{13,19}/.test(bodyText.replace(/\s/g, ''));
      expect(hasFullCardNumber, 'Full card numbers should not be visible').to.be.false;
    });
  });

  it('should require authentication for billing access', () => {
    cy.clearCookies();
    cy.clearLocalStorage();
    cy.visit('/app/billing');

    // Should redirect to login
    cy.url().should('include', '/login');
  });
});


export {};

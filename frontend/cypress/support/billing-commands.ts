/// <reference types="cypress" />

// Billing-related custom commands for Powernode E2E testing

declare global {
  namespace Cypress {
    interface Chainable {
      /**
       * Login as admin user with full permissions
       * @example cy.loginAsAdmin()
       */
      loginAsAdmin(): Chainable<void>;

      /**
       * Login as billing manager with billing permissions
       * @example cy.loginAsBillingManager()
       */
      loginAsBillingManager(): Chainable<void>;

      /**
       * Create a test invoice via API
       * @example cy.createTestInvoice({ amount: 9999, status: 'pending' })
       */
      createTestInvoice(invoiceData?: Partial<TestInvoice>): Chainable<TestInvoice>;

      /**
       * Setup a subscription for testing
       * @example cy.setupSubscription('pro')
       */
      setupSubscription(planSlug: string): Chainable<void>;

      /**
       * Mock Stripe payment gateway responses
       * @example cy.mockPaymentGateway()
       */
      mockPaymentGateway(): Chainable<void>;

      /**
       * Set up billing API intercepts for predictable testing
       * @example cy.interceptBillingApi()
       */
      interceptBillingApi(): Chainable<void>;

      /**
       * Navigate to billing page and wait for load
       * @example cy.visitBillingPage()
       */
      visitBillingPage(): Chainable<void>;

      /**
       * Get billing metrics from the dashboard
       * @example cy.getBillingMetrics()
       */
      getBillingMetrics(): Chainable<JQuery<HTMLElement>>;
    }
  }
}

interface TestInvoice {
  id: string;
  amount_cents: number;
  status: 'pending' | 'paid' | 'overdue' | 'cancelled';
  due_date: string;
  customer_name: string;
}

// Admin login credentials (should be set in cypress.env.json)
const ADMIN_EMAIL = Cypress.env('adminEmail') || 'admin@example.com';
const ADMIN_PASSWORD = Cypress.env('adminPassword') || 'Qx7#mK9@pL2$nZ6!';
const BILLING_MANAGER_EMAIL = Cypress.env('billingManagerEmail') || 'billing@example.com';
const BILLING_MANAGER_PASSWORD = Cypress.env('billingManagerPassword') || 'Rw8$jN4#vX3@qM5!';

// Login as admin user
Cypress.Commands.add('loginAsAdmin', () => {
  cy.session('admin-session', () => {
    cy.request({
      method: 'POST',
      url: `${Cypress.env('apiUrl')}/auth/login`,
      body: {
        email: ADMIN_EMAIL,
        password: ADMIN_PASSWORD,
      },
      failOnStatusCode: false,
    }).then((response) => {
      if (response.status === 200 && response.body.data?.token) {
        window.localStorage.setItem('accessToken', response.body.data.token);
        if (response.body.data.refreshToken) {
          window.localStorage.setItem('refreshToken', response.body.data.refreshToken);
        }
      } else {
        // Fallback to UI login with new data-testid selectors
        cy.visit('/login');
        cy.get('[data-testid="email-input"]', { timeout: 10000 }).should('be.visible').clear().type(ADMIN_EMAIL);
        cy.get('[data-testid="password-input"]').clear().type(ADMIN_PASSWORD);
        cy.get('[data-testid="login-submit-btn"]').should('not.be.disabled').click();
        cy.url({ timeout: 15000 }).should('match', /\/(app|dashboard)/);
      }
    });
  });
  cy.visit('/dashboard');
});

// Login as billing manager
Cypress.Commands.add('loginAsBillingManager', () => {
  cy.session('billing-manager-session', () => {
    cy.request({
      method: 'POST',
      url: `${Cypress.env('apiUrl')}/auth/login`,
      body: {
        email: BILLING_MANAGER_EMAIL,
        password: BILLING_MANAGER_PASSWORD,
      },
      failOnStatusCode: false,
    }).then((response) => {
      if (response.status === 200 && response.body.data?.token) {
        window.localStorage.setItem('accessToken', response.body.data.token);
        if (response.body.data.refreshToken) {
          window.localStorage.setItem('refreshToken', response.body.data.refreshToken);
        }
      } else {
        // Fallback to UI login with new data-testid selectors
        cy.visit('/login');
        cy.get('[data-testid="email-input"]', { timeout: 10000 }).should('be.visible').clear().type(BILLING_MANAGER_EMAIL);
        cy.get('[data-testid="password-input"]').clear().type(BILLING_MANAGER_PASSWORD);
        cy.get('[data-testid="login-submit-btn"]').should('not.be.disabled').click();
        cy.url({ timeout: 15000 }).should('match', /\/(app|dashboard)/);
      }
    });
  });
  cy.visit('/dashboard');
});

// Create test invoice via API
Cypress.Commands.add('createTestInvoice', (invoiceData = {}) => {
  const defaultInvoice: TestInvoice = {
    id: `inv_${Date.now()}`,
    amount_cents: 9999,
    status: 'pending',
    due_date: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString(),
    customer_name: 'Test Customer',
    ...invoiceData,
  };

  return cy.request({
    method: 'POST',
    url: `${Cypress.env('apiUrl')}/billing/invoices`,
    headers: {
      Authorization: `Bearer ${window.localStorage.getItem('accessToken')}`,
    },
    body: defaultInvoice,
    failOnStatusCode: false,
  }).then((response) => {
    if (response.status === 201 || response.status === 200) {
      return response.body.data;
    }
    return defaultInvoice;
  });
});

// Setup subscription for testing
Cypress.Commands.add('setupSubscription', (planSlug: string) => {
  cy.request({
    method: 'POST',
    url: `${Cypress.env('apiUrl')}/subscriptions`,
    headers: {
      Authorization: `Bearer ${window.localStorage.getItem('accessToken')}`,
    },
    body: {
      plan_slug: planSlug,
      billing_cycle: 'monthly',
    },
    failOnStatusCode: false,
  });
});

// Mock Stripe payment gateway
Cypress.Commands.add('mockPaymentGateway', () => {
  // Intercept Stripe.js loading
  cy.intercept('GET', 'https://js.stripe.com/**', {
    statusCode: 200,
    body: 'window.Stripe = function() { return { elements: function() { return { create: function() { return { mount: function() {}, on: function() {} }; } }; }, confirmCardPayment: function() { return Promise.resolve({ paymentIntent: { status: "succeeded" } }); } }; };',
  }).as('stripeJs');

  // Intercept Stripe API calls
  cy.intercept('POST', '**/v1/payment_intents/**', {
    statusCode: 200,
    body: {
      id: 'pi_test_123',
      status: 'succeeded',
      client_secret: 'pi_test_secret',
    },
  }).as('stripePaymentIntent');

  cy.intercept('POST', '**/v1/payment_methods/**', {
    statusCode: 200,
    body: {
      id: 'pm_test_123',
      type: 'card',
      card: {
        brand: 'visa',
        last4: '4242',
        exp_month: 12,
        exp_year: 2025,
      },
    },
  }).as('stripePaymentMethod');
});

// Set up billing API intercepts
Cypress.Commands.add('interceptBillingApi', () => {
  // Intercept billing overview
  cy.intercept('GET', '**/api/v1/billing/overview**', {
    fixture: 'billing/overview.json',
  }).as('billingOverview');

  // Intercept invoices list
  cy.intercept('GET', '**/api/v1/billing/invoices**', {
    fixture: 'billing/invoices.json',
  }).as('invoicesList');

  // Intercept payment methods
  cy.intercept('GET', '**/api/v1/billing/payment-methods**', {
    fixture: 'billing/payment-methods.json',
  }).as('paymentMethods');

  // Intercept subscription data
  cy.intercept('GET', '**/api/v1/subscriptions**', {
    fixture: 'billing/subscription-plans.json',
  }).as('subscriptions');

  // Intercept plans
  cy.intercept('GET', '**/api/v1/plans**', {
    fixture: 'billing/subscription-plans.json',
  }).as('plans');

  // Intercept invoice creation
  cy.intercept('POST', '**/api/v1/billing/invoices', {
    statusCode: 201,
    body: {
      success: true,
      data: {
        id: 'inv_new_123',
        status: 'pending',
        amount_cents: 9999,
      },
    },
  }).as('createInvoice');

  // Intercept invoice download
  cy.intercept('GET', '**/api/v1/billing/invoices/*/download', {
    statusCode: 200,
    headers: {
      'content-type': 'application/pdf',
    },
    body: new Blob(['PDF content'], { type: 'application/pdf' }),
  }).as('downloadInvoice');
});

// Navigate to billing page
Cypress.Commands.add('visitBillingPage', () => {
  cy.visit('/business/billing');
  cy.url().should('include', '/billing');
  cy.get('[data-testid="billing-page"], .billing-container, [class*="billing"]', { timeout: 10000 })
    .should('exist');
});

// Get billing metrics
Cypress.Commands.add('getBillingMetrics', () => {
  return cy.get('[data-testid="billing-metrics"], .billing-metrics, [class*="metrics"]');
});

export {};

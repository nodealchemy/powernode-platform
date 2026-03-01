/// <reference types="cypress" />

/**
 * Business Billing Workflows Tests
 *
 * Comprehensive E2E tests for Business Billing:
 * - Invoice management
 * - Payment processing
 * - Subscription management
 * - Payment method management
 * - Billing history
 * - Dunning management
 */

describe('Business Billing Workflows Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
    setupBillingIntercepts();
  });

  describe('Billing Overview', () => {
    beforeEach(() => {
      cy.navigateTo('/app/business/billing');
    });

    it('should display billing page with title', () => {
      cy.assertContainsAny(['Billing', 'Billing Overview', 'Payments']);
    });

    it('should display current balance or amount due', () => {
      cy.assertContainsAny(['Balance', 'Amount Due', 'Current', '$']);
    });

    it('should display next payment date', () => {
      cy.assertContainsAny(['Next Payment', 'Due Date', 'Renewal']);
    });

    it('should display subscription status', () => {
      cy.assertContainsAny(['Active', 'Subscription', 'Plan', 'Status']);
    });

    it('should have manage subscription button', () => {
      cy.get('button').contains(/manage|upgrade|change/i).should('exist');
    });
  });

  describe('Invoices Tab', () => {
    beforeEach(() => {
      cy.navigateTo('/app/business/billing');
      cy.get('button').contains(/invoices/i).first().click();
    });

    it('should display invoices list', () => {
      cy.assertContainsAny(['Invoice', 'INV-', 'invoices']);
    });

    it('should show invoice status', () => {
      cy.assertContainsAny(['Paid', 'Pending', 'Overdue', 'Draft']);
    });

    it('should show invoice amount', () => {
      cy.get('body').should('contain', '$');
    });

    it('should show invoice date', () => {
      cy.get('body').invoke('text').should('match', /\d{1,2}\/\d{1,2}\/\d{2,4}|Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec/);
    });

    it('should have download invoice button', () => {
      cy.get('button').contains(/download|pdf|view/i).should('exist');
    });

    it('should download invoice when button clicked', () => {
      cy.intercept('GET', '**/api/**/invoices/*/download*', {
        statusCode: 200,
        headers: { 'content-type': 'application/pdf' },
        body: 'PDF content',
      }).as('downloadInvoice');

      cy.get('button').contains(/download|pdf/i).first().click();
      cy.wait('@downloadInvoice');
    });
  });

  describe('Payment Methods Tab', () => {
    beforeEach(() => {
      cy.navigateTo('/app/business/billing');
      cy.get('button').contains(/payment methods|methods/i).first().click();
    });

    it('should display payment methods list', () => {
      cy.assertContainsAny(['Payment Methods', 'Card', 'Bank', 'Method']);
    });

    it('should show card details (masked)', () => {
      cy.assertContainsAny(['****', 'ending in', 'expires']);
    });

    it('should have add payment method button', () => {
      cy.get('button').contains(/add|new/i).should('exist');
    });

    it('should have set default option', () => {
      cy.get('button').contains(/default|primary/i).should('exist');
    });

    it('should have remove payment method option', () => {
      cy.get('button').contains(/remove|delete/i).should('exist');
    });

    it('should open add payment method modal', () => {
      cy.get('button').contains(/add|new/i).first().click();
      cy.assertContainsAny(['Add', 'Card', 'Payment']);
    });
  });

  describe('Subscription Management', () => {
    beforeEach(() => {
      cy.navigateTo('/app/business/billing');
      cy.get('button').contains(/subscription|plan/i).first().click();
    });

    it('should display current subscription details', () => {
      cy.assertContainsAny(['Current Plan', 'Subscription', 'Plan']);
    });

    it('should show plan name and price', () => {
      cy.assertContainsAny(['Pro', 'Business', 'Enterprise', 'Starter', '$']);
    });

    it('should show billing cycle', () => {
      cy.assertContainsAny(['monthly', 'annual', 'yearly', 'per month', 'per year']);
    });

    it('should have upgrade/downgrade options', () => {
      cy.get('button').contains(/upgrade|change|switch/i).should('exist');
    });

    it('should have cancel subscription option', () => {
      cy.get('button').contains(/cancel/i).should('exist');
    });

    it('should show plan features', () => {
      cy.assertContainsAny(['features', 'included', 'limits', 'users', 'storage']);
    });
  });

  describe('Upgrade/Downgrade Plan', () => {
    beforeEach(() => {
      cy.navigateTo('/app/business/billing');
      cy.get('button').contains(/upgrade|change plan/i).first().click();
    });

    it('should display available plans', () => {
      cy.assertContainsAny(['Plans', 'Choose', 'Select']);
    });

    it('should show plan comparison', () => {
      cy.assertContainsAny(['features', 'price', 'compare']);
    });

    it('should calculate proration', () => {
      cy.assertContainsAny(['proration', 'prorated', 'credit', 'charge']);
    });

    it('should change plan when confirmed', () => {
      cy.intercept('POST', '**/api/**/subscriptions/change*', {
        statusCode: 200,
        body: { success: true, message: 'Plan changed successfully' },
      }).as('changePlan');

      cy.get('[class*="card"]').contains(/enterprise|business/i).first().click();
      cy.get('button').contains(/confirm|upgrade/i).click();
      cy.wait('@changePlan');
      cy.assertContainsAny(['changed', 'success', 'upgraded']);
    });
  });

  describe('Make Payment', () => {
    beforeEach(() => {
      cy.navigateTo('/app/business/billing');
    });

    it('should have pay now button for outstanding balance', () => {
      cy.get('button').contains(/pay now|pay/i).should('exist');
    });

    it('should process payment when button clicked', () => {
      cy.intercept('POST', '**/api/**/payments*', {
        statusCode: 200,
        body: { success: true, payment: { id: 'pay-new', amount: 99.00 } },
      }).as('processPayment');

      cy.get('button').contains(/pay/i).first().click();
      cy.wait('@processPayment');
      cy.assertContainsAny(['paid', 'success', 'processed']);
    });
  });

  describe('Billing History', () => {
    beforeEach(() => {
      cy.navigateTo('/app/business/billing');
      cy.get('button').contains(/history|transactions/i).first().click();
    });

    it('should display transaction history', () => {
      cy.assertContainsAny(['History', 'Transactions', 'payments']);
    });

    it('should show transaction type', () => {
      cy.assertContainsAny(['Payment', 'Refund', 'Credit', 'Charge']);
    });

    it('should show transaction status', () => {
      cy.assertContainsAny(['Completed', 'Pending', 'Failed', 'Refunded']);
    });

    it('should have date filter', () => {
      cy.get('input[type="date"], select').should('exist');
    });

    it('should have export option', () => {
      cy.get('button').contains(/export|download/i).should('exist');
    });
  });

  describe('Dunning Management', () => {
    beforeEach(() => {
      cy.navigateTo('/app/business/billing');
    });

    it('should display failed payment notice if applicable', () => {
      cy.assertContainsAny(['Failed', 'Payment failed', 'Retry', 'Billing']);
    });

    it('should have retry payment option', () => {
      cy.get('button').contains(/retry/i).should('exist');
    });

    it('should have update payment method option on failure', () => {
      cy.get('button').contains(/update|change/i).should('exist');
    });
  });

  describe('Cancel Subscription', () => {
    beforeEach(() => {
      cy.navigateTo('/app/business/billing');
    });

    it('should open cancel modal when button clicked', () => {
      cy.get('button').contains(/cancel subscription/i).click();
      cy.assertContainsAny(['Cancel', 'Cancellation', 'confirm']);
    });

    it('should show cancellation impact', () => {
      cy.get('button').contains(/cancel subscription/i).click();
      cy.assertContainsAny(['lose access', 'data', 'effective', 'end of period']);
    });

    it('should offer retention options', () => {
      cy.get('button').contains(/cancel subscription/i).click();
      cy.assertContainsAny(['reason', 'feedback', 'alternative', 'discount']);
    });

    it('should cancel subscription when confirmed', () => {
      cy.intercept('POST', '**/api/**/subscriptions/cancel*', {
        statusCode: 200,
        body: { success: true, message: 'Subscription cancelled' },
      }).as('cancelSubscription');

      cy.get('button').contains(/cancel subscription/i).click();
      cy.get('button').contains(/confirm|cancel anyway/i).click();
      cy.wait('@cancelSubscription');
      cy.assertContainsAny(['cancelled', 'success']);
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.testErrorHandling('**/api/**/billing/**', {
        statusCode: 500,
        visitUrl: '/app/business/billing',
      });
    });

    it('should handle payment failure gracefully', () => {
      cy.intercept('POST', '**/api/**/payments*', {
        statusCode: 400,
        body: { error: 'Payment declined' },
      }).as('paymentFailed');

      cy.navigateTo('/app/business/billing');
      cy.get('button').contains(/pay/i).first().click();
      cy.wait('@paymentFailed');
      cy.assertContainsAny(['declined', 'failed', 'error']);
    });
  });

  describe('Responsive Design', () => {
    it('should display correctly across viewports', () => {
      cy.testResponsiveDesign('/app/business/billing', {
        checkContent: 'Billing',
      });
    });
  });
});

function setupBillingIntercepts() {
  const mockBillingOverview = {
    current_balance: 0,
    next_payment_date: '2025-02-01',
    next_payment_amount: 99.00,
    subscription: {
      plan: 'Pro',
      status: 'active',
      billing_cycle: 'monthly',
      price: 99.00,
    },
  };

  const mockInvoices = [
    {
      id: 'inv-1',
      invoice_number: 'INV-2025-001',
      amount: 99.00,
      status: 'paid',
      due_date: '2025-01-15',
      paid_at: '2025-01-14',
    },
    {
      id: 'inv-2',
      invoice_number: 'INV-2025-002',
      amount: 99.00,
      status: 'pending',
      due_date: '2025-02-01',
      paid_at: null,
    },
  ];

  const mockPaymentMethods = [
    {
      id: 'pm-1',
      type: 'card',
      brand: 'Visa',
      last4: '4242',
      exp_month: 12,
      exp_year: 2027,
      is_default: true,
    },
    {
      id: 'pm-2',
      type: 'card',
      brand: 'Mastercard',
      last4: '5555',
      exp_month: 6,
      exp_year: 2026,
      is_default: false,
    },
  ];

  const mockPlans = [
    { id: 'plan-1', name: 'Starter', price: 29, billing_cycle: 'monthly' },
    { id: 'plan-2', name: 'Pro', price: 99, billing_cycle: 'monthly' },
    { id: 'plan-3', name: 'Enterprise', price: 299, billing_cycle: 'monthly' },
  ];

  const mockTransactions = [
    { id: 'txn-1', type: 'payment', amount: 99.00, status: 'completed', created_at: '2025-01-14T10:00:00Z' },
    { id: 'txn-2', type: 'refund', amount: 25.00, status: 'completed', created_at: '2025-01-10T10:00:00Z' },
  ];

  cy.intercept('GET', '**/api/**/billing/overview*', {
    statusCode: 200,
    body: { data: mockBillingOverview },
  }).as('getBillingOverview');

  cy.intercept('GET', '**/api/**/invoices*', {
    statusCode: 200,
    body: { items: mockInvoices },
  }).as('getInvoices');

  cy.intercept('GET', '**/api/**/invoices/*/download*', {
    statusCode: 200,
    headers: { 'content-type': 'application/pdf' },
    body: 'PDF content',
  }).as('downloadInvoice');

  cy.intercept('GET', '**/api/**/payment-methods*', {
    statusCode: 200,
    body: { items: mockPaymentMethods },
  }).as('getPaymentMethods');

  cy.intercept('GET', '**/api/**/plans*', {
    statusCode: 200,
    body: { items: mockPlans },
  }).as('getPlans');

  cy.intercept('GET', '**/api/**/transactions*', {
    statusCode: 200,
    body: { items: mockTransactions },
  }).as('getTransactions');

  cy.intercept('POST', '**/api/**/payments*', {
    statusCode: 200,
    body: { success: true, payment: { id: 'pay-new' } },
  }).as('processPayment');

  cy.intercept('POST', '**/api/**/subscriptions/change*', {
    statusCode: 200,
    body: { success: true, message: 'Plan changed' },
  }).as('changePlan');

  cy.intercept('POST', '**/api/**/subscriptions/cancel*', {
    statusCode: 200,
    body: { success: true, message: 'Subscription cancelled' },
  }).as('cancelSubscription');
}

export {};

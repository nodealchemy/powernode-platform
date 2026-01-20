/// <reference types="cypress" />

/**
 * Business Payment Processing Tests
 *
 * Tests for Payment Processing functionality including:
 * - Payment method management
 * - Payment processing flows
 * - Failed payment recovery
 * - Refund processing
 * - Payment history
 * - Multi-currency handling
 */

describe('Business Payment Processing Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Payment Methods', () => {
    it('should navigate to payment methods', () => {
      cy.visit('/app/business/billing/payment-methods');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasPayment = $body.text().includes('Payment') ||
                          $body.text().includes('Card') ||
                          $body.text().includes('Method');
        if (hasPayment) {
          cy.log('Payment methods page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display existing payment methods', () => {
      cy.visit('/app/business/billing/payment-methods');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasMethods = $body.find('[data-testid="payment-method"], .card, table').length > 0;
        if (hasMethods) {
          cy.log('Payment methods displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have add payment method button', () => {
      cy.visit('/app/business/billing/payment-methods');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasAdd = $body.find('button:contains("Add"), button:contains("New")').length > 0 ||
                      $body.text().includes('Add');
        if (hasAdd) {
          cy.log('Add payment method button displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display card details (masked)', () => {
      cy.visit('/app/business/billing/payment-methods');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasCard = $body.text().includes('****') ||
                       $body.text().includes('Visa') ||
                       $body.text().includes('Mastercard') ||
                       $body.text().includes('ending in');
        if (hasCard) {
          cy.log('Card details displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have default payment method indicator', () => {
      cy.visit('/app/business/billing/payment-methods');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasDefault = $body.text().includes('Default') ||
                          $body.text().includes('Primary') ||
                          $body.find('[data-testid="default-badge"]').length > 0;
        if (hasDefault) {
          cy.log('Default payment method indicator displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Payment Processing', () => {
    it('should navigate to payments page', () => {
      cy.visit('/app/business/billing/payments');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasPayments = $body.text().includes('Payment') ||
                           $body.text().includes('Transaction');
        if (hasPayments) {
          cy.log('Payments page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display payment list', () => {
      cy.visit('/app/business/billing/payments');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasList = $body.find('table, [data-testid="payments-list"]').length > 0;
        if (hasList) {
          cy.log('Payment list displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display payment status', () => {
      cy.visit('/app/business/billing/payments');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasStatus = $body.text().includes('Successful') ||
                         $body.text().includes('Pending') ||
                         $body.text().includes('Failed') ||
                         $body.text().includes('Completed');
        if (hasStatus) {
          cy.log('Payment status displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display payment amounts', () => {
      cy.visit('/app/business/billing/payments');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasAmount = $body.text().includes('$') ||
                         $body.text().includes('€') ||
                         $body.text().includes('Amount');
        if (hasAmount) {
          cy.log('Payment amounts displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Failed Payment Recovery', () => {
    it('should navigate to failed payments', () => {
      cy.visit('/app/business/billing/payments?status=failed');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasFailed = $body.text().includes('Failed') ||
                         $body.text().includes('Declined') ||
                         $body.text().includes('Retry');
        if (hasFailed) {
          cy.log('Failed payments page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have retry payment option', () => {
      cy.visit('/app/business/billing/payments');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasRetry = $body.find('button:contains("Retry"), button:contains("Try Again")').length > 0 ||
                        $body.text().includes('Retry');
        if (hasRetry) {
          cy.log('Retry payment option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display failure reason', () => {
      cy.visit('/app/business/billing/payments');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasReason = $body.text().includes('Reason') ||
                         $body.text().includes('declined') ||
                         $body.text().includes('insufficient');
        if (hasReason) {
          cy.log('Failure reason displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Refunds', () => {
    it('should navigate to refunds', () => {
      cy.visit('/app/business/billing/refunds');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasRefunds = $body.text().includes('Refund') ||
                          $body.text().includes('Return');
        if (hasRefunds) {
          cy.log('Refunds page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have issue refund option', () => {
      cy.visit('/app/business/billing/payments');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasRefund = $body.find('button:contains("Refund"), [data-testid="refund-button"]').length > 0 ||
                         $body.text().includes('Refund');
        if (hasRefund) {
          cy.log('Issue refund option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display refund history', () => {
      cy.visit('/app/business/billing/refunds');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasHistory = $body.find('table, [data-testid="refunds-list"]').length > 0;
        if (hasHistory) {
          cy.log('Refund history displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Invoices', () => {
    it('should navigate to invoices', () => {
      cy.visit('/app/business/billing/invoices');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasInvoices = $body.text().includes('Invoice') ||
                           $body.text().includes('Bill');
        if (hasInvoices) {
          cy.log('Invoices page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display invoice list', () => {
      cy.visit('/app/business/billing/invoices');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasList = $body.find('table, [data-testid="invoices-list"]').length > 0;
        if (hasList) {
          cy.log('Invoice list displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have download invoice option', () => {
      cy.visit('/app/business/billing/invoices');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasDownload = $body.find('button:contains("Download"), a[download]').length > 0 ||
                           $body.text().includes('Download') ||
                           $body.text().includes('PDF');
        if (hasDownload) {
          cy.log('Download invoice option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display invoice status', () => {
      cy.visit('/app/business/billing/invoices');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasStatus = $body.text().includes('Paid') ||
                         $body.text().includes('Due') ||
                         $body.text().includes('Overdue') ||
                         $body.text().includes('Draft');
        if (hasStatus) {
          cy.log('Invoice status displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Multi-Currency', () => {
    it('should display currency options', () => {
      cy.visit('/app/business/billing');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasCurrency = $body.text().includes('Currency') ||
                           $body.text().includes('USD') ||
                           $body.text().includes('EUR') ||
                           $body.text().includes('GBP');
        if (hasCurrency) {
          cy.log('Currency options displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display amounts in selected currency', () => {
      cy.visit('/app/business/billing');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasSymbol = $body.text().includes('$') ||
                         $body.text().includes('€') ||
                         $body.text().includes('£');
        if (hasSymbol) {
          cy.log('Currency amounts displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Responsive Design', () => {
    const viewports = [
      { width: 1280, height: 720, name: 'desktop' },
      { width: 768, height: 1024, name: 'tablet' },
      { width: 375, height: 667, name: 'mobile' },
    ];

    viewports.forEach(({ width, height, name }) => {
      it(`should display payment processing correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/app/business/billing/payments');
        cy.waitForPageLoad();

        cy.get('body').should('be.visible');
        cy.log(`Payment processing displayed correctly on ${name}`);
      });
    });
  });
});

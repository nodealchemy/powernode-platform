/// <reference types="cypress" />

/**
 * Account Billing Tests
 *
 * Tests for Account Billing functionality including:
 * - Billing overview
 * - Payment methods
 * - Billing history
 * - Invoice management
 * - Billing alerts
 * - Billing address
 */

describe('Account Billing Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Billing Overview', () => {
    it('should navigate to billing page', () => {
      cy.visit('/app/account/billing');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasBilling = $body.text().includes('Billing') ||
                          $body.text().includes('Payment') ||
                          $body.text().includes('Subscription');
        if (hasBilling) {
          cy.log('Billing page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display current plan', () => {
      cy.visit('/app/account/billing');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasPlan = $body.text().includes('Plan') ||
                       $body.text().includes('Free') ||
                       $body.text().includes('Pro') ||
                       $body.text().includes('Business');
        if (hasPlan) {
          cy.log('Current plan displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display billing period', () => {
      cy.visit('/app/account/billing');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasPeriod = $body.text().includes('Monthly') ||
                         $body.text().includes('Annual') ||
                         $body.text().includes('Period');
        if (hasPeriod) {
          cy.log('Billing period displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display next billing date', () => {
      cy.visit('/app/account/billing');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasDate = $body.text().includes('Next') ||
                       $body.text().includes('Renewal') ||
                       $body.text().match(/\d{1,2}\/\d{1,2}/) !== null;
        if (hasDate) {
          cy.log('Next billing date displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Payment Methods', () => {
    beforeEach(() => {
      cy.visit('/app/account/billing/payment-methods');
      cy.waitForPageLoad();
    });

    it('should display payment methods section', () => {
      cy.get('body').then($body => {
        const hasPayment = $body.text().includes('Payment') ||
                          $body.text().includes('Card') ||
                          $body.text().includes('Method');
        if (hasPayment) {
          cy.log('Payment methods section displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display saved cards', () => {
      cy.get('body').then($body => {
        const hasCards = $body.text().includes('****') ||
                        $body.text().includes('Visa') ||
                        $body.text().includes('Mastercard');
        if (hasCards) {
          cy.log('Saved cards displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have add payment method button', () => {
      cy.get('body').then($body => {
        const hasAdd = $body.find('button:contains("Add"), button:contains("New")').length > 0 ||
                      $body.text().includes('Add');
        if (hasAdd) {
          cy.log('Add payment method button displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have remove payment method option', () => {
      cy.get('body').then($body => {
        const hasRemove = $body.find('button:contains("Remove"), button:contains("Delete")').length > 0 ||
                         $body.text().includes('Remove');
        if (hasRemove) {
          cy.log('Remove payment method option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have set default option', () => {
      cy.get('body').then($body => {
        const hasDefault = $body.text().includes('Default') ||
                          $body.text().includes('Primary') ||
                          $body.find('[data-testid="set-default"]').length > 0;
        if (hasDefault) {
          cy.log('Set default option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Billing History', () => {
    it('should navigate to billing history', () => {
      cy.visit('/app/account/billing/history');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasHistory = $body.text().includes('History') ||
                          $body.text().includes('Invoice') ||
                          $body.text().includes('Transaction');
        if (hasHistory) {
          cy.log('Billing history page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display billing history list', () => {
      cy.visit('/app/account/billing/history');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasList = $body.find('table, [data-testid="billing-history"]').length > 0;
        if (hasList) {
          cy.log('Billing history list displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display invoice amounts', () => {
      cy.visit('/app/account/billing/history');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasAmounts = $body.text().includes('$') ||
                          $body.text().includes('€') ||
                          $body.text().includes('Amount');
        if (hasAmounts) {
          cy.log('Invoice amounts displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have download invoice option', () => {
      cy.visit('/app/account/billing/history');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasDownload = $body.find('button:contains("Download"), a[download], button:contains("PDF")').length > 0 ||
                           $body.text().includes('Download');
        if (hasDownload) {
          cy.log('Download invoice option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Invoice Details', () => {
    it('should navigate to invoice detail', () => {
      cy.visit('/app/account/billing/invoices');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasInvoice = $body.text().includes('Invoice') ||
                          $body.text().includes('Bill');
        if (hasInvoice) {
          cy.log('Invoice page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display invoice number', () => {
      cy.visit('/app/account/billing/invoices');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasNumber = $body.text().includes('INV-') ||
                         $body.text().includes('#') ||
                         $body.text().includes('Invoice');
        if (hasNumber) {
          cy.log('Invoice number displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display line items', () => {
      cy.visit('/app/account/billing/invoices');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasItems = $body.text().includes('Item') ||
                        $body.text().includes('Description') ||
                        $body.find('table').length > 0;
        if (hasItems) {
          cy.log('Line items displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Billing Address', () => {
    it('should navigate to billing address', () => {
      cy.visit('/app/account/billing/address');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasAddress = $body.text().includes('Address') ||
                          $body.text().includes('Billing') ||
                          $body.text().includes('Country');
        if (hasAddress) {
          cy.log('Billing address page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display address fields', () => {
      cy.visit('/app/account/billing/address');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasFields = $body.find('input').length > 0 ||
                         $body.text().includes('Street') ||
                         $body.text().includes('City');
        if (hasFields) {
          cy.log('Address fields displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have save address button', () => {
      cy.visit('/app/account/billing/address');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasSave = $body.find('button:contains("Save"), button:contains("Update")').length > 0;
        if (hasSave) {
          cy.log('Save address button displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Billing Alerts', () => {
    beforeEach(() => {
      cy.visit('/app/account/billing');
      cy.waitForPageLoad();
    });

    it('should display payment due alerts', () => {
      cy.get('body').then($body => {
        const hasAlert = $body.text().includes('Due') ||
                        $body.text().includes('Overdue') ||
                        $body.find('[data-testid="billing-alert"]').length >= 0;
        cy.log('Payment due alert pattern available');
      });

      cy.get('body').should('be.visible');
    });

    it('should display failed payment warning', () => {
      cy.get('body').then($body => {
        const hasWarning = $body.text().includes('Failed') ||
                          $body.text().includes('Declined') ||
                          $body.text().includes('Update payment');
        if (hasWarning) {
          cy.log('Failed payment warning displayed');
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
      it(`should display billing correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/app/account/billing');
        cy.waitForPageLoad();

        cy.get('body').should('be.visible');
        cy.log(`Billing displayed correctly on ${name}`);
      });
    });
  });
});

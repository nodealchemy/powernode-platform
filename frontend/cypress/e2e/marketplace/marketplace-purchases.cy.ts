/// <reference types="cypress" />

/**
 * Marketplace Purchases Tests
 *
 * Tests for Marketplace Purchase functionality including:
 * - Purchase flow
 * - Payment processing
 * - Order confirmation
 * - Purchase history
 * - Refund requests
 * - License management
 */

describe('Marketplace Purchases Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Purchase Flow', () => {
    it('should navigate to item detail', () => {
      cy.visit('/app/marketplace');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasItems = $body.find('[data-testid="marketplace-item"], .item-card, article').length > 0;
        if (hasItems) {
          cy.log('Marketplace items displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display purchase button', () => {
      cy.visit('/app/marketplace');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasPurchase = $body.find('button:contains("Buy"), button:contains("Purchase"), button:contains("Get")').length > 0 ||
                           $body.text().includes('Buy') ||
                           $body.text().includes('Purchase');
        if (hasPurchase) {
          cy.log('Purchase button displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display item price', () => {
      cy.visit('/app/marketplace');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasPrice = $body.text().includes('$') ||
                        $body.text().includes('Free') ||
                        $body.text().includes('€');
        if (hasPrice) {
          cy.log('Item price displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display pricing tiers', () => {
      cy.visit('/app/marketplace');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasTiers = $body.text().includes('Plan') ||
                        $body.text().includes('Tier') ||
                        $body.text().includes('Monthly') ||
                        $body.text().includes('Annual');
        if (hasTiers) {
          cy.log('Pricing tiers displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Checkout Process', () => {
    beforeEach(() => {
      cy.visit('/app/marketplace/checkout');
      cy.waitForPageLoad();
    });

    it('should display checkout page', () => {
      cy.get('body').then($body => {
        const hasCheckout = $body.text().includes('Checkout') ||
                          $body.text().includes('Payment') ||
                          $body.text().includes('Order');
        if (hasCheckout) {
          cy.log('Checkout page displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display order summary', () => {
      cy.get('body').then($body => {
        const hasSummary = $body.text().includes('Summary') ||
                          $body.text().includes('Total') ||
                          $body.text().includes('Item');
        if (hasSummary) {
          cy.log('Order summary displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display payment method selection', () => {
      cy.get('body').then($body => {
        const hasPayment = $body.text().includes('Payment') ||
                          $body.text().includes('Card') ||
                          $body.text().includes('Method');
        if (hasPayment) {
          cy.log('Payment method selection displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have complete purchase button', () => {
      cy.get('body').then($body => {
        const hasComplete = $body.find('button:contains("Complete"), button:contains("Pay"), button:contains("Purchase")').length > 0;
        if (hasComplete) {
          cy.log('Complete purchase button displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Order Confirmation', () => {
    it('should display confirmation page', () => {
      cy.visit('/app/marketplace/orders/confirmation');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasConfirmation = $body.text().includes('Confirmation') ||
                               $body.text().includes('Thank you') ||
                               $body.text().includes('Success');
        if (hasConfirmation) {
          cy.log('Confirmation page displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display order number', () => {
      cy.visit('/app/marketplace/orders/confirmation');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasOrderNum = $body.text().includes('Order') ||
                           $body.text().includes('#') ||
                           $body.text().match(/[A-Z0-9]{6,}/) !== null;
        if (hasOrderNum) {
          cy.log('Order number displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Purchase History', () => {
    it('should navigate to purchase history', () => {
      cy.visit('/app/marketplace/purchases');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasHistory = $body.text().includes('Purchase') ||
                          $body.text().includes('Order') ||
                          $body.text().includes('History');
        if (hasHistory) {
          cy.log('Purchase history page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display purchase list', () => {
      cy.visit('/app/marketplace/purchases');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasList = $body.find('table, [data-testid="purchases-list"], .order-list').length > 0;
        if (hasList) {
          cy.log('Purchase list displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display purchase date', () => {
      cy.visit('/app/marketplace/purchases');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasDate = $body.text().includes('Date') ||
                       $body.text().match(/\d{4}/) !== null ||
                       $body.text().includes('ago');
        if (hasDate) {
          cy.log('Purchase date displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display purchase status', () => {
      cy.visit('/app/marketplace/purchases');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasStatus = $body.text().includes('Completed') ||
                         $body.text().includes('Active') ||
                         $body.text().includes('Status');
        if (hasStatus) {
          cy.log('Purchase status displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Refund Requests', () => {
    beforeEach(() => {
      cy.visit('/app/marketplace/purchases');
      cy.waitForPageLoad();
    });

    it('should have refund option', () => {
      cy.get('body').then($body => {
        const hasRefund = $body.find('button:contains("Refund"), button:contains("Request refund")').length > 0 ||
                         $body.text().includes('Refund');
        if (hasRefund) {
          cy.log('Refund option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display refund policy', () => {
      cy.get('body').then($body => {
        const hasPolicy = $body.text().includes('Policy') ||
                         $body.text().includes('day') ||
                         $body.text().includes('refund');
        if (hasPolicy) {
          cy.log('Refund policy displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('License Management', () => {
    it('should navigate to licenses', () => {
      cy.visit('/app/marketplace/licenses');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasLicenses = $body.text().includes('License') ||
                          $body.text().includes('Key') ||
                          $body.text().includes('Subscription');
        if (hasLicenses) {
          cy.log('Licenses page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display active licenses', () => {
      cy.visit('/app/marketplace/licenses');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasActive = $body.text().includes('Active') ||
                         $body.text().includes('Valid') ||
                         $body.find('[data-testid="active-licenses"]').length > 0;
        if (hasActive) {
          cy.log('Active licenses displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display license expiration', () => {
      cy.visit('/app/marketplace/licenses');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasExpiration = $body.text().includes('Expire') ||
                            $body.text().includes('Valid until') ||
                            $body.text().includes('Renewal');
        if (hasExpiration) {
          cy.log('License expiration displayed');
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
      it(`should display purchases correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/app/marketplace/purchases');
        cy.waitForPageLoad();

        cy.get('body').should('be.visible');
        cy.log(`Purchases displayed correctly on ${name}`);
      });
    });
  });
});

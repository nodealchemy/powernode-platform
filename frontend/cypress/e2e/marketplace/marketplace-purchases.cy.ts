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
      cy.assertHasElement(['[data-testid="marketplace-item"]', '.item-card', 'article']);
    });

    it('should display purchase button', () => {
      cy.visit('/app/marketplace');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Buy', 'Purchase']);
    });

    it('should display item price', () => {
      cy.visit('/app/marketplace');
      cy.waitForPageLoad();
      cy.assertContainsAny(['$', 'Free', '€']);
    });

    it('should display pricing tiers', () => {
      cy.visit('/app/marketplace');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Plan', 'Tier', 'Monthly', 'Annual']);
    });
  });

  describe('Checkout Process', () => {
    beforeEach(() => {
      cy.visit('/app/marketplace/checkout');
      cy.waitForPageLoad();
    });

    it('should display checkout page', () => {
      cy.assertContainsAny(['Checkout', 'Payment', 'Order']);
    });

    it('should display order summary', () => {
      cy.assertContainsAny(['Summary', 'Total', 'Item']);
    });

    it('should display payment method selection', () => {
      cy.assertContainsAny(['Payment', 'Card', 'Method']);
    });

    it('should have complete purchase button', () => {
      cy.assertHasElement(['button:contains("Complete")', 'button:contains("Pay")', 'button:contains("Purchase")']);
    });
  });

  describe('Order Confirmation', () => {
    it('should display confirmation page', () => {
      cy.visit('/app/marketplace/orders/confirmation');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Confirmation', 'Thank you', 'Success']);
    });

    it('should display order number', () => {
      cy.visit('/app/marketplace/orders/confirmation');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Order', '#']);
    });
  });

  describe('Purchase History', () => {
    it('should navigate to purchase history', () => {
      cy.visit('/app/marketplace/purchases');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Purchase', 'Order', 'History']);
    });

    it('should display purchase list', () => {
      cy.visit('/app/marketplace/purchases');
      cy.waitForPageLoad();
      cy.assertHasElement(['table', '[data-testid="purchases-list"]', '.order-list']);
    });

    it('should display purchase date', () => {
      cy.visit('/app/marketplace/purchases');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Date', 'ago']);
    });

    it('should display purchase status', () => {
      cy.visit('/app/marketplace/purchases');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Completed', 'Active', 'Status']);
    });
  });

  describe('Refund Requests', () => {
    beforeEach(() => {
      cy.visit('/app/marketplace/purchases');
      cy.waitForPageLoad();
    });

    it('should have refund option', () => {
      cy.assertContainsAny(['Refund']);
    });

    it('should display refund policy', () => {
      cy.assertContainsAny(['Policy', 'day', 'refund']);
    });
  });

  describe('License Management', () => {
    it('should navigate to licenses', () => {
      cy.visit('/app/marketplace/licenses');
      cy.waitForPageLoad();
      cy.assertContainsAny(['License', 'Key', 'Subscription']);
    });

    it('should display active licenses', () => {
      cy.visit('/app/marketplace/licenses');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Active', 'Valid']);
    });

    it('should display license expiration', () => {
      cy.visit('/app/marketplace/licenses');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Expire', 'Valid until', 'Renewal']);
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

        cy.assertContainsAny(['Purchases', 'Marketplace']);
        cy.log(`Purchases displayed correctly on ${name}`);
      });
    });
  });
});

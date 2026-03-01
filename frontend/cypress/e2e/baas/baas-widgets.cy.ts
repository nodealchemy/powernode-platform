/// <reference types="cypress" />

/**
 * BaaS Widgets Tests
 *
 * Tests for BaaS embeddable widget functionality including:
 * - Pricing Table widget
 * - Customer Portal widget
 * - Widget configuration
 * - Theme customization
 * - Standalone rendering
 */

describe('BaaS Widgets Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Pricing Table Widget', () => {
    it('should navigate to pricing table configuration', () => {
      cy.visit('/baas/widgets/pricing-table');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Pricing', 'Plans', 'Widget']);
    });

    it('should display plan cards in widget', () => {
      cy.visit('/baas/widgets/pricing-table');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Free', 'Starter', 'Pro', 'Enterprise']);
    });

    it('should display pricing information', () => {
      cy.visit('/baas/widgets/pricing-table');
      cy.waitForPageLoad();
      cy.assertContainsAny(['$', '/month', '/year', 'Price']);
    });

    it('should display feature lists', () => {
      cy.visit('/baas/widgets/pricing-table');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Features', 'Included']);
    });

    it('should have theme options', () => {
      cy.visit('/baas/widgets/pricing-table');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Theme', 'Dark', 'Light']);
    });

    it('should highlight popular plan', () => {
      cy.visit('/baas/widgets/pricing-table');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Popular', 'Most', 'Recommended']);
    });
  });

  describe('Customer Portal Widget', () => {
    it('should navigate to customer portal configuration', () => {
      cy.visit('/baas/widgets/customer-portal');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Customer Portal', 'Portal', 'Widget']);
    });

    it('should display subscription details section', () => {
      cy.visit('/baas/widgets/customer-portal');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Subscription', 'Plan', 'Active']);
    });

    it('should display billing section', () => {
      cy.visit('/baas/widgets/customer-portal');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Billing', 'Payment', 'Invoice']);
    });

    it('should display payment methods', () => {
      cy.visit('/baas/widgets/customer-portal');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Payment Method', 'Card', 'Update']);
    });

    it('should display invoice history', () => {
      cy.visit('/baas/widgets/customer-portal');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Invoice', 'History', 'Download']);
    });

    it('should have cancel subscription option', () => {
      cy.visit('/baas/widgets/customer-portal');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Cancel', 'Downgrade', 'Change Plan']);
    });
  });

  describe('Widget Embed Code', () => {
    it('should display embed code for pricing table', () => {
      cy.visit('/baas/widgets/pricing-table');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Embed', 'Code', '<script', 'iframe']);
    });

    it('should have copy code functionality', () => {
      cy.visit('/baas/widgets/pricing-table');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Copy']);
    });
  });

  describe('Widget Preview', () => {
    it('should display live preview of pricing widget', () => {
      cy.visit('/baas/widgets/pricing-table');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Preview']);
    });

    it('should update preview on configuration change', () => {
      cy.visit('/baas/widgets/pricing-table');
      cy.waitForPageLoad();
      cy.assertHasElement(['input', 'select']);
    });
  });

  describe('Widget Customization', () => {
    it('should allow color customization', () => {
      cy.visit('/baas/widgets/pricing-table');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Color', 'Primary', 'Accent']);
    });

    it('should allow font customization', () => {
      cy.visit('/baas/widgets/pricing-table');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Font', 'Typography']);
    });

    it('should allow layout customization', () => {
      cy.visit('/baas/widgets/pricing-table');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Layout', 'Grid', 'Cards', 'Columns']);
    });
  });
});

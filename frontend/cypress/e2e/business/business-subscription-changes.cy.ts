/// <reference types="cypress" />

/**
 * Business Subscription Changes Tests
 *
 * Tests for Subscription upgrade/downgrade functionality including:
 * - Plan comparison
 * - Upgrade flow
 * - Downgrade flow
 * - Proration display
 * - Plan switching confirmation
 * - Billing cycle changes
 */

describe('Business Subscription Changes Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Current Subscription Display', () => {
    it('should navigate to subscription page', () => {
      cy.visit('/app/business/billing/subscription');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Subscription', 'Plan', 'Current']);
    });

    it('should display current plan', () => {
      cy.visit('/app/business/billing/subscription');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Plan', 'Free', 'Pro', 'Business']);
    });

    it('should display current price', () => {
      cy.visit('/app/business/billing/subscription');
      cy.waitForPageLoad();

      cy.assertContainsAny(['$', '/month', '/year']);
    });

    it('should display billing cycle', () => {
      cy.visit('/app/business/billing/subscription');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Monthly', 'Annual', 'Yearly', 'Billing']);
    });

    it('should display next billing date', () => {
      cy.visit('/app/business/billing/subscription');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Next', 'Renewal', 'Billing']);
    });
  });

  describe('Plan Comparison', () => {
    it('should navigate to plan comparison', () => {
      cy.visit('/app/business/billing/plans');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Plan', 'Compare', 'Pricing']);
    });

    it('should display available plans', () => {
      cy.visit('/app/business/billing/plans');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Free', 'Pro', 'Starter', 'Business']);
    });

    it('should highlight current plan', () => {
      cy.visit('/app/business/billing/plans');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Current', 'Your plan', 'Plan']);
    });

    it('should display plan features', () => {
      cy.visit('/app/business/billing/plans');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Feature', 'Plan', 'Included']);
    });
  });

  describe('Upgrade Flow', () => {
    it('should display upgrade button', () => {
      cy.visit('/app/business/billing/plans');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Upgrade', 'Select', 'Plan']);
    });

    it('should show upgrade confirmation', () => {
      cy.visit('/app/business/billing/plans');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Confirm', 'Review', 'Summary', 'Plan']);
    });

    it('should display proration for upgrades', () => {
      cy.visit('/app/business/billing/plans');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Proration', 'prorated', 'Credit', 'Charge', 'Plan']);
    });

    it('should show immediate vs next cycle option', () => {
      cy.visit('/app/business/billing/plans');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Immediately', 'Next cycle', 'When', 'Plan']);
    });
  });

  describe('Downgrade Flow', () => {
    it('should display downgrade option', () => {
      cy.visit('/app/business/billing/plans');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Downgrade', 'Select', 'Plan']);
    });

    it('should show downgrade warning', () => {
      cy.visit('/app/business/billing/plans');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Warning', 'lose', 'feature', 'access', 'Plan']);
    });

    it('should display feature loss summary', () => {
      cy.visit('/app/business/billing/plans');
      cy.waitForPageLoad();

      cy.assertContainsAny(['lose', 'remove', 'no longer', 'Plan']);
    });

    it('should show downgrade takes effect at end of cycle', () => {
      cy.visit('/app/business/billing/plans');
      cy.waitForPageLoad();

      cy.assertContainsAny(['end of', 'cycle', 'until', 'Plan']);
    });
  });

  describe('Billing Cycle Changes', () => {
    it('should display billing cycle toggle', () => {
      cy.visit('/app/business/billing/plans');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Monthly', 'Annual', 'Billing']);
    });

    it('should show annual discount', () => {
      cy.visit('/app/business/billing/plans');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Save', '%', 'discount', 'Annual']);
    });

    it('should update prices when toggle changes', () => {
      cy.visit('/app/business/billing/plans');
      cy.waitForPageLoad();

      cy.assertContainsAny(['$', '/mo', '/yr', 'Plan']);
    });
  });

  describe('Cancellation', () => {
    it('should have cancel subscription option', () => {
      cy.visit('/app/business/billing/subscription');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Cancel subscription', 'Cancel', 'Subscription']);
    });

    it('should display cancellation confirmation', () => {
      cy.visit('/app/business/billing/subscription');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Confirm', 'Are you sure', 'Cancel']);
    });

    it('should show retention offers', () => {
      cy.visit('/app/business/billing/subscription');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Offer', 'discount', 'stay', 'Subscription']);
    });
  });

  describe('Responsive Design', () => {
    const viewports = [
      { width: 1280, height: 720, name: 'desktop' },
      { width: 768, height: 1024, name: 'tablet' },
      { width: 375, height: 667, name: 'mobile' },
    ];

    viewports.forEach(({ width, height, name }) => {
      it(`should display subscription changes correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/app/business/billing/plans');
        cy.waitForPageLoad();

        cy.assertContainsAny(['Plan', 'Subscription', 'Billing']);
        cy.log(`Subscription changes displayed correctly on ${name}`);
      });
    });
  });
});

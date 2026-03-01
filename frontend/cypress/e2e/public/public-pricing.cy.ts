/// <reference types="cypress" />

/**
 * Public Pricing Page Tests
 *
 * Tests for Public Pricing functionality including:
 * - Pricing page display
 * - Plan comparison
 * - Plan features
 * - Price display
 * - CTA buttons
 * - FAQ section
 * - Contact/Enterprise options
 */

describe('Public Pricing Page Tests', () => {
  describe('Pricing Page Access', () => {
    it('should load pricing page', () => {
      cy.visit('/pricing');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Pricing', 'Plans', 'Price']);
    });

    it('should display pricing header', () => {
      cy.visit('/pricing');
      cy.waitForPageLoad();
      cy.assertHasElement(['h1', 'h2']);
    });
  });

  describe('Plan Cards', () => {
    beforeEach(() => {
      cy.visit('/pricing');
      cy.waitForPageLoad();
    });

    it('should display multiple plan options', () => {
      cy.assertContainsAny(['Free', 'Starter', 'Pro', 'Business', 'Enterprise']);
    });

    it('should display plan prices', () => {
      cy.assertContainsAny(['$', '/month', '/year', 'Free']);
    });

    it('should display plan features', () => {
      cy.assertHasElement(['ul li', '[data-testid="plan-features"]']);
    });

    it('should highlight recommended plan', () => {
      cy.assertContainsAny(['Popular', 'Recommended', 'Best value']);
    });
  });

  describe('CTA Buttons', () => {
    beforeEach(() => {
      cy.visit('/pricing');
      cy.waitForPageLoad();
    });

    it('should display Get Started buttons', () => {
      cy.assertContainsAny(['Get Started', 'Sign up']);
    });

    it('should display Contact Sales for Enterprise', () => {
      cy.assertContainsAny(['Contact', 'Sales', 'Get in touch']);
    });
  });

  describe('Billing Toggle', () => {
    beforeEach(() => {
      cy.visit('/pricing');
      cy.waitForPageLoad();
    });

    it('should display monthly/annual toggle', () => {
      cy.assertContainsAny(['Monthly', 'Annual', 'Yearly']);
    });

    it('should show annual discount', () => {
      cy.assertContainsAny(['Save', '%', 'discount']);
    });
  });

  describe('Feature Comparison', () => {
    beforeEach(() => {
      cy.visit('/pricing');
      cy.waitForPageLoad();
    });

    it('should display feature comparison table', () => {
      cy.assertContainsAny(['Compare', 'Features']);
    });
  });

  describe('FAQ Section', () => {
    beforeEach(() => {
      cy.visit('/pricing');
      cy.waitForPageLoad();
    });

    it('should display FAQ section', () => {
      cy.assertContainsAny(['FAQ', 'Frequently Asked', 'Questions']);
    });

    it('should have expandable FAQ items', () => {
      cy.assertHasElement(['[data-testid="faq-item"]', 'details', '[role="button"]']);
    });
  });

  describe('Responsive Design', () => {
    const viewports = [
      { width: 1280, height: 720, name: 'desktop' },
      { width: 768, height: 1024, name: 'tablet' },
      { width: 375, height: 667, name: 'mobile' },
    ];

    viewports.forEach(({ width, height, name }) => {
      it(`should display pricing page correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/pricing');
        cy.waitForPageLoad();

        cy.assertContainsAny(['Pricing', 'Plans']);
        cy.log(`Pricing page displayed correctly on ${name}`);
      });
    });
  });
});

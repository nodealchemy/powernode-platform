/// <reference types="cypress" />

/**
 * Public Features Page Tests
 *
 * Tests for Features Page functionality including:
 * - Feature categories display
 * - Individual feature details
 * - Feature comparisons
 * - Integration with pricing
 * - Responsive design
 */

describe('Public Features Page Tests', () => {
  describe('Features Page Access', () => {
    it('should load features page', () => {
      cy.visit('/features');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Features', 'Capabilities', 'What']);
    });

    it('should display features header', () => {
      cy.visit('/features');
      cy.waitForPageLoad();
      cy.assertHasElement(['h1', 'h2']);
    });
  });

  describe('Feature Categories', () => {
    beforeEach(() => {
      cy.visit('/features');
      cy.waitForPageLoad();
    });

    it('should display billing features', () => {
      cy.assertContainsAny(['Billing', 'Subscription', 'Payment']);
    });

    it('should display analytics features', () => {
      cy.assertContainsAny(['Analytics', 'Reports', 'Insights']);
    });

    it('should display automation features', () => {
      cy.assertContainsAny(['Automation', 'Workflow', 'AI']);
    });

    it('should display integration features', () => {
      cy.assertContainsAny(['Integration', 'API', 'Connect']);
    });
  });

  describe('Feature Details', () => {
    beforeEach(() => {
      cy.visit('/features');
      cy.waitForPageLoad();
    });

    it('should display feature descriptions', () => {
      cy.assertHasElement(['p', '.description', '[data-testid*="feature"]']);
    });

    it('should display feature icons or images', () => {
      cy.assertHasElement(['img', 'svg', '[data-testid*="icon"]']);
    });
  });

  describe('Call-to-Action', () => {
    beforeEach(() => {
      cy.visit('/features');
      cy.waitForPageLoad();
    });

    it('should have link to pricing', () => {
      cy.assertContainsAny(['Pricing', 'Plans']);
    });

    it('should have get started button', () => {
      cy.assertContainsAny(['Get Started', 'Try', 'Sign up']);
    });
  });

  describe('Responsive Design', () => {
    const viewports = [
      { width: 1280, height: 720, name: 'desktop' },
      { width: 768, height: 1024, name: 'tablet' },
      { width: 375, height: 667, name: 'mobile' },
    ];

    viewports.forEach(({ width, height, name }) => {
      it(`should display features page correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/features');
        cy.waitForPageLoad();

        cy.assertContainsAny(['Features', 'Capabilities']);
        cy.log(`Features page displayed correctly on ${name}`);
      });
    });
  });
});

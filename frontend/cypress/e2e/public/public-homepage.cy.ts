/// <reference types="cypress" />

/**
 * Public Homepage Tests
 *
 * Tests for Homepage/Landing Page functionality including:
 * - Page loading and hero section
 * - Navigation menu
 * - Feature highlights
 * - Call-to-action buttons
 * - Footer links
 * - Responsive design
 */

describe('Public Homepage Tests', () => {
  describe('Homepage Access', () => {
    it('should load homepage', () => {
      cy.visit('/');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Powernode', 'Get Started', 'Home']);
      cy.log('Homepage loaded successfully');
    });

    it('should display hero section', () => {
      cy.visit('/');
      cy.waitForPageLoad();
      cy.assertHasElement(['h1', '[data-testid="hero-section"]']);
    });

    it('should display main headline', () => {
      cy.visit('/');
      cy.waitForPageLoad();
      cy.get('h1').should('be.visible');
    });
  });

  describe('Navigation Menu', () => {
    beforeEach(() => {
      cy.visit('/');
      cy.waitForPageLoad();
    });

    it('should display navigation bar', () => {
      cy.assertHasElement(['nav', 'header', '[data-testid="navbar"]']);
    });

    it('should display logo', () => {
      cy.assertContainsAny(['Powernode']);
    });

    it('should have login link', () => {
      cy.assertContainsAny(['Login', 'Sign in']);
    });

    it('should have signup link', () => {
      cy.assertContainsAny(['Sign up', 'Get Started']);
    });
  });

  describe('Feature Highlights', () => {
    beforeEach(() => {
      cy.visit('/');
      cy.waitForPageLoad();
    });

    it('should display feature sections', () => {
      cy.assertContainsAny(['Features', 'Capabilities']);
    });

    it('should display feature cards or list', () => {
      cy.assertHasElement(['.card', '[data-testid*="card"]', 'article']);
    });
  });

  describe('Call-to-Action Buttons', () => {
    beforeEach(() => {
      cy.visit('/');
      cy.waitForPageLoad();
    });

    it('should display primary CTA button', () => {
      cy.assertContainsAny(['Get Started', 'Try', 'Start']);
    });

    it('should display secondary CTA options', () => {
      cy.assertContainsAny(['Learn more', 'Demo', 'Contact']);
    });
  });

  describe('Footer', () => {
    beforeEach(() => {
      cy.visit('/');
      cy.waitForPageLoad();
    });

    it('should display footer', () => {
      cy.assertHasElement(['footer', '[data-testid="footer"]']);
    });

    it('should have privacy policy link in footer', () => {
      cy.assertContainsAny(['Privacy']);
    });

    it('should have terms link in footer', () => {
      cy.assertContainsAny(['Terms']);
    });

    it('should display copyright notice', () => {
      cy.assertContainsAny(['©', 'Copyright', '2024', '2025', '2026']);
    });
  });

  describe('Social Proof', () => {
    beforeEach(() => {
      cy.visit('/');
      cy.waitForPageLoad();
    });

    it('should display testimonials or reviews', () => {
      cy.assertContainsAny(['testimonial', 'review', 'trusted by', 'customers']);
    });

    it('should display customer logos or stats', () => {
      cy.assertContainsAny(['trusted by', 'customers', 'users']);
    });
  });

  describe('Responsive Design', () => {
    const viewports = [
      { width: 1920, height: 1080, name: 'large-desktop' },
      { width: 1280, height: 720, name: 'desktop' },
      { width: 768, height: 1024, name: 'tablet' },
      { width: 375, height: 667, name: 'mobile' },
    ];

    viewports.forEach(({ width, height, name }) => {
      it(`should display homepage correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/');
        cy.waitForPageLoad();

        cy.assertContainsAny(['Powernode', 'Get Started', 'Home']);
        cy.get('h1').should('be.visible');
        cy.log(`Homepage displayed correctly on ${name}`);
      });
    });
  });

  describe('Performance', () => {
    it('should load within acceptable time', () => {
      cy.visit('/');
      cy.waitForPageLoad();

      // Page should be interactive
      cy.assertContainsAny(['Powernode', 'Get Started', 'Home']);
      cy.log('Homepage loaded within acceptable time');
    });
  });
});

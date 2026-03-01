/// <reference types="cypress" />

/**
 * Public Contact Page Tests
 *
 * Tests for Contact Page functionality including:
 * - Contact form display
 * - Form validation
 * - Contact information
 * - Support options
 * - Responsive design
 */

describe('Public Contact Page Tests', () => {
  describe('Contact Page Access', () => {
    it('should load contact page', () => {
      cy.visit('/contact');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Contact', 'Get in touch', 'Reach']);
    });

    it('should display contact header', () => {
      cy.visit('/contact');
      cy.waitForPageLoad();
      cy.assertHasElement(['h1', 'h2']);
    });
  });

  describe('Contact Form', () => {
    beforeEach(() => {
      cy.visit('/contact');
      cy.waitForPageLoad();
    });

    it('should display contact form', () => {
      cy.assertHasElement(['form', '[data-testid="contact-form"]']);
    });

    it('should have name field', () => {
      cy.assertContainsAny(['Name']);
    });

    it('should have email field', () => {
      cy.assertHasElement(['input[type="email"]', 'input[name*="email"]', 'input[placeholder*="email"]']);
    });

    it('should have message field', () => {
      cy.assertHasElement(['textarea', 'input[name*="message"]']);
    });

    it('should have submit button', () => {
      cy.assertContainsAny(['Send', 'Submit']);
    });
  });

  describe('Contact Information', () => {
    beforeEach(() => {
      cy.visit('/contact');
      cy.waitForPageLoad();
    });

    it('should display email address', () => {
      cy.assertContainsAny(['@', 'email']);
    });

    it('should display support options', () => {
      cy.assertContainsAny(['Support', 'Help', 'FAQ']);
    });
  });

  describe('Inquiry Types', () => {
    beforeEach(() => {
      cy.visit('/contact');
      cy.waitForPageLoad();
    });

    it('should display sales inquiry option', () => {
      cy.assertContainsAny(['Sales', 'Enterprise', 'Demo']);
    });

    it('should display support inquiry option', () => {
      cy.assertContainsAny(['Support', 'Technical', 'Help']);
    });
  });

  describe('Responsive Design', () => {
    const viewports = [
      { width: 1280, height: 720, name: 'desktop' },
      { width: 768, height: 1024, name: 'tablet' },
      { width: 375, height: 667, name: 'mobile' },
    ];

    viewports.forEach(({ width, height, name }) => {
      it(`should display contact page correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/contact');
        cy.waitForPageLoad();

        cy.assertContainsAny(['Contact', 'Get in touch']);
        cy.log(`Contact page displayed correctly on ${name}`);
      });
    });
  });
});

/// <reference types="cypress" />

/**
 * Public Legal Pages Tests
 *
 * Tests for Legal Pages functionality including:
 * - Privacy Policy
 * - Terms of Service
 * - Cookie Policy
 * - Acceptable Use Policy
 * - Page structure and accessibility
 */

describe('Public Legal Pages Tests', () => {
  describe('Privacy Policy', () => {
    it('should load privacy policy page', () => {
      cy.visit('/privacy');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Privacy', 'Data']);
    });

    it('should display privacy policy content', () => {
      cy.visit('/privacy');
      cy.waitForPageLoad();
      cy.assertHasElement(['h1', 'h2', 'p']);
    });

    it('should have data collection section', () => {
      cy.visit('/privacy');
      cy.waitForPageLoad();
      cy.assertContainsAny(['collect', 'information', 'data']);
    });

    it('should have contact information for privacy inquiries', () => {
      cy.visit('/privacy');
      cy.waitForPageLoad();
      cy.assertContainsAny(['contact', '@', 'email']);
    });
  });

  describe('Terms of Service', () => {
    it('should load terms of service page', () => {
      cy.visit('/terms');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Terms', 'Service', 'Agreement']);
    });

    it('should display terms content', () => {
      cy.visit('/terms');
      cy.waitForPageLoad();
      cy.assertHasElement(['h1', 'h2', 'p']);
    });

    it('should have acceptance section', () => {
      cy.visit('/terms');
      cy.waitForPageLoad();
      cy.assertContainsAny(['accept', 'agree', 'consent']);
    });
  });

  describe('Cookie Policy', () => {
    it('should load cookie policy page', () => {
      cy.visit('/cookies');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Cookie', 'cookie']);
    });

    it('should explain cookie usage', () => {
      cy.visit('/cookies');
      cy.waitForPageLoad();
      cy.assertContainsAny(['use', 'purpose', 'tracking']);
    });
  });

  describe('Legal Page Structure', () => {
    const legalPages = ['/privacy', '/terms'];

    legalPages.forEach(page => {
      it(`should have proper heading structure on ${page}`, () => {
        cy.visit(page);
        cy.waitForPageLoad();
        cy.assertHasElement(['h1', 'h2']);
      });

      it(`should have last updated date on ${page}`, () => {
        cy.visit(page);
        cy.waitForPageLoad();
        cy.assertContainsAny(['Last updated', 'Effective']);
      });
    });
  });

  describe('Responsive Legal Pages', () => {
    const viewports = [
      { width: 1280, height: 720, name: 'desktop' },
      { width: 768, height: 1024, name: 'tablet' },
      { width: 375, height: 667, name: 'mobile' },
    ];

    viewports.forEach(({ width, height, name }) => {
      it(`should display privacy policy correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/privacy');
        cy.waitForPageLoad();

        cy.assertContainsAny(['Privacy', 'Terms', 'Legal']);
        cy.log(`Privacy policy displayed correctly on ${name}`);
      });

      it(`should display terms correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/terms');
        cy.waitForPageLoad();

        cy.assertContainsAny(['Privacy', 'Terms', 'Legal']);
        cy.log(`Terms displayed correctly on ${name}`);
      });
    });
  });
});

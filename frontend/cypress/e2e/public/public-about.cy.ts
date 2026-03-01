/// <reference types="cypress" />

/**
 * Public About Page Tests
 *
 * Tests for About Page functionality including:
 * - Company information
 * - Team section
 * - Mission/Vision
 * - Company history
 * - Contact links
 * - Responsive design
 */

describe('Public About Page Tests', () => {
  describe('About Page Access', () => {
    it('should load about page', () => {
      cy.visit('/about');
      cy.waitForPageLoad();
      cy.assertContainsAny(['About', 'Company', 'Who we are']);
    });

    it('should display about header', () => {
      cy.visit('/about');
      cy.waitForPageLoad();
      cy.assertHasElement(['h1', 'h2']);
    });
  });

  describe('Company Information', () => {
    beforeEach(() => {
      cy.visit('/about');
      cy.waitForPageLoad();
    });

    it('should display company description', () => {
      cy.assertHasElement(['p', '.description', '[data-testid="company-description"]']);
    });

    it('should display mission or vision statement', () => {
      cy.assertContainsAny(['Mission', 'Vision', 'believe', 'goal']);
    });

    it('should display company values', () => {
      cy.assertContainsAny(['Values', 'principles', 'commitment']);
    });
  });

  describe('Team Section', () => {
    beforeEach(() => {
      cy.visit('/about');
      cy.waitForPageLoad();
    });

    it('should display team section', () => {
      cy.assertContainsAny(['Team', 'People', 'Leadership']);
    });

    it('should display team member photos or avatars', () => {
      cy.assertHasElement(['img[alt*="team"]', 'img[alt*="founder"]', '.avatar']);
    });
  });

  describe('Company Stats', () => {
    beforeEach(() => {
      cy.visit('/about');
      cy.waitForPageLoad();
    });

    it('should display company statistics', () => {
      cy.assertContainsAny(['customers', 'countries', 'users']);
    });
  });

  describe('Call-to-Action', () => {
    beforeEach(() => {
      cy.visit('/about');
      cy.waitForPageLoad();
    });

    it('should have contact or careers link', () => {
      cy.assertContainsAny(['Contact', 'Join', 'Careers']);
    });
  });

  describe('Responsive Design', () => {
    const viewports = [
      { width: 1280, height: 720, name: 'desktop' },
      { width: 768, height: 1024, name: 'tablet' },
      { width: 375, height: 667, name: 'mobile' },
    ];

    viewports.forEach(({ width, height, name }) => {
      it(`should display about page correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/about');
        cy.waitForPageLoad();

        cy.assertContainsAny(['About', 'Our story']);
        cy.log(`About page displayed correctly on ${name}`);
      });
    });
  });
});

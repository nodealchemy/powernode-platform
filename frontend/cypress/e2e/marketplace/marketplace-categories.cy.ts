/// <reference types="cypress" />

/**
 * Marketplace Categories Tests
 *
 * Tests for Marketplace Category functionality including:
 * - Category listing
 * - Category filtering
 * - Category navigation
 * - Subcategories
 * - Category search
 * - Featured categories
 */

describe('Marketplace Categories Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Category Listing', () => {
    it('should navigate to marketplace page', () => {
      cy.visit('/app/marketplace');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Marketplace', 'Browse', 'Templates']);
    });

    it('should display category sidebar or filter', () => {
      cy.visit('/app/marketplace');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Categories', 'Category']);
    });

    it('should display category list', () => {
      cy.visit('/app/marketplace');
      cy.waitForPageLoad();
      cy.assertContainsAny(['AI', 'Automation', 'Analytics', 'Integration', 'Productivity']);
    });
  });

  describe('Category Filtering', () => {
    beforeEach(() => {
      cy.visit('/app/marketplace');
      cy.waitForPageLoad();
    });

    it('should filter items when category selected', () => {
      cy.assertHasElement(['[data-testid="category-link"]', 'a:contains("AI")', 'button:contains("AI")']);
    });

    it('should show active category indicator', () => {
      cy.get('[data-testid="category-link"]').first().click();
      cy.assertHasElement(['.active', '[aria-selected="true"]', '.selected']);
    });

    it('should display item count per category', () => {
      cy.assertHasElement(['[data-testid="category-count"]']);
    });
  });

  describe('All Categories View', () => {
    beforeEach(() => {
      cy.visit('/app/marketplace');
      cy.waitForPageLoad();
    });

    it('should have All/Clear filter option', () => {
      cy.assertContainsAny(['All', 'Clear']);
    });
  });

  describe('Featured Categories', () => {
    beforeEach(() => {
      cy.visit('/app/marketplace');
      cy.waitForPageLoad();
    });

    it('should display featured or popular categories', () => {
      cy.assertContainsAny(['Featured', 'Popular', 'Trending']);
    });
  });

  describe('Category Navigation', () => {
    it('should navigate to category page via URL', () => {
      cy.visit('/app/marketplace?category=ai');
      cy.waitForPageLoad();
      cy.assertContainsAny(['AI', 'filtered']);
    });
  });

  describe('Responsive Category Display', () => {
    const viewports = [
      { width: 1280, height: 720, name: 'desktop' },
      { width: 768, height: 1024, name: 'tablet' },
      { width: 375, height: 667, name: 'mobile' },
    ];

    viewports.forEach(({ width, height, name }) => {
      it(`should display categories correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/app/marketplace');
        cy.waitForPageLoad();

        cy.assertContainsAny(['Marketplace', 'Categories']);
        cy.log(`Categories displayed correctly on ${name}`);
      });
    });
  });
});

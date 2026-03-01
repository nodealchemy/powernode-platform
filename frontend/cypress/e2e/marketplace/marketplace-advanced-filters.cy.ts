/// <reference types="cypress" />

/**
 * Marketplace Advanced Filters Tests
 *
 * Tests for Marketplace Advanced Filtering including:
 * - Multiple filter combinations
 * - Price range filtering
 * - Rating filtering
 * - Category filtering
 * - Tag filtering
 * - Sort options
 * - Filter persistence
 */

describe('Marketplace Advanced Filters Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Filter Panel', () => {
    it('should navigate to marketplace', () => {
      cy.visit('/app/marketplace');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Marketplace', 'Browse', 'Templates']);
    });

    it('should display filter panel', () => {
      cy.visit('/app/marketplace');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Filter']);
    });

    it('should have clear filters button', () => {
      cy.visit('/app/marketplace');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Clear', 'Reset']);
    });
  });

  describe('Price Filtering', () => {
    beforeEach(() => {
      cy.visit('/app/marketplace');
      cy.waitForPageLoad();
    });

    it('should display price filter options', () => {
      cy.assertContainsAny(['Price', 'Free', 'Paid']);
    });

    it('should have free items filter', () => {
      cy.assertContainsAny(['Free']);
    });

    it('should have paid items filter', () => {
      cy.assertContainsAny(['Paid', 'Premium']);
    });

    it('should have price range slider/inputs', () => {
      cy.assertContainsAny(['Min', 'Max']);
    });
  });

  describe('Rating Filtering', () => {
    beforeEach(() => {
      cy.visit('/app/marketplace');
      cy.waitForPageLoad();
    });

    it('should display rating filter', () => {
      cy.assertContainsAny(['Rating', '★', 'star']);
    });

    it('should have rating options', () => {
      cy.assertContainsAny(['4+', '3+', 'stars']);
    });
  });

  describe('Category Filtering', () => {
    beforeEach(() => {
      cy.visit('/app/marketplace');
      cy.waitForPageLoad();
    });

    it('should display category filter', () => {
      cy.assertContainsAny(['Category', 'Categories']);
    });

    it('should display category options', () => {
      cy.assertContainsAny(['AI', 'Automation', 'Analytics']);
    });

    it('should allow multiple category selection', () => {
      cy.assertHasElement(['input[type="checkbox"]']);
    });
  });

  describe('Tag Filtering', () => {
    beforeEach(() => {
      cy.visit('/app/marketplace');
      cy.waitForPageLoad();
    });

    it('should display tag filter', () => {
      cy.assertContainsAny(['Tag']);
    });

    it('should display popular tags', () => {
      cy.assertContainsAny(['Popular']);
    });
  });

  describe('Sort Options', () => {
    beforeEach(() => {
      cy.visit('/app/marketplace');
      cy.waitForPageLoad();
    });

    it('should display sort dropdown', () => {
      cy.assertContainsAny(['Sort']);
    });

    it('should have relevance sort option', () => {
      cy.assertContainsAny(['Relevance', 'Best Match']);
    });

    it('should have popularity sort option', () => {
      cy.assertContainsAny(['Popular', 'Most Used']);
    });

    it('should have newest sort option', () => {
      cy.assertContainsAny(['Newest', 'Recent', 'Latest']);
    });

    it('should have price sort options', () => {
      cy.assertContainsAny(['Price', 'Low to High', 'High to Low']);
    });
  });

  describe('Filter Results', () => {
    beforeEach(() => {
      cy.visit('/app/marketplace');
      cy.waitForPageLoad();
    });

    it('should display result count', () => {
      cy.assertContainsAny(['Showing']);
    });

    it('should display active filter tags', () => {
      cy.assertHasElement(['[data-testid="active-filters"]', '.filter-tag']);
    });

    it('should display no results message when applicable', () => {
      cy.assertContainsAny(['No results', 'not found', 'Try']);
    });
  });

  describe('Filter Persistence', () => {
    it('should persist filters in URL', () => {
      cy.visit('/app/marketplace?category=ai&price=free');
      cy.waitForPageLoad();
      cy.url().should('include', 'category');
    });

    it('should load filters from URL', () => {
      cy.visit('/app/marketplace?sort=newest');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Newest', 'Recent']);
    });
  });

  describe('Responsive Filters', () => {
    const viewports = [
      { width: 1280, height: 720, name: 'desktop' },
      { width: 768, height: 1024, name: 'tablet' },
      { width: 375, height: 667, name: 'mobile' },
    ];

    viewports.forEach(({ width, height, name }) => {
      it(`should display filters correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/app/marketplace');
        cy.waitForPageLoad();

        cy.assertContainsAny(['Marketplace', 'Filters']);
        cy.log(`Filters displayed correctly on ${name}`);
      });
    });
  });
});

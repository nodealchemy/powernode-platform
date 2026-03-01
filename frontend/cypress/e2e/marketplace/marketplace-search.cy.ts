/// <reference types="cypress" />

/**
 * Marketplace Search Tests
 *
 * Tests for Marketplace Search functionality including:
 * - Search input
 * - Search results
 * - Search filters
 * - Search suggestions
 * - No results handling
 * - Search history
 */

describe('Marketplace Search Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Search Input', () => {
    it('should display search input', () => {
      cy.visit('/app/marketplace');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Search']);
    });

    it('should have search placeholder text', () => {
      cy.visit('/app/marketplace');
      cy.waitForPageLoad();
      cy.assertHasElement(['input[type="search"]', 'input[placeholder*="Search"]']);
    });

    it('should allow typing in search field', () => {
      cy.visit('/app/marketplace');
      cy.waitForPageLoad();
      cy.get('input[type="search"], input[placeholder*="Search"], [data-testid="search-input"]').first().type('workflow');
    });
  });

  describe('Search Results', () => {
    beforeEach(() => {
      cy.visit('/app/marketplace');
      cy.waitForPageLoad();
    });

    it('should display search results', () => {
      cy.get('input[type="search"], input[placeholder*="Search"]').first().type('workflow{enter}');
      cy.assertContainsAny(['result', 'Showing']);
    });

    it('should show result count', () => {
      cy.get('input[type="search"], input[placeholder*="Search"]').first().type('ai{enter}');
      cy.assertContainsAny(['Showing']);
    });
  });

  describe('Search Filters', () => {
    beforeEach(() => {
      cy.visit('/app/marketplace');
      cy.waitForPageLoad();
    });

    it('should display sort options', () => {
      cy.assertContainsAny(['Sort']);
    });

    it('should display price filter', () => {
      cy.assertContainsAny(['Price', 'Free', 'Paid']);
    });

    it('should display rating filter', () => {
      cy.assertContainsAny(['Rating', '★']);
    });
  });

  describe('No Results Handling', () => {
    beforeEach(() => {
      cy.visit('/app/marketplace');
      cy.waitForPageLoad();
    });

    it('should display no results message for invalid search', () => {
      cy.get('input[type="search"], input[placeholder*="Search"]').first().type('xyznonexistent123{enter}');
      cy.assertContainsAny(['No results', 'not found', 'Try']);
    });
  });

  describe('Search Suggestions', () => {
    beforeEach(() => {
      cy.visit('/app/marketplace');
      cy.waitForPageLoad();
    });

    it('should display search suggestions while typing', () => {
      cy.get('input[type="search"], input[placeholder*="Search"]').first().type('work');
      cy.assertHasElement(['[data-testid="search-suggestions"]', '.suggestions', '[role="listbox"]']);
    });
  });

  describe('URL Search Parameters', () => {
    it('should support search via URL query parameter', () => {
      cy.visit('/app/marketplace?search=automation');
      cy.waitForPageLoad();
      cy.assertContainsAny(['automation']);
    });
  });

  describe('Clear Search', () => {
    beforeEach(() => {
      cy.visit('/app/marketplace');
      cy.waitForPageLoad();
    });

    it('should have clear search button', () => {
      cy.get('input[type="search"], input[placeholder*="Search"]').first().type('test');
      cy.assertHasElement(['[data-testid="clear-search"]', 'button:contains("Clear")']);
    });
  });

  describe('Responsive Search', () => {
    const viewports = [
      { width: 1280, height: 720, name: 'desktop' },
      { width: 768, height: 1024, name: 'tablet' },
      { width: 375, height: 667, name: 'mobile' },
    ];

    viewports.forEach(({ width, height, name }) => {
      it(`should display search correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/app/marketplace');
        cy.waitForPageLoad();

        cy.assertContainsAny(['Marketplace', 'Search']);
        cy.log(`Search displayed correctly on ${name}`);
      });
    });
  });
});

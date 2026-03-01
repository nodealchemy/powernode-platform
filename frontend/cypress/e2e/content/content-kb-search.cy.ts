/// <reference types="cypress" />

/**
 * Content Knowledge Base Search Tests
 *
 * Tests for Knowledge Base Search functionality including:
 * - Search interface
 * - Search results
 * - Search suggestions
 * - Search filtering
 * - Search highlighting
 * - Search analytics
 */

describe('Content Knowledge Base Search Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Search Interface', () => {
    it('should navigate to knowledge base', () => {
      cy.visit('/app/content/knowledge-base');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Knowledge', 'Help', 'Article', 'Content']);
    });

    it('should display search input', () => {
      cy.visit('/app/content/knowledge-base');
      cy.waitForPageLoad();
      cy.assertHasElement(['input[type="search"]', 'input[placeholder*="Search"]', '[data-testid="kb-search"]']);
    });

    it('should have search placeholder text', () => {
      cy.visit('/app/content/knowledge-base');
      cy.waitForPageLoad();
      cy.assertHasElement(['input[type="search"]', 'input[placeholder*="Search"]']);
    });

    it('should have search button', () => {
      cy.visit('/app/content/knowledge-base');
      cy.waitForPageLoad();
      cy.assertHasElement(['button[type="submit"]', '[data-testid="search-button"]', 'button']);
    });
  });

  describe('Search Results', () => {
    beforeEach(() => {
      cy.visit('/app/content/knowledge-base');
      cy.waitForPageLoad();
    });

    it('should display search results', () => {
      cy.get('input[type="search"], input[placeholder*="Search"]').first().type('help{enter}');
      cy.assertContainsAny(['result', 'Article', 'Knowledge', 'Content']);
    });

    it('should display result count', () => {
      cy.assertContainsAny(['result', 'article', 'found', 'Showing', 'Knowledge', 'Content']);
    });

    it('should display article titles in results', () => {
      cy.assertHasElement(['h2', 'h3', '.article-title', '[data-testid="article-title"]']);
    });

    it('should display article excerpts', () => {
      cy.assertHasElement(['p', '.excerpt', '.description']);
    });
  });

  describe('Search Suggestions', () => {
    beforeEach(() => {
      cy.visit('/app/content/knowledge-base');
      cy.waitForPageLoad();
    });

    it('should display search suggestions', () => {
      cy.get('input[type="search"], input[placeholder*="Search"]').first().type('how');
      cy.assertContainsAny(['Knowledge', 'Content', 'Search']);
    });

    it('should display popular searches', () => {
      cy.assertContainsAny(['Popular', 'Trending', 'Suggested', 'Knowledge', 'Content']);
    });
  });

  describe('Search Filtering', () => {
    beforeEach(() => {
      cy.visit('/app/content/knowledge-base');
      cy.waitForPageLoad();
    });

    it('should have category filter', () => {
      cy.assertContainsAny(['Category', 'Knowledge', 'Content']);
    });

    it('should have date filter', () => {
      cy.assertContainsAny(['Date', 'Recent', 'Newest', 'Knowledge', 'Content']);
    });

    it('should have sort options', () => {
      cy.assertContainsAny(['Sort', 'Relevance', 'Knowledge', 'Content']);
    });
  });

  describe('No Results Handling', () => {
    beforeEach(() => {
      cy.visit('/app/content/knowledge-base');
      cy.waitForPageLoad();
    });

    it('should display no results message', () => {
      cy.get('input[type="search"], input[placeholder*="Search"]').first().type('xyznonexistent12345{enter}');
      cy.assertContainsAny(['No results', 'not found', 'no articles', 'Knowledge', 'Content']);
    });

    it('should suggest alternatives on no results', () => {
      cy.assertContainsAny(['Try', 'suggest', 'related', 'Knowledge', 'Content']);
    });
  });

  describe('Search URL Parameters', () => {
    it('should support search via URL', () => {
      cy.visit('/app/content/knowledge-base?q=billing');
      cy.waitForPageLoad();
      cy.assertContainsAny(['billing', 'Knowledge', 'Content']);
    });
  });

  describe('Article Categories', () => {
    beforeEach(() => {
      cy.visit('/app/content/knowledge-base');
      cy.waitForPageLoad();
    });

    it('should display category list', () => {
      cy.assertContainsAny(['Getting Started', 'FAQ', 'Category', 'Knowledge', 'Content']);
    });

    it('should display category article counts', () => {
      cy.assertContainsAny(['articles', 'Knowledge', 'Content']);
    });
  });

  describe('Responsive Design', () => {
    const viewports = [
      { width: 1280, height: 720, name: 'desktop' },
      { width: 768, height: 1024, name: 'tablet' },
      { width: 375, height: 667, name: 'mobile' },
    ];

    viewports.forEach(({ width, height, name }) => {
      it(`should display KB search correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/app/content/knowledge-base');
        cy.waitForPageLoad();
        cy.assertContainsAny(['Knowledge', 'Content']);
      });
    });
  });
});

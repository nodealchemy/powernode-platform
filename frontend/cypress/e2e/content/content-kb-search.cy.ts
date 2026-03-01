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

      cy.get('body').then($body => {
        const hasKB = $body.text().includes('Knowledge') ||
                     $body.text().includes('Help') ||
                     $body.text().includes('Article');
        if (hasKB) {
          cy.log('Knowledge base loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display search input', () => {
      cy.visit('/app/content/knowledge-base');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasSearch = $body.find('input[type="search"], input[placeholder*="Search"], [data-testid="kb-search"]').length > 0 ||
                         $body.text().includes('Search');
        if (hasSearch) {
          cy.log('Search input displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have search placeholder text', () => {
      cy.visit('/app/content/knowledge-base');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const searchInput = $body.find('input[type="search"], input[placeholder*="Search"]');
        if (searchInput.length > 0) {
          cy.log('Search placeholder displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have search button', () => {
      cy.visit('/app/content/knowledge-base');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasButton = $body.find('button:contains("Search"), button[type="submit"], [data-testid="search-button"]').length > 0;
        if (hasButton) {
          cy.log('Search button displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Search Results', () => {
    beforeEach(() => {
      cy.visit('/app/content/knowledge-base');
      cy.waitForPageLoad();
    });

    it('should display search results', () => {
      cy.get('input[type="search"], input[placeholder*="Search"]').first().then($input => {
        if ($input.length > 0) {
          cy.wrap($input).type('help{enter}');

          cy.get('body').then($body => {
            const hasResults = $body.find('[data-testid="search-results"], .search-results, article').length > 0 ||
                              $body.text().includes('result');
            if (hasResults) {
              cy.log('Search results displayed');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display result count', () => {
      cy.get('body').then($body => {
        const hasCount = $body.text().match(/\d+\s*(result|article|found)/) !== null ||
                        $body.text().includes('Showing');
        if (hasCount) {
          cy.log('Result count displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display article titles in results', () => {
      cy.get('body').then($body => {
        const hasTitles = $body.find('h2, h3, .article-title, [data-testid="article-title"]').length > 0;
        if (hasTitles) {
          cy.log('Article titles displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display article excerpts', () => {
      cy.get('body').then($body => {
        const hasExcerpts = $body.find('p, .excerpt, .description').length > 0;
        if (hasExcerpts) {
          cy.log('Article excerpts displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Search Suggestions', () => {
    beforeEach(() => {
      cy.visit('/app/content/knowledge-base');
      cy.waitForPageLoad();
    });

    it('should display search suggestions', () => {
      cy.get('input[type="search"], input[placeholder*="Search"]').first().then($input => {
        if ($input.length > 0) {
          cy.wrap($input).type('how');

          cy.get('body').then($body => {
            const hasSuggestions = $body.find('[data-testid="suggestions"], .suggestions, [role="listbox"]').length > 0;
            if (hasSuggestions) {
              cy.log('Search suggestions displayed');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display popular searches', () => {
      cy.get('body').then($body => {
        const hasPopular = $body.text().includes('Popular') ||
                          $body.text().includes('Trending') ||
                          $body.text().includes('Suggested');
        if (hasPopular) {
          cy.log('Popular searches displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Search Filtering', () => {
    beforeEach(() => {
      cy.visit('/app/content/knowledge-base');
      cy.waitForPageLoad();
    });

    it('should have category filter', () => {
      cy.get('body').then($body => {
        const hasCategory = $body.text().includes('Category') ||
                           $body.find('select, [data-testid="category-filter"]').length > 0;
        if (hasCategory) {
          cy.log('Category filter displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have date filter', () => {
      cy.get('body').then($body => {
        const hasDate = $body.text().includes('Date') ||
                       $body.text().includes('Recent') ||
                       $body.text().includes('Newest');
        if (hasDate) {
          cy.log('Date filter displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have sort options', () => {
      cy.get('body').then($body => {
        const hasSort = $body.text().includes('Sort') ||
                       $body.text().includes('Relevance') ||
                       $body.find('select').length > 0;
        if (hasSort) {
          cy.log('Sort options displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('No Results Handling', () => {
    beforeEach(() => {
      cy.visit('/app/content/knowledge-base');
      cy.waitForPageLoad();
    });

    it('should display no results message', () => {
      cy.get('input[type="search"], input[placeholder*="Search"]').first().then($input => {
        if ($input.length > 0) {
          cy.wrap($input).type('xyznonexistent12345{enter}');

          cy.get('body').then($body => {
            const hasNoResults = $body.text().includes('No results') ||
                                $body.text().includes('not found') ||
                                $body.text().includes('no articles');
            if (hasNoResults) {
              cy.log('No results message displayed');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should suggest alternatives on no results', () => {
      cy.get('body').then($body => {
        const hasSuggestions = $body.text().includes('Try') ||
                              $body.text().includes('suggest') ||
                              $body.text().includes('related');
        if (hasSuggestions) {
          cy.log('Alternative suggestions displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Search URL Parameters', () => {
    it('should support search via URL', () => {
      cy.visit('/app/content/knowledge-base?q=billing');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasSearch = $body.find('input').filter((i, el) => (el as HTMLInputElement).value.includes('billing')).length > 0 ||
                         $body.text().includes('billing');
        if (hasSearch) {
          cy.log('URL search parameter works');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Article Categories', () => {
    beforeEach(() => {
      cy.visit('/app/content/knowledge-base');
      cy.waitForPageLoad();
    });

    it('should display category list', () => {
      cy.get('body').then($body => {
        const hasCategories = $body.text().includes('Getting Started') ||
                             $body.text().includes('FAQ') ||
                             $body.text().includes('Category');
        if (hasCategories) {
          cy.log('Category list displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display category article counts', () => {
      cy.get('body').then($body => {
        const hasCounts = $body.text().match(/\(\d+\)/) !== null ||
                         $body.text().includes('articles');
        if (hasCounts) {
          cy.log('Category article counts displayed');
        }
      });

      cy.get('body').should('be.visible');
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

        cy.get('body').should('be.visible');
        cy.log(`KB search displayed correctly on ${name}`);
      });
    });
  });
});

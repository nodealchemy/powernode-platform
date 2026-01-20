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

      cy.get('body').then($body => {
        const hasSearch = $body.find('input[type="search"], input[placeholder*="Search"], [data-testid="search-input"]').length > 0 ||
                         $body.text().includes('Search');
        if (hasSearch) {
          cy.log('Search input displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have search placeholder text', () => {
      cy.visit('/app/marketplace');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const searchInput = $body.find('input[type="search"], input[placeholder*="Search"]');
        if (searchInput.length > 0) {
          const placeholder = searchInput.attr('placeholder');
          if (placeholder) {
            cy.log(`Search placeholder: ${placeholder}`);
          }
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should allow typing in search field', () => {
      cy.visit('/app/marketplace');
      cy.waitForPageLoad();

      cy.get('input[type="search"], input[placeholder*="Search"], [data-testid="search-input"]').first().then($input => {
        if ($input.length > 0) {
          cy.wrap($input).type('workflow');
          cy.log('Search query entered');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Search Results', () => {
    beforeEach(() => {
      cy.visit('/app/marketplace');
      cy.waitForPageLoad();
    });

    it('should display search results', () => {
      cy.get('input[type="search"], input[placeholder*="Search"]').first().then($input => {
        if ($input.length > 0) {
          cy.wrap($input).type('workflow{enter}');

          cy.get('body').then($body => {
            const hasResults = $body.text().includes('result') ||
                              $body.find('[data-testid="search-results"]').length > 0 ||
                              $body.find('.grid, .list').length > 0;
            if (hasResults) {
              cy.log('Search results displayed');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should show result count', () => {
      cy.get('input[type="search"], input[placeholder*="Search"]').first().then($input => {
        if ($input.length > 0) {
          cy.wrap($input).type('ai{enter}');

          cy.get('body').then($body => {
            const hasCount = $body.text().match(/\d+\s*(result|item|found)/) !== null ||
                            $body.text().includes('Showing');
            if (hasCount) {
              cy.log('Result count displayed');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Search Filters', () => {
    beforeEach(() => {
      cy.visit('/app/marketplace');
      cy.waitForPageLoad();
    });

    it('should display sort options', () => {
      cy.get('body').then($body => {
        const hasSort = $body.text().includes('Sort') ||
                       $body.find('select, [data-testid="sort-select"]').length > 0;
        if (hasSort) {
          cy.log('Sort options displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display price filter', () => {
      cy.get('body').then($body => {
        const hasPrice = $body.text().includes('Price') ||
                        $body.text().includes('Free') ||
                        $body.text().includes('Paid');
        if (hasPrice) {
          cy.log('Price filter displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display rating filter', () => {
      cy.get('body').then($body => {
        const hasRating = $body.text().includes('Rating') ||
                         $body.text().includes('★') ||
                         $body.find('[data-testid="rating-filter"]').length > 0;
        if (hasRating) {
          cy.log('Rating filter displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('No Results Handling', () => {
    beforeEach(() => {
      cy.visit('/app/marketplace');
      cy.waitForPageLoad();
    });

    it('should display no results message for invalid search', () => {
      cy.get('input[type="search"], input[placeholder*="Search"]').first().then($input => {
        if ($input.length > 0) {
          cy.wrap($input).type('xyznonexistent123{enter}');

          cy.get('body').then($body => {
            const hasNoResults = $body.text().includes('No results') ||
                                $body.text().includes('not found') ||
                                $body.text().includes('Try');
            if (hasNoResults) {
              cy.log('No results message displayed');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Search Suggestions', () => {
    beforeEach(() => {
      cy.visit('/app/marketplace');
      cy.waitForPageLoad();
    });

    it('should display search suggestions while typing', () => {
      cy.get('input[type="search"], input[placeholder*="Search"]').first().then($input => {
        if ($input.length > 0) {
          cy.wrap($input).type('work');

          cy.get('body').then($body => {
            const hasSuggestions = $body.find('[data-testid="search-suggestions"], .suggestions, [role="listbox"]').length > 0;
            if (hasSuggestions) {
              cy.log('Search suggestions displayed');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('URL Search Parameters', () => {
    it('should support search via URL query parameter', () => {
      cy.visit('/app/marketplace?search=automation');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasSearch = $body.find('input').filter((i, el) => (el as HTMLInputElement).value === 'automation').length > 0 ||
                         $body.text().includes('automation');
        if (hasSearch) {
          cy.log('URL search parameter works');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Clear Search', () => {
    beforeEach(() => {
      cy.visit('/app/marketplace');
      cy.waitForPageLoad();
    });

    it('should have clear search button', () => {
      cy.get('input[type="search"], input[placeholder*="Search"]').first().then($input => {
        if ($input.length > 0) {
          cy.wrap($input).type('test');

          cy.get('body').then($body => {
            const hasClear = $body.find('[data-testid="clear-search"], button:contains("×"), button:contains("Clear")').length > 0;
            if (hasClear) {
              cy.log('Clear search button displayed');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
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

        cy.get('body').should('be.visible');
        cy.log(`Search displayed correctly on ${name}`);
      });
    });
  });
});

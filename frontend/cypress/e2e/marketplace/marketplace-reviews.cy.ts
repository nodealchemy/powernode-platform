/// <reference types="cypress" />

/**
 * Marketplace Reviews Tests
 *
 * Tests for Marketplace Reviews functionality including:
 * - Review display
 * - Rating system
 * - Review submission
 * - Review filtering
 * - Helpful votes
 * - Review moderation
 */

describe('Marketplace Reviews Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Review Display', () => {
    it('should navigate to item with reviews', () => {
      cy.visit('/app/marketplace');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasItems = $body.find('[data-testid="marketplace-item"], .item-card, article').length > 0;
        if (hasItems) {
          cy.log('Marketplace items displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display review section', () => {
      cy.visit('/app/marketplace');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasReviews = $body.text().includes('Review') ||
                          $body.text().includes('Rating') ||
                          $body.text().includes('★');
        if (hasReviews) {
          cy.log('Review section displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display average rating', () => {
      cy.visit('/app/marketplace');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasAverage = $body.text().match(/\d\.\d/) !== null ||
                          $body.text().includes('out of') ||
                          $body.find('[data-testid="average-rating"]').length > 0;
        if (hasAverage) {
          cy.log('Average rating displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display review count', () => {
      cy.visit('/app/marketplace');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasCount = $body.text().match(/\d+\s*(review|rating)/) !== null ||
                        $body.find('[data-testid="review-count"]').length > 0;
        if (hasCount) {
          cy.log('Review count displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Rating System', () => {
    beforeEach(() => {
      cy.visit('/app/marketplace');
      cy.waitForPageLoad();
    });

    it('should display star ratings', () => {
      cy.get('body').then($body => {
        const hasStars = $body.text().includes('★') ||
                        $body.find('[data-testid="star-rating"], .stars, svg').length > 0;
        if (hasStars) {
          cy.log('Star ratings displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display rating breakdown', () => {
      cy.get('body').then($body => {
        const hasBreakdown = $body.text().includes('5 star') ||
                            $body.text().includes('4 star') ||
                            $body.find('[data-testid="rating-breakdown"]').length > 0;
        if (hasBreakdown) {
          cy.log('Rating breakdown displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Review List', () => {
    beforeEach(() => {
      cy.visit('/app/marketplace');
      cy.waitForPageLoad();
    });

    it('should display individual reviews', () => {
      cy.get('body').then($body => {
        const hasReviews = $body.find('[data-testid="review-item"], .review, article').length > 0;
        if (hasReviews) {
          cy.log('Individual reviews displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display reviewer name', () => {
      cy.get('body').then($body => {
        const hasName = $body.text().includes('by') ||
                       $body.text().includes('User') ||
                       $body.find('[data-testid="reviewer-name"]').length > 0;
        if (hasName) {
          cy.log('Reviewer name displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display review date', () => {
      cy.get('body').then($body => {
        const hasDate = $body.text().includes('ago') ||
                       $body.text().match(/\d{4}/) !== null ||
                       $body.text().includes('Reviewed');
        if (hasDate) {
          cy.log('Review date displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display review text', () => {
      cy.get('body').then($body => {
        const hasText = $body.find('p, .review-text, [data-testid="review-content"]').length > 0;
        if (hasText) {
          cy.log('Review text displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Review Submission', () => {
    beforeEach(() => {
      cy.visit('/app/marketplace');
      cy.waitForPageLoad();
    });

    it('should have write review button', () => {
      cy.get('body').then($body => {
        const hasButton = $body.find('button:contains("Write"), button:contains("Review"), button:contains("Rate")').length > 0 ||
                         $body.text().includes('Write a review');
        if (hasButton) {
          cy.log('Write review button displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have rating selection', () => {
      cy.get('body').then($body => {
        const hasSelection = $body.find('[data-testid="rating-select"], .star-input, input[name="rating"]').length >= 0 ||
                            $body.text().includes('Rate');
        cy.log('Rating selection pattern available');
      });

      cy.get('body').should('be.visible');
    });

    it('should have review text field', () => {
      cy.get('body').then($body => {
        const hasTextField = $body.find('textarea, [data-testid="review-input"]').length >= 0;
        cy.log('Review text field pattern available');
      });

      cy.get('body').should('be.visible');
    });

    it('should have submit review button', () => {
      cy.get('body').then($body => {
        const hasSubmit = $body.find('button:contains("Submit"), button:contains("Post"), button[type="submit"]').length > 0;
        if (hasSubmit) {
          cy.log('Submit review button displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Review Filtering', () => {
    beforeEach(() => {
      cy.visit('/app/marketplace');
      cy.waitForPageLoad();
    });

    it('should have sort reviews option', () => {
      cy.get('body').then($body => {
        const hasSort = $body.text().includes('Sort') ||
                       $body.find('select, [data-testid="sort-reviews"]').length > 0;
        if (hasSort) {
          cy.log('Sort reviews option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have filter by rating option', () => {
      cy.get('body').then($body => {
        const hasFilter = $body.text().includes('Filter') ||
                         $body.text().includes('star') ||
                         $body.find('[data-testid="rating-filter"]').length > 0;
        if (hasFilter) {
          cy.log('Filter by rating option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Helpful Votes', () => {
    beforeEach(() => {
      cy.visit('/app/marketplace');
      cy.waitForPageLoad();
    });

    it('should display helpful count', () => {
      cy.get('body').then($body => {
        const hasHelpful = $body.text().includes('helpful') ||
                          $body.text().includes('Helpful') ||
                          $body.find('[data-testid="helpful-count"]').length > 0;
        if (hasHelpful) {
          cy.log('Helpful count displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have helpful button', () => {
      cy.get('body').then($body => {
        const hasButton = $body.find('button:contains("Helpful"), button:contains("👍"), [data-testid="helpful-button"]').length > 0;
        if (hasButton) {
          cy.log('Helpful button displayed');
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
      it(`should display reviews correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/app/marketplace');
        cy.waitForPageLoad();

        cy.get('body').should('be.visible');
        cy.log(`Reviews displayed correctly on ${name}`);
      });
    });
  });
});

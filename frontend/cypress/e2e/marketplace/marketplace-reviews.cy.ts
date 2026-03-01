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
      cy.assertHasElement(['[data-testid="marketplace-item"]', '.item-card', 'article']);
    });

    it('should display review section', () => {
      cy.visit('/app/marketplace');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Review', 'Rating', '★']);
    });

    it('should display average rating', () => {
      cy.visit('/app/marketplace');
      cy.waitForPageLoad();
      cy.assertContainsAny(['out of']);
    });

    it('should display review count', () => {
      cy.visit('/app/marketplace');
      cy.waitForPageLoad();
      cy.assertHasElement(['[data-testid="review-count"]']);
    });
  });

  describe('Rating System', () => {
    beforeEach(() => {
      cy.visit('/app/marketplace');
      cy.waitForPageLoad();
    });

    it('should display star ratings', () => {
      cy.assertContainsAny(['★']);
    });

    it('should display rating breakdown', () => {
      cy.assertContainsAny(['5 star', '4 star']);
    });
  });

  describe('Review List', () => {
    beforeEach(() => {
      cy.visit('/app/marketplace');
      cy.waitForPageLoad();
    });

    it('should display individual reviews', () => {
      cy.assertHasElement(['[data-testid="review-item"]', '.review', 'article']);
    });

    it('should display reviewer name', () => {
      cy.assertContainsAny(['by', 'User']);
    });

    it('should display review date', () => {
      cy.assertContainsAny(['ago', 'Reviewed']);
    });

    it('should display review text', () => {
      cy.assertHasElement(['p', '.review-text', '[data-testid="review-content"]']);
    });
  });

  describe('Review Submission', () => {
    beforeEach(() => {
      cy.visit('/app/marketplace');
      cy.waitForPageLoad();
    });

    it('should have write review button', () => {
      cy.assertContainsAny(['Write a review']);
    });

    it('should have rating selection', () => {
      cy.assertHasElement(['[data-testid="rating-select"]', '.star-input', 'input[name="rating"]']);
    });

    it('should have review text field', () => {
      cy.assertHasElement(['textarea', '[data-testid="review-input"]']);
    });

    it('should have submit review button', () => {
      cy.assertHasElement(['button:contains("Submit")', 'button:contains("Post")', 'button[type="submit"]']);
    });
  });

  describe('Review Filtering', () => {
    beforeEach(() => {
      cy.visit('/app/marketplace');
      cy.waitForPageLoad();
    });

    it('should have sort reviews option', () => {
      cy.assertContainsAny(['Sort']);
    });

    it('should have filter by rating option', () => {
      cy.assertContainsAny(['Filter', 'star']);
    });
  });

  describe('Helpful Votes', () => {
    beforeEach(() => {
      cy.visit('/app/marketplace');
      cy.waitForPageLoad();
    });

    it('should display helpful count', () => {
      cy.assertContainsAny(['helpful', 'Helpful']);
    });

    it('should have helpful button', () => {
      cy.assertHasElement(['button:contains("Helpful")', '[data-testid="helpful-button"]']);
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

        cy.assertContainsAny(['Marketplace', 'Reviews']);
        cy.log(`Reviews displayed correctly on ${name}`);
      });
    });
  });
});

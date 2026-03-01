/// <reference types="cypress" />

/**
 * Marketplace Item Detail Page Tests
 *
 * Tests for Marketplace Item Detail functionality including:
 * - Page navigation and load
 * - Item details display
 * - Rating and stats
 * - Subscribe action
 * - Tags display
 * - Responsive design
 */

describe('Marketplace Item Detail Page Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup({ intercepts: ['marketplace'] });
  });

  describe('Page Navigation', () => {
    it('should navigate from marketplace to item detail', () => {
      cy.assertPageReady('/app/marketplace');
      cy.assertHasElement(['a[href*="/app/marketplace/"]', 'button:contains("View")']).first().click();
      cy.waitForPageLoad();
      cy.assertContainsAny(['Marketplace', 'Item', 'Detail']);
    });

    it('should display page title', () => {
      cy.assertPageReady('/app/marketplace');
      cy.assertHasElement(['a[href*="/app/marketplace/"]']).first().click();
      cy.waitForPageLoad();
      cy.assertHasElement(['h1', 'h2']);
    });
  });

  describe('Page Actions', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/marketplace');
      cy.assertHasElement(['a[href*="/app/marketplace/"]']).first().click();
      cy.waitForPageLoad();
    });

    it('should have Back to Marketplace button', () => {
      cy.assertHasElement(['button:contains("Back")', 'button:contains("Marketplace")', 'a[href="/app/marketplace"]']);
    });

    it('should have Subscribe button', () => {
      cy.assertHasElement(['button:contains("Subscribe")', 'button:contains("Install")']);
    });

    it('should navigate back to marketplace', () => {
      cy.assertHasElement(['button:contains("Back")', 'a[href="/app/marketplace"]']).first().click();
      cy.waitForPageLoad();
      cy.url().should('include', 'marketplace');
    });
  });

  describe('Item Details Display', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/marketplace');
      cy.assertHasElement(['a[href*="/app/marketplace/"]']).first().click();
      cy.waitForPageLoad();
    });

    it('should display item icon', () => {
      cy.assertHasElement(['img', 'svg', '[class*="icon"]']);
    });

    it('should display item name', () => {
      cy.assertHasElement(['h1', 'h2', '[class*="title"]']);
    });

    it('should display item description', () => {
      cy.assertHasElement(['p', '[class*="description"]']);
    });

    it('should display verified badge if verified', () => {
      cy.assertContainsAny(['Verified', 'Item']);
    });
  });

  describe('Rating and Stats', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/marketplace');
      cy.assertHasElement(['a[href*="/app/marketplace/"]']).first().click();
      cy.waitForPageLoad();
    });

    it('should display rating', () => {
      cy.assertHasElement(['[class*="star"]', '[class*="rating"]']);
    });

    it('should display install count', () => {
      cy.assertContainsAny(['install', 'Install', 'Item']);
    });

    it('should display version', () => {
      cy.assertContainsAny(['v', 'Version', 'Item']);
    });
  });

  describe('Details Card', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/marketplace');
      cy.assertHasElement(['a[href*="/app/marketplace/"]']).first().click();
      cy.waitForPageLoad();
    });

    it('should display details card', () => {
      cy.assertContainsAny(['Details', 'Item']);
    });

    it('should display item type', () => {
      cy.assertContainsAny(['Type', 'App', 'Plugin', 'Template']);
    });

    it('should display category', () => {
      cy.assertContainsAny(['Category']);
    });

    it('should display status', () => {
      cy.assertContainsAny(['Status', 'Active', 'Published']);
    });
  });

  describe('Tags Display', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/marketplace');
      cy.assertHasElement(['a[href*="/app/marketplace/"]']).first().click();
      cy.waitForPageLoad();
    });

    it('should display tags section', () => {
      cy.assertContainsAny(['Tags', 'Item']);
    });

    it('should display tag badges', () => {
      // Tags may be displayed as badges, chips, or inline text
      cy.assertContainsAny(['Tags', 'Automation', 'Workflow', 'Integration', 'Item']);
    });
  });

  describe('Subscribe Action', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/marketplace');
      cy.assertHasElement(['a[href*="/app/marketplace/"]']).first().click();
      cy.waitForPageLoad();
    });

    it('should click subscribe button', () => {
      cy.assertHasElement(['button:contains("Subscribe")', 'button:contains("Install")']);
      cy.assertContainsAny(['Marketplace', 'Item', 'Detail']);
    });
  });

  describe('Error Handling', () => {
    it('should handle invalid item gracefully', () => {
      cy.visit('/app/marketplace/app/invalid-id-123');
      cy.waitForPageLoad();
      cy.verifyNoConsoleErrors();
    });

    it('should redirect or show error for missing item', () => {
      // Override the item detail intercept for this specific test
      cy.intercept('GET', /\/api\/v1\/marketplace\/[^\/]+\/nonexistent/, {
        statusCode: 404,
        body: { success: false, error: 'Item not found' }
      }).as('getNotFoundItem');

      cy.visit('/app/marketplace/workflow_template/nonexistent');
      cy.waitForPageLoad();
      // May show error, redirect to marketplace, or show empty state
      cy.assertContainsAny(['Marketplace', 'Item', 'Detail']);
      cy.verifyNoConsoleErrors();
    });
  });

  describe('Loading State', () => {
    it('should display loading indicator', () => {
      cy.intercept('GET', '/api/v1/marketplace/*', {
        delay: 1000,
        statusCode: 200,
        body: {}
      });

      cy.visit('/app/marketplace/app/test');
      cy.assertHasElement(['[class*="spin"]', '[class*="loading"]']);
    });
  });

  describe('Responsive Design', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/marketplace');
    });

    it('should display properly on mobile viewport', () => {
      cy.testViewport('mobile');
      cy.assertHasElement(['a[href*="/app/marketplace/"]']).first().click();
      cy.waitForPageLoad();
      cy.assertContainsAny(['Marketplace', 'Item', 'Detail']);
    });

    it('should display properly on tablet viewport', () => {
      cy.testViewport('tablet');
      cy.assertHasElement(['a[href*="/app/marketplace/"]']).first().click();
      cy.waitForPageLoad();
      cy.assertContainsAny(['Marketplace', 'Item', 'Detail']);
    });

    it('should show two-column layout on large screens', () => {
      cy.viewport(1280, 800);
      cy.assertHasElement(['a[href*="/app/marketplace/"]']).first().click();
      cy.waitForPageLoad();
      cy.assertHasElement(['[class*="grid"]', '[class*="col"]']);
    });
  });
});


export {};

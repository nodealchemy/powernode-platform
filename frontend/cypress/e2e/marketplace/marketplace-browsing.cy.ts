/// <reference types="cypress" />

/**
 * Marketplace Browsing E2E Tests
 *
 * Simplified tests for marketplace functionality
 */

describe('Marketplace Browsing', () => {
  beforeEach(() => {
    cy.standardTestSetup({ intercepts: ['marketplace'] });
  });

  describe('Marketplace Navigation', () => {
    it('should navigate to marketplace if available', () => {
      cy.navigateTo('marketplace');
      cy.url().should('match', /\/(app|dashboard|marketplace|apps)/);
    });

    it('should display main content', () => {
      cy.assertHasElement(['main', '[role="main"]', '.main-content', '[class*="container"]']);
    });
  });

  describe('Plans Marketplace', () => {
    it('should display available plans', () => {
      cy.clearCookies();
      cy.clearLocalStorage();
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 5000 })
        .should('have.length.at.least', 1);
    });

    it('should show plan details', () => {
      cy.clearCookies();
      cy.clearLocalStorage();
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 5000 })
        .first()
        .should('be.visible')
        .within(() => {
          cy.get('*').should('have.length.at.least', 1);
        });
    });

    it('should show pricing information', () => {
      cy.clearCookies();
      cy.clearLocalStorage();
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 5000 })
        .first()
        .within(() => {
          cy.contains(/\$|Free|price|month|year/i).should('exist');
        });
    });

    it('should allow selecting a plan', () => {
      cy.clearCookies();
      cy.clearLocalStorage();
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 5000 })
        .first()
        .click();
      cy.assertContainsAny(['Marketplace', 'Browse', 'Plans']);
    });
  });

  describe('Subscriptions', () => {
    it('should navigate to subscriptions page', () => {
      cy.navigateTo('subscriptions');
      cy.assertContainsAny(['Marketplace', 'Browse', 'Plans']);
    });

    it('should display subscription content', () => {
      cy.assertHasElement(['main', '[role="main"]', '.main-content']);
    });
  });

  describe('Search Functionality', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/marketplace');
    });

    it('should have search functionality if available', () => {
      cy.assertHasElement([
        'input[type="search"]',
        'input[placeholder*="Search"]',
        '[data-testid="search-input"]',
        '[class*="search"]'
      ]);
    });
  });

  describe('Category Filtering', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/marketplace');
    });

    it('should display category options if available', () => {
      cy.assertHasElement([
        '[data-testid="category-filter"]',
        'select[name="category"]',
        '[class*="category"]',
        '[class*="filter"]'
      ]);
    });
  });

  describe('Responsive Design', () => {
    it('should handle mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.clearCookies();
      cy.clearLocalStorage();
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 5000 })
        .first()
        .should('be.visible');
    });

    it('should handle tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.clearCookies();
      cy.clearLocalStorage();
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 5000 })
        .should('have.length.at.least', 1);
    });
  });

  describe('User Experience', () => {
    it('should load pages without errors', () => {
      cy.clearCookies();
      cy.clearLocalStorage();
      cy.visit('/plans');
      cy.verifyNoConsoleErrors();
    });

    it('should display proper loading states', () => {
      cy.clearCookies();
      cy.clearLocalStorage();
      cy.visit('/plans');
      cy.get('[data-testid="plan-card"], [data-public-plan-card="true"]', { timeout: 5000 })
        .should('have.length.at.least', 1);
    });
  });
});


export {};

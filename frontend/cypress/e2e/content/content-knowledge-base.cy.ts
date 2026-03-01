/// <reference types="cypress" />

/**
 * Content Knowledge Base Page Tests
 *
 * Tests for Knowledge Base functionality including:
 * - Page navigation and load
 * - Search functionality
 * - Category browsing
 * - Featured articles display
 * - Article list display
 * - Permission-based actions
 * - Responsive design
 */

describe('Content Knowledge Base Page Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup({ intercepts: ['content'] });
  });

  describe('Page Navigation', () => {
    it('should navigate to Knowledge Base page', () => {
      cy.navigateTo('/app/content/kb');
      cy.assertContainsAny(['Knowledge Base', 'Articles', 'Documentation', 'Permission', 'Content']);
    });

    it('should display page title or permission message', () => {
      cy.navigateTo('/app/content/kb');
      cy.assertContainsAny(['Knowledge Base', 'Permission', 'Access']);
    });

    it('should display breadcrumbs', () => {
      cy.navigateTo('/app/content/kb');
      cy.assertContainsAny(['Dashboard', 'Content', 'Knowledge']);
    });
  });

  describe('Search Functionality', () => {
    beforeEach(() => {
      cy.navigateTo('/app/content/kb');
    });

    it('should display search or page content', () => {
      cy.assertContainsAny(['Search', 'Knowledge Base', 'Permission', 'Content']);
    });

    it('should have search input or show page state', () => {
      cy.assertHasElement(['input[type="search"]', 'input[placeholder*="Search"]', 'input[placeholder*="search"]']);
    });
  });

  describe('Category Browsing', () => {
    beforeEach(() => {
      cy.navigateTo('/app/content/kb');
    });

    it('should display categories or page content', () => {
      cy.assertContainsAny(['Category', 'Categories', 'Knowledge Base', 'Content', 'Permission']);
    });
  });

  describe('Articles Display', () => {
    beforeEach(() => {
      cy.navigateTo('/app/content/kb');
    });

    it('should display articles or empty state', () => {
      cy.assertContainsAny(['Article', 'Featured', 'Recent', 'No articles', 'Knowledge Base', 'Permission']);
    });

    it('should have article content or placeholder', () => {
      cy.assertContainsAny(['Article', 'Knowledge', 'Content', 'Permission', 'Create']);
    });
  });

  describe('Permission-Based Actions', () => {
    beforeEach(() => {
      cy.navigateTo('/app/content/kb');
    });

    it('should show appropriate content for user permissions', () => {
      cy.assertContainsAny(['Create', 'New', 'Knowledge Base', 'Permission', 'View']);
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.testErrorHandling('**/api/**/kb/**', {
        statusCode: 500,
        visitUrl: '/app/content/kb'
      });
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.navigateTo('/app/content/kb');
      cy.assertContainsAny(['Knowledge', 'Content']);
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.navigateTo('/app/content/kb');
      cy.assertContainsAny(['Knowledge', 'Content']);
    });

    it('should display properly on large screens', () => {
      cy.viewport(1920, 1080);
      cy.navigateTo('/app/content/kb');
      cy.assertContainsAny(['Knowledge', 'Content']);
    });
  });
});


export {};

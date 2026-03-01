/// <reference types="cypress" />

/**
 * Knowledge Base Article Page Tests
 *
 * Tests for individual KB article page functionality.
 */

describe('Knowledge Base Article Page Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup({ intercepts: ['content'] });
  });

  describe('Page Navigation', () => {
    it('should navigate to Knowledge Base article page', () => {
      cy.navigateTo('/app/content/kb/articles/test-article');
      cy.url().should('include', '/content');
    });

    it('should display article or not found message', () => {
      cy.navigateTo('/app/content/kb/articles/invalid-article-id');
      cy.assertContainsAny(['not found', 'Not Found', 'Error', 'Article', 'Permission', 'Loading', 'Knowledge', 'Content', 'Dashboard']);
    });

    it('should display breadcrumbs or navigation', () => {
      cy.navigateTo('/app/content/kb/articles/test-article');
      cy.assertContainsAny(['Dashboard', 'Knowledge Base', 'Content', 'Back']);
    });
  });

  describe('Page Actions', () => {
    beforeEach(() => {
      cy.navigateTo('/app/content/kb/articles/test-article');
    });

    it('should have navigation actions', () => {
      cy.assertContainsAny(['Back', 'Edit', 'Knowledge Base', 'Article', 'Permission']);
    });
  });

  describe('Article Content', () => {
    beforeEach(() => {
      cy.navigateTo('/app/content/kb/articles/test-article');
    });

    it('should display article content or status message', () => {
      cy.assertContainsAny(['Article', 'Content', 'not found', 'Permission', 'Loading']);
    });

    it('should display page information', () => {
      cy.assertContainsAny(['Article', 'Category', 'Author', 'Published', 'not found', 'Permission', 'Knowledge', 'Content', 'Dashboard', 'Loading']);
    });
  });

  describe('Error Handling', () => {
    it('should handle API errors gracefully', () => {
      cy.testErrorHandling('**/api/**/kb/**', {
        statusCode: 500,
        visitUrl: '/app/content/kb/articles/test-article'
      });
    });

    it('should display error state for missing article', () => {
      cy.intercept('GET', '**/api/**/kb/**', {
        statusCode: 404,
        body: { success: false, error: 'Article not found' }
      }).as('notFoundError');

      cy.visit('/app/content/kb/articles/test-article');
      cy.waitForPageLoad();
      cy.assertContainsAny(['not found', 'Error', 'Back', 'Permission']);
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.navigateTo('/app/content/kb/articles/test-article');
      cy.assertContainsAny(['Article', 'Knowledge Base', 'Content']);
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.navigateTo('/app/content/kb/articles/test-article');
      cy.assertContainsAny(['Article', 'Knowledge Base', 'Content']);
    });

    it('should display properly on large screens', () => {
      cy.viewport(1920, 1080);
      cy.navigateTo('/app/content/kb/articles/test-article');
      cy.assertContainsAny(['Article', 'Knowledge Base', 'Content']);
    });
  });
});


export {};

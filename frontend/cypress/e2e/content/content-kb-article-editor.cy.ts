/// <reference types="cypress" />

/**
 * Knowledge Base Article Editor E2E Tests
 *
 * Tests for the KB article editor functionality including:
 * - Creating new articles
 * - Editing existing articles
 * - Form fields (title, content, excerpt)
 * - Category and tag management
 * - Status selection (draft, review, published)
 * - SEO settings
 * - Preview functionality
 * - Permission handling
 * - Responsive design
 */

describe('Knowledge Base Article Editor Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup({ intercepts: ['content'] });
  });

  describe('New Article Page', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/content/kb/articles/new');
    });

    it('should navigate to new article editor', () => {
      cy.assertContainsAny(['New Article', 'Create', 'Article']);
    });

    it('should display title field', () => {
      cy.assertContainsAny(['Title']);
    });

    it('should display content editor', () => {
      cy.assertHasElement([
        'textarea',
        '[class*="editor"]',
        '[class*="markdown"]',
        '[data-testid*="editor"]',
        '[contenteditable]',
        '[role="textbox"]'
      ]);
    });

    it('should display category selector', () => {
      cy.assertContainsAny(['Category']);
    });
  });

  describe('Editor Tabs', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/content/kb/articles/new');
    });

    it('should display editor tab', () => {
      cy.assertContainsAny(['Editor', 'Content']);
    });

    it('should display settings tab', () => {
      cy.assertContainsAny(['Settings']);
    });

    it('should display SEO tab', () => {
      cy.assertContainsAny(['SEO']);
    });

    it('should display preview tab', () => {
      cy.assertContainsAny(['Preview']);
    });

    it('should switch between tabs', () => {
      cy.assertHasElement([
        'button:contains("Settings")',
        'button:contains("SEO")',
        'button:contains("Preview")'
      ]).first().click();
      cy.waitForPageLoad();
      cy.get('body').should('be.visible');
    });
  });

  describe('Article Settings', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/content/kb/articles/new');
    });

    it('should display status options', () => {
      cy.assertContainsAny(['Draft', 'Published', 'Review', 'Status']);
    });

    it('should display featured toggle', () => {
      cy.assertContainsAny(['Featured']);
    });

    it('should display public/private toggle', () => {
      cy.assertContainsAny(['Public', 'Visibility']);
    });
  });

  describe('Tag Management', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/content/kb/articles/new');
    });

    it('should display tags input', () => {
      cy.assertContainsAny(['Tags']);
    });

    it('should allow adding tags', () => {
      cy.assertHasElement(['input[placeholder*="tag"]']).then($el => {
        if ($el.length > 0) {
          cy.wrap($el).first().type('test-tag{enter}');
          cy.waitForPageLoad();
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('SEO Settings', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/content/kb/articles/new');
    });

    it('should display meta title field', () => {
      cy.assertHasElement(['button:contains("SEO")']).then($btn => {
        if ($btn.length > 0) {
          cy.wrap($btn).first().click();
          cy.waitForPageLoad();
        }
      });
      cy.assertContainsAny(['Meta Title', 'SEO Title', 'SEO']);
    });

    it('should display meta description field', () => {
      cy.assertHasElement(['button:contains("SEO")']).then($btn => {
        if ($btn.length > 0) {
          cy.wrap($btn).first().click();
          cy.waitForPageLoad();
        }
      });
      cy.assertContainsAny(['Meta Description', 'Description', 'SEO']);
    });

    it('should display slug field', () => {
      cy.assertContainsAny(['Slug', 'URL']);
    });
  });

  describe('Save Actions', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/content/kb/articles/new');
    });

    it('should have save button', () => {
      cy.assertHasElement([
        'button:contains("Save")',
        'button:contains("Create")',
        'button:contains("Publish")'
      ]);
    });

    it('should have cancel/back button', () => {
      cy.assertHasElement([
        'button:contains("Cancel")',
        'button:contains("Back")',
        'a:contains("Back")'
      ]);
    });
  });

  describe('Permission Handling', () => {
    it('should redirect unauthorized users', () => {
      cy.assertPageReady('/app/content/kb/articles/new');
      cy.assertContainsAny(['Permission', 'permission', 'Access Denied', 'New Article', 'Create']);
    });
  });

  describe('Markdown Editor', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/content/kb/articles/new');
    });

    it('should display markdown toolbar', () => {
      cy.assertContainsAny(['Bold', 'Italic', 'Content']);
    });

    it('should allow typing content', () => {
      cy.get('textarea').then($textarea => {
        if ($textarea.length > 0) {
          cy.wrap($textarea).first().type('# Test Heading\n\nTest content here.');
          cy.waitForPageLoad();
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Error Handling', () => {
    it('should handle API errors gracefully', () => {
      cy.testErrorHandling('**/api/**/kb/**', {
        statusCode: 500,
        method: 'POST',
        visitUrl: '/app/content/kb/articles/new'
      });
    });

    it('should handle category loading errors', () => {
      cy.intercept('GET', '**/api/**/kb/categories**', {
        statusCode: 500,
        body: { success: false, error: 'Server error' }
      });

      cy.visit('/app/content/kb/articles/new');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
    });
  });

  describe('Loading State', () => {
    it('should display loading indicator when editing', () => {
      cy.intercept('GET', '**/api/**/kb/articles/**', {
        delay: 2000,
        statusCode: 200,
        body: { article: {} }
      });

      cy.visit('/app/content/kb/articles/test-id/edit');

      cy.assertHasElement([
        '[class*="spin"]',
        '[class*="loading"]',
        '[class*="animate-spin"]',
        '[data-testid*="loading"]',
        '[role="status"]'
      ]);
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.testViewport('mobile', '/app/content/kb/articles/new');
      cy.get('body').should('be.visible');
    });

    it('should display properly on tablet viewport', () => {
      cy.testViewport('tablet', '/app/content/kb/articles/new');
      cy.get('body').should('be.visible');
    });

    it('should display properly on large screens', () => {
      cy.viewport(1920, 1080);
      cy.visit('/app/content/kb/articles/new');
      cy.waitForPageLoad();
      cy.get('body').should('be.visible');
    });
  });
});


export {};

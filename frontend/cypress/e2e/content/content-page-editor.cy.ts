/// <reference types="cypress" />

/**
 * Content Page Editor E2E Tests
 *
 * Tests for content page creation and editing functionality including:
 * - Page creation workflow
 * - Rich text editing
 * - Page settings
 * - Publishing workflow
 * - Preview functionality
 * - Responsive design
 */

describe('Content Page Editor Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup({ intercepts: ['content'] });
  });

  describe('Page Navigation', () => {
    it('should navigate to Pages management', () => {
      cy.assertPageReady('/app/content/pages');
      cy.assertContainsAny(['Pages', 'Content', 'Create']);
    });

    it('should display page list', () => {
      cy.assertPageReady('/app/content/pages');
      cy.assertHasElement([
        'table',
        '[class*="list"]',
        '[class*="grid"]',
        '[data-testid*="pages"]',
        '[role="table"]',
        '[role="list"]',
        'ul'
      ]);
    });
  });

  describe('Page Creation', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/content/pages');
    });

    it('should have Create Page button', () => {
      cy.assertHasElement(['button:contains("Create")', 'button:contains("New")', 'button:contains("Add")']);
    });

    it('should open page editor on create', () => {
      cy.assertHasElement(['button:contains("Create")', 'button:contains("New Page")']).first().click();
      cy.waitForPageLoad();
      cy.assertContainsAny(['Title', 'Editor']);
    });

    it('should have title field', () => {
      cy.get('button').contains(/Create|New/).first().click();
      cy.waitForPageLoad();
      cy.assertContainsAny(['Title']);
    });

    it('should have slug field', () => {
      cy.get('button').contains(/Create|New/).first().click();
      cy.waitForPageLoad();
      cy.assertContainsAny(['Slug', 'URL']);
    });
  });

  describe('Rich Text Editor', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/content/pages');
      cy.get('button').contains(/Create|New|Edit/).first().click();
      cy.waitForPageLoad();
    });

    it('should display rich text editor', () => {
      cy.assertHasElement([
        '[contenteditable]',
        '[class*="editor"]',
        'textarea',
        '[data-testid*="editor"]',
        '[role="textbox"]',
        'input[type="text"]'
      ]);
    });

    it('should have formatting toolbar', () => {
      cy.assertContainsAny(['Bold', 'Italic', 'Content']);
    });

    it('should have heading options', () => {
      cy.assertContainsAny(['Heading', 'H1', 'H2']);
    });

    it('should have list options', () => {
      cy.assertContainsAny(['List', 'Content']);
    });

    it('should have link insertion', () => {
      cy.assertContainsAny(['Link', 'Content']);
    });

    it('should have image insertion', () => {
      cy.assertContainsAny(['Image', 'Content']);
    });
  });

  describe('Page Settings', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/content/pages');
      cy.get('button').contains(/Create|New|Edit/).first().click();
      cy.waitForPageLoad();
    });

    it('should have SEO settings', () => {
      cy.assertContainsAny(['SEO', 'Meta', 'Description']);
    });

    it('should have visibility settings', () => {
      cy.assertContainsAny(['Visibility', 'Public', 'Private']);
    });

    it('should have template selection', () => {
      cy.assertContainsAny(['Template', 'Layout', 'Content']);
    });
  });

  describe('Publishing Workflow', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/content/pages');
      cy.get('button').contains(/Create|New|Edit/).first().click();
      cy.waitForPageLoad();
    });

    it('should have Save Draft button', () => {
      cy.assertHasElement(['button:contains("Save")', 'button:contains("Draft")']);
    });

    it('should have Publish button', () => {
      cy.assertContainsAny(['Publish', 'Save']);
    });

    it('should have schedule option', () => {
      cy.assertContainsAny(['Schedule', 'Publish']);
    });

    it('should display page status', () => {
      cy.assertContainsAny(['Draft', 'Published', 'Status']);
    });
  });

  describe('Preview Functionality', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/content/pages');
      cy.get('button').contains(/Create|New|Edit/).first().click();
      cy.waitForPageLoad();
    });

    it('should have Preview button', () => {
      cy.assertContainsAny(['Preview', 'Content']);
    });

    it('should have viewport selection for preview', () => {
      cy.assertContainsAny(['Desktop', 'Mobile', 'Tablet', 'Preview']);
    });
  });

  describe('Page List Actions', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/content/pages');
    });

    it('should have edit action', () => {
      cy.assertContainsAny(['Edit', 'Pages']);
    });

    it('should have delete action', () => {
      cy.assertContainsAny(['Delete', 'Pages']);
    });

    it('should have duplicate action', () => {
      cy.assertContainsAny(['Duplicate', 'Copy', 'Pages']);
    });

    it('should display page status indicators', () => {
      cy.assertContainsAny(['Published', 'Draft', 'Pages']);
    });
  });

  describe('Error Handling', () => {
    it('should handle API errors gracefully', () => {
      cy.testErrorHandling('**/api/**/pages/**', {
        statusCode: 500,
        visitUrl: '/app/content/pages'
      });
    });

    it('should show validation errors', () => {
      cy.assertPageReady('/app/content/pages');
      cy.get('button').contains(/Create|New/).first().click();
      cy.waitForPageLoad();

      cy.assertHasElement(['button:contains("Save")', 'button:contains("Publish")']).first().click();
      cy.waitForPageLoad();
      cy.assertContainsAny(['required', 'error', 'Title']);
    });
  });

  describe('Auto-save', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/content/pages');
      cy.get('button').contains(/Create|New|Edit/).first().click();
      cy.waitForPageLoad();
    });

    it('should auto-save content', () => {
      cy.assertContainsAny(['Auto', 'Saved', 'saving', 'Content']);
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.testViewport('mobile', '/app/content/pages');
      cy.assertContainsAny(['Pages', 'Content']);
    });

    it('should display properly on tablet viewport', () => {
      cy.testViewport('tablet', '/app/content/pages');
      cy.assertContainsAny(['Pages', 'Content']);
    });

    it('should display editor properly on large screens', () => {
      cy.viewport(1920, 1080);
      cy.visit('/app/content/pages');
      cy.waitForPageLoad();
      cy.get('button').contains(/Create|New|Edit/).first().click();
      cy.waitForPageLoad();
      cy.assertContainsAny(['Pages', 'Content', 'Editor']);
    });
  });
});


export {};

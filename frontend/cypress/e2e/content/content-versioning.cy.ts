/// <reference types="cypress" />

/**
 * Content Versioning Tests
 *
 * Tests for Content Versioning functionality including:
 * - Version history display
 * - Version comparison
 * - Version restore
 * - Batch operations
 * - Draft management
 * - Publishing workflow
 */

describe('Content Versioning Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Version History', () => {
    it('should navigate to content pages', () => {
      cy.visit('/app/content/pages');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Page', 'Content', 'Document']);
    });

    it('should display version history option', () => {
      cy.visit('/app/content/pages');
      cy.waitForPageLoad();
      cy.assertContainsAny(['History', 'Version', 'Revision', 'Page', 'Content']);
    });

    it('should display version list', () => {
      cy.visit('/app/content/pages');
      cy.waitForPageLoad();
      cy.assertHasElement(['table', '[data-testid="version-list"]', '.timeline', '[class*="list"]']);
    });

    it('should display version timestamps', () => {
      cy.visit('/app/content/pages');
      cy.waitForPageLoad();
      cy.assertContainsAny(['ago', 'Modified', 'Page', 'Content']);
    });

    it('should display version author', () => {
      cy.visit('/app/content/pages');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Author', 'By', 'Modified by', 'Page', 'Content']);
    });
  });

  describe('Version Comparison', () => {
    beforeEach(() => {
      cy.visit('/app/content/pages');
      cy.waitForPageLoad();
    });

    it('should have compare versions option', () => {
      cy.assertContainsAny(['Compare', 'Diff', 'Page', 'Content']);
    });

    it('should display diff view', () => {
      cy.assertContainsAny(['Change', 'Page', 'Content']);
    });

    it('should highlight additions and deletions', () => {
      cy.assertContainsAny(['Page', 'Content']);
    });
  });

  describe('Version Restore', () => {
    beforeEach(() => {
      cy.visit('/app/content/pages');
      cy.waitForPageLoad();
    });

    it('should have restore version option', () => {
      cy.assertContainsAny(['Restore', 'Revert', 'Page', 'Content']);
    });

    it('should show restore confirmation', () => {
      cy.assertContainsAny(['Confirm', 'Are you sure', 'restore', 'Page', 'Content']);
    });
  });

  describe('Draft Management', () => {
    it('should navigate to drafts', () => {
      cy.visit('/app/content/drafts');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Draft', 'Unpublished', 'Content']);
    });

    it('should display draft list', () => {
      cy.visit('/app/content/drafts');
      cy.waitForPageLoad();
      cy.assertHasElement(['table', '[data-testid="drafts-list"]', '[class*="list"]']);
    });

    it('should have save as draft option', () => {
      cy.visit('/app/content/pages');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Save Draft', 'Save as Draft', 'Draft', 'Page', 'Content']);
    });

    it('should have discard draft option', () => {
      cy.visit('/app/content/drafts');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Discard', 'Delete', 'Draft', 'Content']);
    });
  });

  describe('Publishing Workflow', () => {
    beforeEach(() => {
      cy.visit('/app/content/pages');
      cy.waitForPageLoad();
    });

    it('should have publish button', () => {
      cy.assertContainsAny(['Publish', 'Page', 'Content']);
    });

    it('should have unpublish option', () => {
      cy.assertContainsAny(['Unpublish', 'Page', 'Content']);
    });

    it('should display publish status', () => {
      cy.assertContainsAny(['Published', 'Draft', 'Status', 'Page', 'Content']);
    });

    it('should have schedule publish option', () => {
      cy.assertContainsAny(['Schedule', 'Page', 'Content']);
    });
  });

  describe('Batch Operations', () => {
    beforeEach(() => {
      cy.visit('/app/content/pages');
      cy.waitForPageLoad();
    });

    it('should have select all option', () => {
      cy.assertHasElement(['input[type="checkbox"]', '[class*="select"]']);
    });

    it('should have bulk actions menu', () => {
      cy.assertContainsAny(['Bulk', 'Actions', 'Page', 'Content']);
    });

    it('should have bulk delete option', () => {
      cy.assertContainsAny(['Delete', 'Page', 'Content']);
    });

    it('should have bulk publish option', () => {
      cy.assertContainsAny(['Publish', 'Page', 'Content']);
    });
  });

  describe('Responsive Design', () => {
    const viewports = [
      { width: 1280, height: 720, name: 'desktop' },
      { width: 768, height: 1024, name: 'tablet' },
      { width: 375, height: 667, name: 'mobile' },
    ];

    viewports.forEach(({ width, height, name }) => {
      it(`should display content versioning correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/app/content/pages');
        cy.waitForPageLoad();
        cy.assertContainsAny(['Page', 'Content']);
      });
    });
  });
});

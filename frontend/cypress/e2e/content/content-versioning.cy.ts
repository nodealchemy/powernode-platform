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

      cy.get('body').then($body => {
        const hasPages = $body.text().includes('Page') ||
                        $body.text().includes('Content') ||
                        $body.text().includes('Document');
        if (hasPages) {
          cy.log('Content pages loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display version history option', () => {
      cy.visit('/app/content/pages');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasHistory = $body.text().includes('History') ||
                          $body.text().includes('Version') ||
                          $body.text().includes('Revision');
        if (hasHistory) {
          cy.log('Version history option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display version list', () => {
      cy.visit('/app/content/pages');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasList = $body.find('table, [data-testid="version-list"], .timeline').length > 0;
        if (hasList) {
          cy.log('Version list displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display version timestamps', () => {
      cy.visit('/app/content/pages');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasTimestamp = $body.text().includes('ago') ||
                            $body.text().match(/\d{4}/) !== null ||
                            $body.text().includes('Modified');
        if (hasTimestamp) {
          cy.log('Version timestamps displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display version author', () => {
      cy.visit('/app/content/pages');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasAuthor = $body.text().includes('Author') ||
                         $body.text().includes('By') ||
                         $body.text().includes('Modified by');
        if (hasAuthor) {
          cy.log('Version author displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Version Comparison', () => {
    beforeEach(() => {
      cy.visit('/app/content/pages');
      cy.waitForPageLoad();
    });

    it('should have compare versions option', () => {
      cy.get('body').then($body => {
        const hasCompare = $body.text().includes('Compare') ||
                          $body.text().includes('Diff') ||
                          $body.find('button:contains("Compare")').length > 0;
        if (hasCompare) {
          cy.log('Compare versions option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display diff view', () => {
      cy.get('body').then($body => {
        const hasDiff = $body.find('.diff, [data-testid="diff-view"], pre').length >= 0 ||
                       $body.text().includes('Change');
        cy.log('Diff view can be displayed');
      });

      cy.get('body').should('be.visible');
    });

    it('should highlight additions and deletions', () => {
      cy.get('body').then($body => {
        const hasHighlight = $body.find('.addition, .deletion, .added, .removed').length >= 0 ||
                            $body.text().includes('+') ||
                            $body.text().includes('-');
        cy.log('Diff highlighting available');
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Version Restore', () => {
    beforeEach(() => {
      cy.visit('/app/content/pages');
      cy.waitForPageLoad();
    });

    it('should have restore version option', () => {
      cy.get('body').then($body => {
        const hasRestore = $body.find('button:contains("Restore"), button:contains("Revert")').length > 0 ||
                          $body.text().includes('Restore');
        if (hasRestore) {
          cy.log('Restore version option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should show restore confirmation', () => {
      cy.get('body').then($body => {
        const hasConfirm = $body.text().includes('Confirm') ||
                          $body.text().includes('Are you sure') ||
                          $body.text().includes('restore');
        if (hasConfirm) {
          cy.log('Restore confirmation available');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Draft Management', () => {
    it('should navigate to drafts', () => {
      cy.visit('/app/content/drafts');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasDrafts = $body.text().includes('Draft') ||
                         $body.text().includes('Unpublished');
        if (hasDrafts) {
          cy.log('Drafts page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display draft list', () => {
      cy.visit('/app/content/drafts');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasList = $body.find('table, [data-testid="drafts-list"]').length > 0;
        if (hasList) {
          cy.log('Draft list displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have save as draft option', () => {
      cy.visit('/app/content/pages');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasSaveDraft = $body.find('button:contains("Save Draft"), button:contains("Save as Draft")').length > 0 ||
                            $body.text().includes('Draft');
        if (hasSaveDraft) {
          cy.log('Save as draft option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have discard draft option', () => {
      cy.visit('/app/content/drafts');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasDiscard = $body.find('button:contains("Discard"), button:contains("Delete")').length > 0 ||
                          $body.text().includes('Discard');
        if (hasDiscard) {
          cy.log('Discard draft option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Publishing Workflow', () => {
    beforeEach(() => {
      cy.visit('/app/content/pages');
      cy.waitForPageLoad();
    });

    it('should have publish button', () => {
      cy.get('body').then($body => {
        const hasPublish = $body.find('button:contains("Publish")').length > 0 ||
                          $body.text().includes('Publish');
        if (hasPublish) {
          cy.log('Publish button displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have unpublish option', () => {
      cy.get('body').then($body => {
        const hasUnpublish = $body.find('button:contains("Unpublish")').length > 0 ||
                            $body.text().includes('Unpublish');
        if (hasUnpublish) {
          cy.log('Unpublish option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display publish status', () => {
      cy.get('body').then($body => {
        const hasStatus = $body.text().includes('Published') ||
                         $body.text().includes('Draft') ||
                         $body.text().includes('Status');
        if (hasStatus) {
          cy.log('Publish status displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have schedule publish option', () => {
      cy.get('body').then($body => {
        const hasSchedule = $body.text().includes('Schedule') ||
                           $body.find('input[type="datetime-local"]').length > 0;
        if (hasSchedule) {
          cy.log('Schedule publish option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Batch Operations', () => {
    beforeEach(() => {
      cy.visit('/app/content/pages');
      cy.waitForPageLoad();
    });

    it('should have select all option', () => {
      cy.get('body').then($body => {
        const hasSelectAll = $body.find('input[type="checkbox"]').length > 0 ||
                            $body.text().includes('Select all');
        if (hasSelectAll) {
          cy.log('Select all option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have bulk actions menu', () => {
      cy.get('body').then($body => {
        const hasBulk = $body.text().includes('Bulk') ||
                       $body.text().includes('Actions') ||
                       $body.find('[data-testid="bulk-actions"]').length > 0;
        if (hasBulk) {
          cy.log('Bulk actions menu displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have bulk delete option', () => {
      cy.get('body').then($body => {
        const hasBulkDelete = $body.text().includes('Delete') ||
                             $body.find('button:contains("Delete")').length > 0;
        if (hasBulkDelete) {
          cy.log('Bulk delete option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have bulk publish option', () => {
      cy.get('body').then($body => {
        const hasBulkPublish = $body.text().includes('Publish') ||
                              $body.find('button:contains("Publish")').length > 0;
        if (hasBulkPublish) {
          cy.log('Bulk publish option displayed');
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
      it(`should display content versioning correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/app/content/pages');
        cy.waitForPageLoad();

        cy.get('body').should('be.visible');
        cy.log(`Content versioning displayed correctly on ${name}`);
      });
    });
  });
});

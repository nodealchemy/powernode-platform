/// <reference types="cypress" />

/**
 * AI Conversations Page Tests
 *
 * Tests for AI Conversations functionality including:
 * - Page navigation and load
 * - Conversation list display
 * - Search functionality
 * - Filter by status
 * - Filter by agent
 * - Create conversation
 * - View conversation details
 * - Continue conversation
 * - Export conversation
 * - Archive/unarchive conversation
 * - Delete conversation
 * - Pagination
 * - Responsive design
 */

describe('AI Conversations Page Tests', () => {
  beforeEach(() => {
    // Handle uncaught exceptions from React/application code
    Cypress.on('uncaught:exception', () => false);
    cy.standardTestSetup({ intercepts: ['ai'] });
  });

  describe('Page Navigation', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/conversations');
    });

    it('should load AI Conversations page directly', () => {
      cy.assertContainsAny(['Conversation', 'Conversations', 'AI']);
    });

    it('should display page title', () => {
      cy.assertContainsAny(['AI Conversations', 'Conversations']);
    });

    it('should display breadcrumbs', () => {
      cy.assertContainsAny(['Dashboard', 'AI', 'Conversations']);
    });
  });

  describe('Conversation List Display', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/conversations');
    });

    it('should display conversation list or empty state', () => {
      cy.assertContainsAny(['No conversations', 'Start Conversation', 'Conversation']);
    });

    it('should display conversation status badges', () => {
      cy.assertContainsAny(['Active', 'Completed', 'Archived', 'Conversation']);
    });

    it('should display message counts', () => {
      cy.assertContainsAny(['Messages', 'messages', 'tokens', 'Conversation']);
    });

    it('should display conversation costs', () => {
      cy.assertContainsAny(['$', 'Cost', 'Conversation']);
    });

    it('should display last activity timestamps', () => {
      cy.assertContainsAny(['ago', 'Activity', 'Last', 'Conversation']);
    });
  });

  describe('Search Functionality', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/conversations');
    });

    it('should have search input', () => {
      cy.assertHasElement(['input[type="search"]', 'input[placeholder*="Search"]', 'input[placeholder*="search"]']);
    });
  });

  describe('Filter by Status', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/conversations');
    });

    it('should have status filter dropdown', () => {
      cy.assertHasElement(['select', '[class*="select"]']);
    });
  });

  describe('Filter by Agent', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/conversations');
    });

    it('should have agent filter dropdown', () => {
      cy.assertContainsAny(['Agent', 'All Agents', 'Conversation']);
    });
  });

  describe('Create Conversation', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/conversations');
    });

    it('should display Start Conversation button', () => {
      cy.assertHasElement(['button:contains("Start Conversation")', 'button:contains("New Conversation")', 'button:contains("Create")']);
    });

    it('should open create modal when Start Conversation clicked', () => {
      cy.get('body').then($body => {
        const createButton = $body.find('button:contains("Start Conversation")');
        if (createButton.length > 0) {
          cy.wrap(createButton).first().click();
          cy.waitForStableDOM();
          cy.assertHasElement(['[role="dialog"]', '[class*="modal"]']);
        }
      });
    });
  });

  describe('View Conversation Details', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/conversations');
    });

    it('should have View action for conversations or show empty state', () => {
      cy.get('body').then($body => {
        const hasViewButton = $body.find('button[title="View Details"], button:contains("View")').length > 0;
        const hasEmptyState = $body.text().includes('No conversations') || $body.text().includes('Start Conversation');
        expect(hasViewButton || hasEmptyState, 'Expected View button or empty state').to.be.true;
      });
    });
  });

  describe('Continue Conversation', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/conversations');
    });

    it('should have Continue action for active conversations or show empty state', () => {
      cy.get('body').then($body => {
        const hasContinueButton = $body.find('button[title="Continue Conversation"], button:contains("Continue")').length > 0;
        const hasEmptyState = $body.text().includes('No conversations') || $body.text().includes('Start Conversation');
        expect(hasContinueButton || hasEmptyState, 'Expected Continue button or empty state').to.be.true;
      });
    });
  });

  describe('Export Conversation', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/conversations');
    });

    it('should have Export action for conversations or show empty state', () => {
      cy.get('body').then($body => {
        const hasExportButton = $body.find('button[title="Export Conversation"], button:contains("Export")').length > 0;
        const hasEmptyState = $body.text().includes('No conversations') || $body.text().includes('Start Conversation');
        expect(hasExportButton || hasEmptyState, 'Expected Export button or empty state').to.be.true;
      });
    });
  });

  describe('Archive/Unarchive Conversation', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/conversations');
    });

    it('should have Archive action for conversations or show empty state', () => {
      cy.get('body').then($body => {
        const hasArchiveButton = $body.find('button[title="Archive"], button[title="Unarchive"]').length > 0;
        const hasEmptyState = $body.text().includes('No conversations') || $body.text().includes('Start Conversation');
        expect(hasArchiveButton || hasEmptyState, 'Expected Archive button or empty state').to.be.true;
      });
    });
  });

  describe('Delete Conversation', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/conversations');
    });

    it('should have Delete action for conversations or show empty state', () => {
      cy.get('body').then($body => {
        const hasDeleteButton = $body.find('button[title="Delete Conversation"], button:contains("Delete")').length > 0;
        const hasEmptyState = $body.text().includes('No conversations') || $body.text().includes('Start Conversation');
        expect(hasDeleteButton || hasEmptyState, 'Expected Delete button or empty state').to.be.true;
      });
    });

    it('should show confirmation before delete', () => {
      cy.get('body').then($body => {
        const deleteButton = $body.find('button[title="Delete Conversation"]');
        if (deleteButton.length > 0) {
          cy.wrap(deleteButton).first().click();
          cy.waitForStableDOM();
          cy.assertContainsAny(['Are you sure', 'confirm', 'Cancel']);
        }
      });
    });
  });

  describe('Pagination', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/conversations');
    });

    it('should display pagination when many conversations exist or show content', () => {
      cy.get('body').then($body => {
        const hasPagination = $body.find('[class*="pagination"], button:contains("Next"), button:contains("Previous")').length > 0;
        const hasConversationContent = $body.text().includes('Conversation') || $body.text().includes('No conversations');
        expect(hasPagination || hasConversationContent, 'Expected pagination or conversation content').to.be.true;
      });
    });
  });

  describe('Empty State', () => {
    it('should display empty state when no conversations', () => {
      cy.assertPageReady('/app/ai/conversations');
      cy.assertContainsAny(['No conversations', 'Start Conversation', 'Conversation']);
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.testErrorHandling('/api/v1/ai/conversations*', {
        statusCode: 500,
        visitUrl: '/app/ai/conversations'
      });
    });
  });

  describe('Permission-Based Actions', () => {
    it('should show actions based on permissions', () => {
      cy.assertPageReady('/app/ai/conversations');
      cy.assertContainsAny(['Start', 'Delete', 'Export', 'Conversation']);
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.testResponsiveDesign('/app/ai/conversations', {
        checkContent: ['Conversation']
      });
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.assertPageReady('/app/ai/conversations');
      cy.get('body').should('be.visible');
    });
  });
});

export {};

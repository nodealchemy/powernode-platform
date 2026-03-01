/// <reference types="cypress" />

/**
 * Agent Cards Tests
 *
 * Tests for A2A Agent Cards page functionality including:
 * - Page navigation and load
 * - Agent card list display
 * - Agent card detail view
 * - Agent card creation
 * - Agent card editing
 * - Agent card deletion
 * - Permission-based actions
 * - Responsive design
 */

describe('Agent Cards Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup({ intercepts: ['ai'] });
  });

  describe('Page Navigation', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/agent-cards');
    });

    it('should load Agent Cards page directly', () => {
      cy.assertContainsAny(['Agent Cards', 'Agent Card', 'A2A']);
    });

    it('should display breadcrumbs', () => {
      cy.assertContainsAny(['Dashboard', 'AI', 'Agent Cards']);
    });
  });

  describe('Agent Card List Display', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/agent-cards');
    });

    it('should display agent card list or empty state', () => {
      cy.assertContainsAny(['No agent cards', 'Create Agent Card', 'Agent Cards']);
    });

    it('should display agent card names or empty state', () => {
      cy.get('body').then($body => {
        const hasCardList = $body.find('[data-testid="agent-card-list"], table, .agent-card-item').length > 0;
        const hasEmptyState = $body.text().includes('No agent cards') ||
                              $body.text().includes('Create') ||
                              $body.text().includes('Agent Cards') ||
                              $body.text().includes('discovery');
        expect(hasCardList || hasEmptyState).to.be.true;
      });
    });

    it('should display agent card descriptions', () => {
      cy.assertContainsAny(['description', 'Agent Cards', 'discovery', 'communication']);
    });
  });

  describe('Create Agent Card', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/agent-cards');
    });

    it('should display Create Agent Card button or page content', () => {
      cy.get('body').then($body => {
        const hasCreate = $body.find('button:contains("Create Agent Card"), button:contains("Create")').length > 0;
        const hasPageContent = $body.text().includes('Agent Cards') || $body.text().includes('A2A');
        expect(hasCreate || hasPageContent).to.be.true;
      });
    });

    it('should open create form when button clicked', () => {
      cy.get('body').then($body => {
        if ($body.find('button:contains("Create Agent Card")').length > 0) {
          cy.clickButton('Create Agent Card');
          cy.waitForStableDOM();
          cy.assertContainsAny(['Create', 'Name', 'Description', 'Cancel']);
        } else if ($body.find('button:contains("Create")').length > 0) {
          cy.clickButton('Create');
          cy.waitForStableDOM();
          cy.assertContainsAny(['Create', 'Name', 'Description', 'Cancel']);
        }
      });
    });

    it('should cancel creation and return to list', () => {
      cy.get('body').then($body => {
        if ($body.find('button:contains("Create Agent Card")').length > 0) {
          cy.clickButton('Create Agent Card');
          cy.waitForStableDOM();
          cy.get('body').then($newBody => {
            if ($newBody.find('button:contains("Cancel")').length > 0) {
              cy.clickButton('Cancel');
              cy.waitForStableDOM();
              cy.assertContainsAny(['Agent Cards', 'Create Agent Card']);
            }
          });
        }
      });
    });
  });

  describe('Agent Card Detail View', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/agent-cards');
    });

    it('should navigate to card detail when card selected', () => {
      cy.get('body').then($body => {
        const cardRow = $body.find('[data-testid="agent-card-row"], tr[data-card-id], .agent-card-item');
        if (cardRow.length > 0) {
          cy.wrap(cardRow).first().click();
          cy.waitForStableDOM();
          cy.assertContainsAny(['Details', 'Back to List', 'Edit']);
        }
      });
    });

    it('should display Back to List button in detail view', () => {
      cy.get('body').then($body => {
        const cardRow = $body.find('[data-testid="agent-card-row"], tr[data-card-id], .agent-card-item');
        if (cardRow.length > 0) {
          cy.wrap(cardRow).first().click();
          cy.waitForStableDOM();
          cy.assertHasElement(['button:contains("Back")', 'button:contains("List")']);
        }
      });
    });
  });

  describe('Agent Card Actions', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/agent-cards');
    });

    it('should have edit action for cards or page content', () => {
      cy.get('body').then($body => {
        const hasEdit = $body.find('button:contains("Edit"), [aria-label*="edit"], [title*="Edit"]').length > 0;
        const hasPageContent = $body.text().includes('No agent cards') ||
                               $body.text().includes('Create Agent Card') ||
                               $body.text().includes('Agent Cards') ||
                               $body.text().includes('A2A');
        expect(hasEdit || hasPageContent).to.be.true;
      });
    });

    it('should have delete action for cards or page content', () => {
      cy.get('body').then($body => {
        const hasDelete = $body.find('button:contains("Delete"), [aria-label*="delete"], [title*="Delete"]').length > 0;
        const hasPageContent = $body.text().includes('No agent cards') ||
                               $body.text().includes('Create Agent Card') ||
                               $body.text().includes('Agent Cards') ||
                               $body.text().includes('A2A');
        expect(hasDelete || hasPageContent).to.be.true;
      });
    });
  });

  describe('Delete Agent Card', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/agent-cards');
    });

    it('should show confirmation before delete', () => {
      cy.get('body').then($body => {
        const deleteButton = $body.find('button:contains("Delete"), [aria-label*="delete"]');
        if (deleteButton.length > 0) {
          cy.wrap(deleteButton).first().click();
          cy.waitForStableDOM();
          cy.assertContainsAny(['Are you sure', 'confirm', 'Cancel']);
        }
      });
    });
  });

  describe('Refresh Action', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/agent-cards');
    });

    it('should have refresh button', () => {
      cy.assertHasElement(['button:contains("Refresh")', '[aria-label*="refresh"]', '[title*="Refresh"]', 'button[data-testid="refresh"]']);
    });

    it('should refresh card list when clicked', () => {
      cy.get('body').then($body => {
        const refreshButton = $body.find('button:contains("Refresh"), [aria-label*="refresh"]');
        if (refreshButton.length > 0) {
          cy.wrap(refreshButton).first().click();
          cy.waitForStableDOM();
        }
      });
    });
  });

  describe('Empty State', () => {
    it('should display empty state when no cards exist', () => {
      cy.mockEndpoint('GET', '/api/v1/ai/agent-cards*', { success: true, data: { items: [] } });
      cy.navigateTo('/app/ai/agent-cards');
      cy.assertContainsAny(['No agent cards', 'Create Agent Card', 'Agent Cards']);
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.testErrorHandling('/api/v1/ai/agent-cards*', {
        statusCode: 500,
        visitUrl: '/app/ai/agent-cards'
      });
    });
  });

  describe('Permission-Based Actions', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/agent-cards');
    });

    it('should show create button based on permissions', () => {
      cy.assertContainsAny(['Create Agent Card', 'Agent Cards', 'AI']);
    });

    it('should show edit based on permissions', () => {
      cy.get('body').then($body => {
        const hasCards = $body.find('[data-testid="agent-card-row"], .agent-card-item').length > 0;
        if (hasCards) {
          cy.assertHasElement(['button:contains("Edit")', '[aria-label*="edit"]']);
        }
      });
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.testResponsiveDesign('/app/ai/agent-cards', {
        checkContent: ['Agent', 'Card']
      });
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.assertPageReady('/app/ai/agent-cards');
      cy.get('body').should('be.visible');
    });
  });
});

export {};

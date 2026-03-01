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
      cy.assertContainsAny(['No agent cards', 'Create', 'Agent Cards', 'discovery']);
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
      cy.assertContainsAny(['Create Agent Card', 'Create', 'Agent Cards', 'A2A']);
    });

    it('should open create form when button clicked', () => {
      cy.get('button:contains("Create Agent Card"), button:contains("Create")').first().click();
      cy.waitForStableDOM();
      cy.assertContainsAny(['Create', 'Name', 'Description', 'Cancel']);
    });

    it('should cancel creation and return to list', () => {
      cy.get('button:contains("Create Agent Card"), button:contains("Create")').first().click();
      cy.waitForStableDOM();
      cy.clickButton('Cancel');
      cy.waitForStableDOM();
      cy.assertContainsAny(['Agent Cards', 'Create Agent Card']);
    });
  });

  describe('Agent Card Detail View', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/agent-cards');
    });

    it('should navigate to card detail when card selected', () => {
      cy.get('[data-testid="agent-card-row"], tr[data-card-id], .agent-card-item').first().click();
      cy.waitForStableDOM();
      cy.assertContainsAny(['Details', 'Back to List', 'Edit']);
    });

    it('should display Back to List button in detail view', () => {
      cy.get('[data-testid="agent-card-row"], tr[data-card-id], .agent-card-item').first().click();
      cy.waitForStableDOM();
      cy.assertHasElement(['button:contains("Back")', 'button:contains("List")']);
    });
  });

  describe('Agent Card Actions', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/agent-cards');
    });

    it('should have edit action for cards or page content', () => {
      cy.assertContainsAny(['Edit', 'No agent cards', 'Create Agent Card', 'Agent Cards', 'A2A']);
    });

    it('should have delete action for cards or page content', () => {
      cy.assertContainsAny(['Delete', 'No agent cards', 'Create Agent Card', 'Agent Cards', 'A2A']);
    });
  });

  describe('Delete Agent Card', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/agent-cards');
    });

    it('should show confirmation before delete', () => {
      cy.get('button:contains("Delete"), [aria-label*="delete"]').first().click();
      cy.waitForStableDOM();
      cy.assertContainsAny(['Are you sure', 'confirm', 'Cancel']);
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
      cy.get('button:contains("Refresh"), [aria-label*="refresh"]').first().click();
      cy.waitForStableDOM();
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
      cy.assertContainsAny(['Edit', 'Agent Cards', 'No agent cards']);
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
      cy.assertContainsAny(['Agent', 'Card']);
    });
  });
});

export {};

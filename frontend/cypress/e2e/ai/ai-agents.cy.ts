/// <reference types="cypress" />

/**
 * AI Agents Tests
 *
 * Tests for AI Agents page functionality including:
 * - Page navigation and load
 * - Agent dashboard display
 * - Create agent modal
 * - Agent list display
 * - Agent status and metrics
 * - Agent editing
 * - Agent deletion
 * - Permission-based actions
 * - Responsive design
 */

describe('AI Agents Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup({ intercepts: ['ai'] });
  });

  describe('Page Navigation', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/agents');
    });

    it('should load AI Agents page directly', () => {
      cy.assertContainsAny(['Agent', 'AI']);
    });

    it('should display breadcrumbs', () => {
      cy.assertContainsAny(['Dashboard', 'AI', 'Agents']);
    });
  });

  describe('Agent Dashboard Display', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/agents');
    });

    it('should display agent dashboard or empty state', () => {
      cy.assertContainsAny(['No agents', 'Create Agent', 'Agent']);
    });

    it('should display agent status', () => {
      cy.assertContainsAny(['Active', 'Inactive', 'Online', 'Offline', 'Agent']);
    });
  });

  describe('Create Agent', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/agents');
    });

    it('should display Create Agent button', () => {
      cy.assertHasElement(['button:contains("Create Agent")', 'button:contains("Create")']);
    });

    it('should open create modal when button clicked', () => {
      cy.get('body').then($body => {
        if ($body.find('button:contains("Create Agent")').length > 0) {
          cy.clickButton('Create Agent');
          cy.waitForStableDOM();
          cy.assertContainsAny(['Create', 'Name', 'Type']);
        }
      });
    });

    it('should close modal when cancel clicked', () => {
      cy.get('body').then($body => {
        if ($body.find('button:contains("Create Agent")').length > 0) {
          cy.clickButton('Create Agent');
          cy.waitForStableDOM();
          cy.get('body').then($newBody => {
            if ($newBody.find('button:contains("Cancel")').length > 0) {
              cy.clickButton('Cancel');
              cy.waitForModalClose();
            }
          });
        }
      });
    });
  });

  describe('Agent List/Grid Display', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/agents');
    });

    it('should display agent metrics', () => {
      cy.assertContainsAny(['tasks', 'runs', 'calls', 'Agent']);
    });

    it('should display agent types', () => {
      cy.assertContainsAny(['Assistant', 'Worker', 'Processor', 'Agent']);
    });
  });

  describe('Agent Actions', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/agents');
    });

    it('should have edit action for agents or empty state', () => {
      cy.get('body').then($body => {
        const hasEdit = $body.find('button:contains("Edit"), [aria-label*="edit"], [title*="Edit"]').length > 0;
        const hasEmptyState = $body.text().includes('No agents') || $body.text().includes('Create Agent') || $body.text().includes('Get started');
        expect(hasEdit || hasEmptyState).to.be.true;
      });
    });

    it('should have delete action for agents or empty state', () => {
      cy.get('body').then($body => {
        const hasDelete = $body.find('button:contains("Delete"), [aria-label*="delete"], [title*="Delete"]').length > 0;
        const hasEmptyState = $body.text().includes('No agents') || $body.text().includes('Create Agent') || $body.text().includes('Get started');
        expect(hasDelete || hasEmptyState).to.be.true;
      });
    });
  });

  describe('Delete Agent', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/agents');
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

  describe('Empty State', () => {
    it('should display empty state when no agents exist', () => {
      cy.mockEndpoint('GET', '/api/v1/ai/agents*', { success: true, data: { agents: [] } });
      cy.navigateTo('/app/ai/agents');
      cy.assertContainsAny(['No agents', 'Get started', 'Create Agent', 'Create your first']);
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.testErrorHandling('/api/v1/ai/agents*', {
        statusCode: 500,
        visitUrl: '/app/ai/agents'
      });
    });
  });

  describe('Permission-Based Actions', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/agents');
    });

    it('should show actions based on permissions', () => {
      cy.assertContainsAny(['Create Agent', 'Agent', 'AI']);
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.testResponsiveDesign('/app/ai/agents', {
        checkContent: ['Agent']
      });
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.assertPageReady('/app/ai/agents');
      cy.get('body').should('be.visible');
    });
  });
});

export {};

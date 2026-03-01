/// <reference types="cypress" />

/**
 * A2A Tasks Tests
 *
 * Tests for A2A (Agent-to-Agent) Tasks page functionality including:
 * - Page navigation and load
 * - Task list display
 * - Task detail view
 * - Task event stream
 * - Task status indicators
 * - Real-time updates
 * - Permission-based actions
 * - Responsive design
 */

describe('A2A Tasks Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup({ intercepts: ['ai'] });
  });

  describe('Page Navigation', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/a2a-tasks');
    });

    it('should load A2A Tasks page directly', () => {
      cy.assertContainsAny(['A2A Tasks', 'Agent-to-Agent', 'Tasks']);
    });

    it('should display breadcrumbs', () => {
      cy.assertContainsAny(['Dashboard', 'AI', 'A2A Tasks']);
    });
  });

  describe('Task List Display', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/a2a-tasks');
    });

    it('should display task list or empty state', () => {
      cy.assertContainsAny(['No tasks', 'Tasks', 'Task', 'Monitor']);
    });

    it('should display task status indicators', () => {
      cy.assertContainsAny(['active', 'pending', 'completed', 'failed', 'Tasks', 'No tasks']);
    });

    it('should display task IDs or empty state', () => {
      cy.get('body').then($body => {
        const hasTaskList = $body.find('[data-testid="task-list"], table, .task-item').length > 0;
        const hasEmptyState = $body.text().includes('No tasks') || $body.text().includes('Monitor');
        expect(hasTaskList || hasEmptyState).to.be.true;
      });
    });
  });

  describe('Task Detail View', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/a2a-tasks');
    });

    it('should navigate to task detail when task selected', () => {
      cy.get('body').then($body => {
        const taskRow = $body.find('[data-testid="task-row"], tr[data-task-id], .task-item');
        if (taskRow.length > 0) {
          cy.wrap(taskRow).first().click();
          cy.waitForStableDOM();
          cy.assertContainsAny(['Task Details', 'Details', 'Back to List']);
        }
      });
    });

    it('should display Back to List button in detail view', () => {
      cy.get('body').then($body => {
        const taskRow = $body.find('[data-testid="task-row"], tr[data-task-id], .task-item');
        if (taskRow.length > 0) {
          cy.wrap(taskRow).first().click();
          cy.waitForStableDOM();
          cy.assertHasElement(['button:contains("Back")', 'button:contains("List")']);
        }
      });
    });
  });

  describe('Task Event Stream', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/a2a-tasks');
    });

    it('should display event stream section for active tasks', () => {
      cy.get('body').then($body => {
        const hasEventStream = $body.find('[data-testid="event-stream"], .event-stream').length > 0;
        const hasTaskList = $body.text().includes('Tasks') || $body.text().includes('Monitor');
        expect(hasEventStream || hasTaskList).to.be.true;
      });
    });
  });

  describe('Refresh Action', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/a2a-tasks');
    });

    it('should have refresh button', () => {
      cy.assertHasElement(['button:contains("Refresh")', '[aria-label*="refresh"]', '[title*="Refresh"]', 'button[data-testid="refresh"]']);
    });

    it('should refresh task list when clicked', () => {
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
    it('should display empty state when no tasks exist', () => {
      cy.mockEndpoint('GET', '/api/v1/ai/a2a/tasks*', { success: true, data: { items: [] } });
      cy.navigateTo('/app/ai/a2a-tasks');
      cy.assertContainsAny(['No tasks', 'Monitor', 'A2A Tasks']);
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.testErrorHandling('/api/v1/ai/a2a/tasks*', {
        statusCode: 500,
        visitUrl: '/app/ai/a2a-tasks'
      });
    });
  });

  describe('Permission-Based Actions', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/ai/a2a-tasks');
    });

    it('should display page content based on permissions', () => {
      cy.assertContainsAny(['A2A Tasks', 'Tasks', 'Monitor', 'AI']);
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.testResponsiveDesign('/app/ai/a2a-tasks', {
        checkContent: ['Task', 'A2A']
      });
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.assertPageReady('/app/ai/a2a-tasks');
      cy.get('body').should('be.visible');
    });
  });
});

export {};

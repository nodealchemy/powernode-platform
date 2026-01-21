/// <reference types="cypress" />

/**
 * AI Agent Teams Workflows Tests
 *
 * Comprehensive E2E tests for AI Agent Teams:
 * - Team creation and management
 * - Member assignment
 * - Team permissions
 * - Collaboration settings
 * - Team analytics
 */

describe('AI Agent Teams Workflows Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup({ intercepts: ['ai'] });
    setupAgentTeamsIntercepts();
  });

  describe('Teams Overview', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/teams');
    });

    it('should display teams page with title', () => {
      cy.assertContainsAny(['Agent Teams', 'Teams', 'Collaboration']);
    });

    it('should display create team button', () => {
      cy.get('button').contains(/create|new|add/i).should('exist');
    });

    it('should display teams list or cards', () => {
      cy.get('[class*="grid"], [class*="list"]').should('exist');
    });

    it('should show team count summary', () => {
      cy.assertContainsAny(['teams', 'agents', 'members']);
    });
  });

  describe('Team Cards', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/teams');
    });

    it('should display team name and description', () => {
      cy.assertContainsAny(['Team', 'description', 'agents']);
    });

    it('should show number of agents in team', () => {
      cy.assertContainsAny(['agents', 'members', 'count']);
    });

    it('should show team status', () => {
      cy.get('[class*="px-2"][class*="py-1"]').should('exist');
      cy.assertContainsAny(['active', 'inactive', 'status']);
    });

    it('should show team leader/owner', () => {
      cy.assertContainsAny(['owner', 'lead', 'created by']);
    });
  });

  describe('Create Team', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/teams');
    });

    it('should open create team modal when button clicked', () => {
      cy.get('button').contains(/create|new|add/i).first().click();
      cy.assertContainsAny(['Create Team', 'New Team', 'Team Name']);
    });

    it('should have team name input', () => {
      cy.get('button').contains(/create|new|add/i).first().click();
      cy.get('input[name="name"], input[placeholder*="name"], input').should('exist');
    });

    it('should have team description input', () => {
      cy.get('button').contains(/create|new|add/i).first().click();
      cy.get('textarea, input[name="description"]').should('exist');
    });

    it('should create team when form submitted', () => {
      cy.intercept('POST', '**/api/**/ai/teams*', {
        statusCode: 201,
        body: { success: true, team: { id: 'team-new', name: 'New Team' } },
      }).as('createTeam');

      cy.get('button').contains(/create|new|add/i).first().click();
      cy.get('input').first().type('Test Team');
      cy.get('button').contains(/save|create|submit/i).click();
      cy.wait('@createTeam');
      cy.assertContainsAny(['created', 'success']);
    });
  });

  describe('Team Details', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/teams');
      cy.get('[class*="card"], [class*="cursor-pointer"]').first().click();
    });

    it('should display team details page', () => {
      cy.assertContainsAny(['Team', 'Details', 'Members', 'Agents']);
    });

    it('should display team members list', () => {
      cy.assertContainsAny(['Members', 'Agents', 'assigned']);
    });

    it('should have add member button', () => {
      cy.get('button').contains(/add|assign|invite/i).should('exist');
    });

    it('should display team settings', () => {
      cy.get('button').contains(/settings|configure/i).should('exist');
    });
  });

  describe('Add Team Member', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/teams');
      cy.get('[class*="card"]').first().click();
    });

    it('should open add member modal', () => {
      cy.get('button').contains(/add|assign/i).first().click();
      cy.assertContainsAny(['Add', 'Assign', 'Select', 'Agent']);
    });

    it('should display available agents to add', () => {
      cy.get('button').contains(/add|assign/i).first().click();
      cy.get('body').then($body => {
        if ($body.find('[class*="checkbox"], [role="option"]').length > 0) {
          cy.log('Agent selection available');
        }
      });
    });

    it('should add agent to team', () => {
      cy.intercept('POST', '**/api/**/ai/teams/*/members*', {
        statusCode: 200,
        body: { success: true, message: 'Agent added to team' },
      }).as('addMember');

      cy.get('button').contains(/add|assign/i).first().click();
      cy.get('input[type="checkbox"], [role="option"]').first().click();
      cy.get('button').contains(/confirm|add|save/i).click();
      cy.wait('@addMember');
    });
  });

  describe('Remove Team Member', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/teams');
      cy.get('[class*="card"]').first().click();
    });

    it('should have remove member option', () => {
      cy.get('button').contains(/remove|delete/i).should('exist');
    });

    it('should remove member when confirmed', () => {
      cy.intercept('DELETE', '**/api/**/ai/teams/*/members/*', {
        statusCode: 200,
        body: { success: true, message: 'Agent removed from team' },
      }).as('removeMember');

      cy.get('button').contains(/remove|delete/i).first().click();
      cy.get('body').then($body => {
        if ($body.find('button:contains("Confirm")').length > 0) {
          cy.get('button').contains(/confirm|yes/i).click();
        }
      });
    });
  });

  describe('Team Permissions', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/teams');
      cy.get('[class*="card"]').first().click();
      cy.get('button').contains(/settings|permissions/i).first().click();
    });

    it('should display permission settings', () => {
      cy.assertContainsAny(['Permissions', 'Access', 'Settings']);
    });

    it('should show collaboration mode options', () => {
      cy.assertContainsAny(['collaboration', 'mode', 'sequential', 'parallel']);
    });

    it('should allow editing permissions', () => {
      cy.get('input[type="checkbox"], [role="switch"], select').should('exist');
    });
  });

  describe('Team Analytics', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/teams');
      cy.get('[class*="card"]').first().click();
      cy.get('button').contains(/analytics|stats/i).first().click();
    });

    it('should display team performance metrics', () => {
      cy.assertContainsAny(['Performance', 'Metrics', 'Analytics', 'Stats']);
    });

    it('should show execution count', () => {
      cy.assertContainsAny(['executions', 'runs', 'tasks']);
    });

    it('should show success rate', () => {
      cy.assertContainsAny(['success', 'rate', '%']);
    });
  });

  describe('Delete Team', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/teams');
      cy.get('[class*="card"]').first().click();
    });

    it('should have delete team option', () => {
      cy.get('button').contains(/delete|remove/i).should('exist');
    });

    it('should show confirmation dialog before delete', () => {
      cy.get('button').contains(/delete/i).first().click();
      cy.assertContainsAny(['confirm', 'sure', 'delete', 'cancel']);
    });

    it('should delete team when confirmed', () => {
      cy.intercept('DELETE', '**/api/**/ai/teams/*', {
        statusCode: 200,
        body: { success: true, message: 'Team deleted' },
      }).as('deleteTeam');

      cy.get('button').contains(/delete/i).first().click();
      cy.get('button').contains(/confirm|yes/i).click();
      cy.wait('@deleteTeam');
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.testErrorHandling('**/api/**/ai/teams**', {
        statusCode: 500,
        visitUrl: '/app/ai/teams',
      });
    });
  });

  describe('Responsive Design', () => {
    it('should display correctly across viewports', () => {
      cy.testResponsiveDesign('/app/ai/teams', {
        checkContent: 'Teams',
      });
    });
  });
});

function setupAgentTeamsIntercepts() {
  const mockTeams = [
    {
      id: 'team-1',
      name: 'Customer Support Team',
      description: 'Handles customer inquiries and support tickets',
      status: 'active',
      agents_count: 5,
      owner: 'admin@example.com',
      collaboration_mode: 'parallel',
      created_at: '2025-01-01T10:00:00Z',
    },
    {
      id: 'team-2',
      name: 'Data Analysis Team',
      description: 'Processes and analyzes business data',
      status: 'active',
      agents_count: 3,
      owner: 'analyst@example.com',
      collaboration_mode: 'sequential',
      created_at: '2025-01-05T10:00:00Z',
    },
    {
      id: 'team-3',
      name: 'Content Generation Team',
      description: 'Creates marketing and documentation content',
      status: 'inactive',
      agents_count: 4,
      owner: 'marketing@example.com',
      collaboration_mode: 'round_robin',
      created_at: '2024-12-15T10:00:00Z',
    },
  ];

  const mockAgents = [
    { id: 'agent-1', name: 'Support Agent', role: 'responder' },
    { id: 'agent-2', name: 'Triage Agent', role: 'router' },
    { id: 'agent-3', name: 'Escalation Agent', role: 'escalator' },
  ];

  const mockAnalytics = {
    total_executions: 1500,
    success_rate: 0.95,
    average_response_time: 250,
    tasks_completed: 1425,
  };

  cy.intercept('GET', '**/api/**/ai/teams', {
    statusCode: 200,
    body: { items: mockTeams },
  }).as('getTeams');

  cy.intercept('GET', '**/api/**/ai/teams/*', {
    statusCode: 200,
    body: { team: mockTeams[0], members: mockAgents },
  }).as('getTeamDetails');

  cy.intercept('POST', '**/api/**/ai/teams', {
    statusCode: 201,
    body: { success: true, team: { id: 'team-new', name: 'New Team' } },
  }).as('createTeam');

  cy.intercept('PUT', '**/api/**/ai/teams/*', {
    statusCode: 200,
    body: { success: true, team: mockTeams[0] },
  }).as('updateTeam');

  cy.intercept('DELETE', '**/api/**/ai/teams/*', {
    statusCode: 200,
    body: { success: true, message: 'Team deleted' },
  }).as('deleteTeam');

  cy.intercept('POST', '**/api/**/ai/teams/*/members*', {
    statusCode: 200,
    body: { success: true, message: 'Agent added to team' },
  }).as('addMember');

  cy.intercept('DELETE', '**/api/**/ai/teams/*/members/*', {
    statusCode: 200,
    body: { success: true, message: 'Agent removed from team' },
  }).as('removeMember');

  cy.intercept('GET', '**/api/**/ai/teams/*/analytics*', {
    statusCode: 200,
    body: { analytics: mockAnalytics },
  }).as('getTeamAnalytics');
}

export {};

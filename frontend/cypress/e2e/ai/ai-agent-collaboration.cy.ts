/// <reference types="cypress" />

/**
 * AI Agent Collaboration Tests
 *
 * Tests for AI Agent Collaboration functionality including:
 * - Team creation
 * - Agent assignment
 * - Collaboration workflows
 * - Communication channels
 * - Shared context
 * - Collaboration monitoring
 */

describe('AI Agent Collaboration Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Agent Teams', () => {
    it('should navigate to agent teams', () => {
      cy.visit('/app/ai/teams');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Team', 'Group', 'Collaboration']);
    });

    it('should display team list', () => {
      cy.visit('/app/ai/teams');
      cy.waitForPageLoad();

      cy.assertHasElement(['[data-testid="teams-list"]', '.team-card', 'table']);
    });

    it('should have create team button', () => {
      cy.visit('/app/ai/teams');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Create', 'New', 'Create team']);
    });

    it('should display team members count', () => {
      cy.visit('/app/ai/teams');
      cy.waitForPageLoad();

      cy.assertContainsAny(['member', 'agent']);
    });
  });

  describe('Team Creation', () => {
    beforeEach(() => {
      cy.visit('/app/ai/teams/new');
      cy.waitForPageLoad();
    });

    it('should display team creation form', () => {
      cy.assertHasElement(['form', '[data-testid="team-form"]']);
    });

    it('should have team name field', () => {
      cy.assertHasElement(['input[name*="name"]', 'input[placeholder*="name"]']);
    });

    it('should have agent selection', () => {
      cy.assertContainsAny(['Agent', 'Select']);
    });

    it('should have team description field', () => {
      cy.assertHasElement(['textarea', 'input[name*="description"]']);
    });
  });

  describe('Agent Assignment', () => {
    beforeEach(() => {
      cy.visit('/app/ai/teams');
      cy.waitForPageLoad();
    });

    it('should display available agents', () => {
      cy.assertContainsAny(['Agent']);
    });

    it('should have add agent to team option', () => {
      cy.assertContainsAny(['Add', 'Assign', 'Add agent']);
    });

    it('should have remove agent from team option', () => {
      cy.assertContainsAny(['Remove']);
    });

    it('should display agent roles', () => {
      cy.assertContainsAny(['Role', 'Lead', 'Member']);
    });
  });

  describe('Collaboration Workflows', () => {
    it('should navigate to collaboration workflows', () => {
      cy.visit('/app/ai/collaboration');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Collaboration', 'Workflow', 'Team']);
    });

    it('should display active collaborations', () => {
      cy.visit('/app/ai/collaboration');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Active', 'Running']);
    });

    it('should display collaboration status', () => {
      cy.visit('/app/ai/collaboration');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Status', 'Progress', 'Complete']);
    });
  });

  describe('Shared Context', () => {
    beforeEach(() => {
      cy.visit('/app/ai/teams');
      cy.waitForPageLoad();
    });

    it('should display shared context option', () => {
      cy.assertContainsAny(['Context', 'Shared', 'Knowledge']);
    });

    it('should display shared resources', () => {
      cy.assertContainsAny(['Resource', 'Document', 'Data']);
    });
  });

  describe('Collaboration Monitoring', () => {
    it('should navigate to collaboration monitoring', () => {
      cy.visit('/app/ai/collaboration/monitor');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Monitor', 'Activity', 'Log']);
    });

    it('should display agent activity', () => {
      cy.visit('/app/ai/collaboration/monitor');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Activity', 'Action']);
    });

    it('should display communication log', () => {
      cy.visit('/app/ai/collaboration/monitor');
      cy.waitForPageLoad();

      cy.assertContainsAny(['Communication', 'Message', 'Exchange']);
    });
  });

  describe('Responsive Design', () => {
    it('should display agent collaboration correctly across viewports', () => {
      cy.testResponsiveDesign('/app/ai/teams', { checkContent: ['Team', 'Agent'] });
    });
  });
});

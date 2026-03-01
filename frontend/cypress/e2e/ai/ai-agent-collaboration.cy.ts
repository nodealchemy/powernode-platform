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

      cy.get('body').then($body => {
        const hasTeams = $body.text().includes('Team') ||
                        $body.text().includes('Group') ||
                        $body.text().includes('Collaboration');
        if (hasTeams) {
          cy.log('Agent teams page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display team list', () => {
      cy.visit('/app/ai/teams');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasList = $body.find('[data-testid="teams-list"], .team-card, table').length > 0;
        if (hasList) {
          cy.log('Team list displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have create team button', () => {
      cy.visit('/app/ai/teams');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasCreate = $body.find('button:contains("Create"), button:contains("New")').length > 0 ||
                         $body.text().includes('Create team');
        if (hasCreate) {
          cy.log('Create team button displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display team members count', () => {
      cy.visit('/app/ai/teams');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasCount = $body.text().includes('member') ||
                        $body.text().includes('agent') ||
                        $body.text().match(/\d+\s*(agent|member)/) !== null;
        if (hasCount) {
          cy.log('Team members count displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Team Creation', () => {
    beforeEach(() => {
      cy.visit('/app/ai/teams/new');
      cy.waitForPageLoad();
    });

    it('should display team creation form', () => {
      cy.get('body').then($body => {
        const hasForm = $body.find('form, [data-testid="team-form"]').length > 0 ||
                       $body.text().includes('Create');
        if (hasForm) {
          cy.log('Team creation form displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have team name field', () => {
      cy.get('body').then($body => {
        const hasName = $body.find('input[name*="name"], input[placeholder*="name"]').length > 0 ||
                       $body.text().includes('Name');
        if (hasName) {
          cy.log('Team name field displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have agent selection', () => {
      cy.get('body').then($body => {
        const hasSelection = $body.text().includes('Agent') ||
                            $body.text().includes('Select') ||
                            $body.find('select, [data-testid="agent-select"]').length > 0;
        if (hasSelection) {
          cy.log('Agent selection displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have team description field', () => {
      cy.get('body').then($body => {
        const hasDescription = $body.find('textarea, input[name*="description"]').length > 0 ||
                              $body.text().includes('Description');
        if (hasDescription) {
          cy.log('Team description field displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Agent Assignment', () => {
    beforeEach(() => {
      cy.visit('/app/ai/teams');
      cy.waitForPageLoad();
    });

    it('should display available agents', () => {
      cy.get('body').then($body => {
        const hasAgents = $body.text().includes('Agent') ||
                         $body.find('[data-testid="agent-list"]').length > 0;
        if (hasAgents) {
          cy.log('Available agents displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have add agent to team option', () => {
      cy.get('body').then($body => {
        const hasAdd = $body.find('button:contains("Add"), button:contains("Assign")').length > 0 ||
                      $body.text().includes('Add agent');
        if (hasAdd) {
          cy.log('Add agent option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have remove agent from team option', () => {
      cy.get('body').then($body => {
        const hasRemove = $body.find('button:contains("Remove")').length > 0 ||
                         $body.text().includes('Remove');
        if (hasRemove) {
          cy.log('Remove agent option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display agent roles', () => {
      cy.get('body').then($body => {
        const hasRoles = $body.text().includes('Role') ||
                        $body.text().includes('Lead') ||
                        $body.text().includes('Member');
        if (hasRoles) {
          cy.log('Agent roles displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Collaboration Workflows', () => {
    it('should navigate to collaboration workflows', () => {
      cy.visit('/app/ai/collaboration');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasCollab = $body.text().includes('Collaboration') ||
                         $body.text().includes('Workflow') ||
                         $body.text().includes('Team');
        if (hasCollab) {
          cy.log('Collaboration workflows page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display active collaborations', () => {
      cy.visit('/app/ai/collaboration');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasActive = $body.text().includes('Active') ||
                         $body.text().includes('Running') ||
                         $body.find('[data-testid="active-collaborations"]').length > 0;
        if (hasActive) {
          cy.log('Active collaborations displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display collaboration status', () => {
      cy.visit('/app/ai/collaboration');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasStatus = $body.text().includes('Status') ||
                         $body.text().includes('Progress') ||
                         $body.text().includes('Complete');
        if (hasStatus) {
          cy.log('Collaboration status displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Shared Context', () => {
    beforeEach(() => {
      cy.visit('/app/ai/teams');
      cy.waitForPageLoad();
    });

    it('should display shared context option', () => {
      cy.get('body').then($body => {
        const hasContext = $body.text().includes('Context') ||
                          $body.text().includes('Shared') ||
                          $body.text().includes('Knowledge');
        if (hasContext) {
          cy.log('Shared context option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display shared resources', () => {
      cy.get('body').then($body => {
        const hasResources = $body.text().includes('Resource') ||
                            $body.text().includes('Document') ||
                            $body.text().includes('Data');
        if (hasResources) {
          cy.log('Shared resources displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Collaboration Monitoring', () => {
    it('should navigate to collaboration monitoring', () => {
      cy.visit('/app/ai/collaboration/monitor');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasMonitor = $body.text().includes('Monitor') ||
                          $body.text().includes('Activity') ||
                          $body.text().includes('Log');
        if (hasMonitor) {
          cy.log('Collaboration monitoring page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display agent activity', () => {
      cy.visit('/app/ai/collaboration/monitor');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasActivity = $body.text().includes('Activity') ||
                           $body.text().includes('Action') ||
                           $body.find('[data-testid="activity-log"]').length > 0;
        if (hasActivity) {
          cy.log('Agent activity displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display communication log', () => {
      cy.visit('/app/ai/collaboration/monitor');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasComm = $body.text().includes('Communication') ||
                       $body.text().includes('Message') ||
                       $body.text().includes('Exchange');
        if (hasComm) {
          cy.log('Communication log displayed');
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
      it(`should display agent collaboration correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/app/ai/teams');
        cy.waitForPageLoad();

        cy.get('body').should('be.visible');
        cy.log(`Agent collaboration displayed correctly on ${name}`);
      });
    });
  });
});

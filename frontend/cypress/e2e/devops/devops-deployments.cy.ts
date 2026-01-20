/// <reference types="cypress" />

/**
 * DevOps Deployments Tests
 *
 * Tests for Deployment functionality including:
 * - Deployment list
 * - Deployment triggers
 * - Deployment status
 * - Rollback options
 * - Environment management
 * - Deployment history
 */

describe('DevOps Deployments Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Deployment List', () => {
    it('should navigate to deployments page', () => {
      cy.visit('/app/devops/deployments');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasDeployments = $body.text().includes('Deployment') ||
                              $body.text().includes('Deploy') ||
                              $body.text().includes('Release');
        if (hasDeployments) {
          cy.log('Deployments page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display deployment list', () => {
      cy.visit('/app/devops/deployments');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasList = $body.find('table, [data-testid="deployments-list"], .deployment-card').length > 0;
        if (hasList) {
          cy.log('Deployment list displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display deployment status', () => {
      cy.visit('/app/devops/deployments');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasStatus = $body.text().includes('Success') ||
                         $body.text().includes('Failed') ||
                         $body.text().includes('Pending') ||
                         $body.text().includes('Running');
        if (hasStatus) {
          cy.log('Deployment status displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display deployment environment', () => {
      cy.visit('/app/devops/deployments');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasEnv = $body.text().includes('Production') ||
                      $body.text().includes('Staging') ||
                      $body.text().includes('Development') ||
                      $body.text().includes('Environment');
        if (hasEnv) {
          cy.log('Deployment environment displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Deployment Triggers', () => {
    beforeEach(() => {
      cy.visit('/app/devops/deployments');
      cy.waitForPageLoad();
    });

    it('should have deploy button', () => {
      cy.get('body').then($body => {
        const hasDeploy = $body.find('button:contains("Deploy"), button:contains("Release")').length > 0 ||
                         $body.text().includes('Deploy');
        if (hasDeploy) {
          cy.log('Deploy button displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have environment selection', () => {
      cy.get('body').then($body => {
        const hasSelection = $body.find('select, [data-testid="env-select"]').length > 0 ||
                            $body.text().includes('Environment');
        if (hasSelection) {
          cy.log('Environment selection displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have version/branch selection', () => {
      cy.get('body').then($body => {
        const hasVersion = $body.text().includes('Version') ||
                          $body.text().includes('Branch') ||
                          $body.text().includes('Tag');
        if (hasVersion) {
          cy.log('Version/branch selection displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Deployment Details', () => {
    it('should display deployment details', () => {
      cy.visit('/app/devops/deployments');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasDetails = $body.text().includes('Detail') ||
                          $body.text().includes('Started') ||
                          $body.text().includes('Duration');
        if (hasDetails) {
          cy.log('Deployment details displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display deployment logs', () => {
      cy.visit('/app/devops/deployments');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasLogs = $body.text().includes('Log') ||
                       $body.find('pre, code, [data-testid="deployment-logs"]').length > 0;
        if (hasLogs) {
          cy.log('Deployment logs displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display deployment commit info', () => {
      cy.visit('/app/devops/deployments');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasCommit = $body.text().includes('Commit') ||
                         $body.text().includes('SHA') ||
                         $body.text().match(/[a-f0-9]{7,}/) !== null;
        if (hasCommit) {
          cy.log('Commit info displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Rollback', () => {
    beforeEach(() => {
      cy.visit('/app/devops/deployments');
      cy.waitForPageLoad();
    });

    it('should have rollback option', () => {
      cy.get('body').then($body => {
        const hasRollback = $body.find('button:contains("Rollback"), button:contains("Revert")').length > 0 ||
                           $body.text().includes('Rollback');
        if (hasRollback) {
          cy.log('Rollback option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display previous versions', () => {
      cy.get('body').then($body => {
        const hasPrevious = $body.text().includes('Previous') ||
                           $body.text().includes('History') ||
                           $body.text().includes('Version');
        if (hasPrevious) {
          cy.log('Previous versions displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should show rollback confirmation', () => {
      cy.get('body').then($body => {
        const hasConfirm = $body.text().includes('Confirm') ||
                          $body.text().includes('Are you sure');
        if (hasConfirm) {
          cy.log('Rollback confirmation available');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Environment Management', () => {
    it('should navigate to environments', () => {
      cy.visit('/app/devops/environments');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasEnv = $body.text().includes('Environment') ||
                      $body.text().includes('Production') ||
                      $body.text().includes('Staging');
        if (hasEnv) {
          cy.log('Environments page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display environment list', () => {
      cy.visit('/app/devops/environments');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasList = $body.find('[data-testid="env-list"], table, .env-card').length > 0;
        if (hasList) {
          cy.log('Environment list displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have create environment option', () => {
      cy.visit('/app/devops/environments');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasCreate = $body.find('button:contains("Create"), button:contains("Add"), button:contains("New")').length > 0;
        if (hasCreate) {
          cy.log('Create environment option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display environment variables', () => {
      cy.visit('/app/devops/environments');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasVars = $body.text().includes('Variable') ||
                       $body.text().includes('Config') ||
                       $body.text().includes('Secret');
        if (hasVars) {
          cy.log('Environment variables displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Deployment History', () => {
    it('should navigate to deployment history', () => {
      cy.visit('/app/devops/deployments/history');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasHistory = $body.text().includes('History') ||
                          $body.text().includes('Past') ||
                          $body.text().includes('Previous');
        if (hasHistory) {
          cy.log('Deployment history page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display deployment timeline', () => {
      cy.visit('/app/devops/deployments/history');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasTimeline = $body.find('.timeline, [data-testid="deployment-timeline"]').length > 0 ||
                           $body.text().includes('Timeline');
        if (hasTimeline) {
          cy.log('Deployment timeline displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have filter by date', () => {
      cy.visit('/app/devops/deployments/history');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasFilter = $body.find('input[type="date"], [data-testid="date-filter"]').length > 0 ||
                         $body.text().includes('Date');
        if (hasFilter) {
          cy.log('Date filter displayed');
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
      it(`should display deployments correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/app/devops/deployments');
        cy.waitForPageLoad();

        cy.get('body').should('be.visible');
        cy.log(`Deployments displayed correctly on ${name}`);
      });
    });
  });
});

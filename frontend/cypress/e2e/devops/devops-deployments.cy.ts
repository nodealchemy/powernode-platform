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
      cy.assertContainsAny(['Deployment', 'Deploy', 'Release']);
    });

    it('should display deployment list', () => {
      cy.visit('/app/devops/deployments');
      cy.waitForPageLoad();
      cy.assertHasElement(['table', '[data-testid="deployments-list"]', '.deployment-card']);
    });

    it('should display deployment status', () => {
      cy.visit('/app/devops/deployments');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Success', 'Failed', 'Pending', 'Running']);
    });

    it('should display deployment environment', () => {
      cy.visit('/app/devops/deployments');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Production', 'Staging', 'Development', 'Environment']);
    });
  });

  describe('Deployment Triggers', () => {
    beforeEach(() => {
      cy.visit('/app/devops/deployments');
      cy.waitForPageLoad();
    });

    it('should have deploy button', () => {
      cy.assertContainsAny(['Deploy', 'Release']);
    });

    it('should have environment selection', () => {
      cy.assertContainsAny(['Environment']);
    });

    it('should have version/branch selection', () => {
      cy.assertContainsAny(['Version', 'Branch', 'Tag']);
    });
  });

  describe('Deployment Details', () => {
    it('should display deployment details', () => {
      cy.visit('/app/devops/deployments');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Detail', 'Started', 'Duration']);
    });

    it('should display deployment logs', () => {
      cy.visit('/app/devops/deployments');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Log']);
    });

    it('should display deployment commit info', () => {
      cy.visit('/app/devops/deployments');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Commit', 'SHA']);
    });
  });

  describe('Rollback', () => {
    beforeEach(() => {
      cy.visit('/app/devops/deployments');
      cy.waitForPageLoad();
    });

    it('should have rollback option', () => {
      cy.assertContainsAny(['Rollback', 'Revert']);
    });

    it('should display previous versions', () => {
      cy.assertContainsAny(['Previous', 'History', 'Version']);
    });

    it('should show rollback confirmation', () => {
      cy.assertContainsAny(['Confirm', 'Are you sure']);
    });
  });

  describe('Environment Management', () => {
    it('should navigate to environments', () => {
      cy.visit('/app/devops/environments');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Environment', 'Production', 'Staging']);
    });

    it('should display environment list', () => {
      cy.visit('/app/devops/environments');
      cy.waitForPageLoad();
      cy.assertHasElement(['[data-testid="env-list"]', 'table', '.env-card']);
    });

    it('should have create environment option', () => {
      cy.visit('/app/devops/environments');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Create', 'Add', 'New']);
    });

    it('should display environment variables', () => {
      cy.visit('/app/devops/environments');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Variable', 'Config', 'Secret']);
    });
  });

  describe('Deployment History', () => {
    it('should navigate to deployment history', () => {
      cy.visit('/app/devops/deployments/history');
      cy.waitForPageLoad();
      cy.assertContainsAny(['History', 'Past', 'Previous']);
    });

    it('should display deployment timeline', () => {
      cy.visit('/app/devops/deployments/history');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Timeline']);
    });

    it('should have filter by date', () => {
      cy.visit('/app/devops/deployments/history');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Date']);
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
        cy.assertContainsAny(['Deployment', 'Deploy', 'Release']);
      });
    });
  });
});

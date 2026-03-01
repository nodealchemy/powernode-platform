/// <reference types="cypress" />

/**
 * DevOps Pipeline Execution Tests
 *
 * Tests for Pipeline Execution functionality including:
 * - Pipeline trigger and execution
 * - Build status monitoring
 * - Pipeline logs
 * - Execution history
 * - Build artifacts
 * - Pipeline failures
 */

describe('DevOps Pipeline Execution Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup();
  });

  describe('Pipeline Trigger', () => {
    it('should navigate to pipelines page', () => {
      cy.visit('/app/devops/pipelines');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Pipeline', 'Build', 'CI/CD']);
    });

    it('should display run pipeline button', () => {
      cy.visit('/app/devops/pipelines');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Run', 'Trigger', 'Start']);
    });

    it('should display pipeline list', () => {
      cy.visit('/app/devops/pipelines');
      cy.waitForPageLoad();
      cy.assertHasElement(['table', '[data-testid="pipelines-list"]', '.list']);
    });

    it('should display branch selector', () => {
      cy.visit('/app/devops/pipelines');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Branch', 'main', 'master']);
    });
  });

  describe('Build Status Monitoring', () => {
    it('should display current build status', () => {
      cy.visit('/app/devops/pipelines');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Running', 'Success', 'Failed', 'Pending', 'Queued']);
    });

    it('should display build progress indicator', () => {
      cy.visit('/app/devops/pipelines');
      cy.waitForPageLoad();
      cy.assertContainsAny(['%']);
    });

    it('should display build duration', () => {
      cy.visit('/app/devops/pipelines');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Duration', 'min', 'sec']);
    });

    it('should display pipeline stages', () => {
      cy.visit('/app/devops/pipelines');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Stage', 'Build', 'Test', 'Deploy']);
    });
  });

  describe('Pipeline Logs', () => {
    it('should navigate to pipeline logs', () => {
      cy.visit('/app/devops/pipelines');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Log', 'Output', 'Console']);
    });

    it('should display log output', () => {
      cy.visit('/app/devops/pipelines');
      cy.waitForPageLoad();
      cy.assertHasElement(['pre', 'code', '[data-testid="log-output"]', '.terminal']);
    });

    it('should have log search functionality', () => {
      cy.visit('/app/devops/pipelines');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Search']);
    });

    it('should have download logs option', () => {
      cy.visit('/app/devops/pipelines');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Download']);
    });
  });

  describe('Execution History', () => {
    it('should navigate to execution history', () => {
      cy.visit('/app/devops/pipelines/history');
      cy.waitForPageLoad();
      cy.assertContainsAny(['History', 'Past', 'Previous']);
    });

    it('should display execution list', () => {
      cy.visit('/app/devops/pipelines/history');
      cy.waitForPageLoad();
      cy.assertHasElement(['table', '[data-testid="history-list"]']);
    });

    it('should display execution timestamps', () => {
      cy.visit('/app/devops/pipelines/history');
      cy.waitForPageLoad();
      cy.assertContainsAny(['ago', 'Today', 'Yesterday']);
    });

    it('should have re-run option', () => {
      cy.visit('/app/devops/pipelines/history');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Re-run', 'Retry']);
    });
  });

  describe('Build Artifacts', () => {
    it('should display artifacts section', () => {
      cy.visit('/app/devops/pipelines');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Artifact', 'Output', 'Download']);
    });

    it('should have artifact download option', () => {
      cy.visit('/app/devops/pipelines');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Download']);
    });
  });

  describe('Pipeline Failures', () => {
    it('should display failed pipelines filter', () => {
      cy.visit('/app/devops/pipelines?status=failed');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Failed', 'Error']);
    });

    it('should display failure details', () => {
      cy.visit('/app/devops/pipelines');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Error', 'Fail', 'exit code']);
    });

    it('should have cancel running pipeline option', () => {
      cy.visit('/app/devops/pipelines');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Cancel', 'Stop', 'Abort']);
    });
  });

  describe('Responsive Design', () => {
    const viewports = [
      { width: 1280, height: 720, name: 'desktop' },
      { width: 768, height: 1024, name: 'tablet' },
      { width: 375, height: 667, name: 'mobile' },
    ];

    viewports.forEach(({ width, height, name }) => {
      it(`should display pipeline execution correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/app/devops/pipelines');
        cy.waitForPageLoad();
        cy.assertContainsAny(['Pipeline', 'Build', 'CI/CD']);
      });
    });
  });
});

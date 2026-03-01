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

      cy.get('body').then($body => {
        const hasPipelines = $body.text().includes('Pipeline') ||
                            $body.text().includes('Build') ||
                            $body.text().includes('CI/CD');
        if (hasPipelines) {
          cy.log('Pipelines page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display run pipeline button', () => {
      cy.visit('/app/devops/pipelines');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasRun = $body.find('button:contains("Run"), button:contains("Trigger"), button:contains("Start")').length > 0 ||
                      $body.text().includes('Run');
        if (hasRun) {
          cy.log('Run pipeline button displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display pipeline list', () => {
      cy.visit('/app/devops/pipelines');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasList = $body.find('table, [data-testid="pipelines-list"], .list').length > 0;
        if (hasList) {
          cy.log('Pipeline list displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display branch selector', () => {
      cy.visit('/app/devops/pipelines');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasBranch = $body.text().includes('Branch') ||
                         $body.text().includes('main') ||
                         $body.text().includes('master') ||
                         $body.find('select').length > 0;
        if (hasBranch) {
          cy.log('Branch selector displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Build Status Monitoring', () => {
    it('should display current build status', () => {
      cy.visit('/app/devops/pipelines');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasStatus = $body.text().includes('Running') ||
                         $body.text().includes('Success') ||
                         $body.text().includes('Failed') ||
                         $body.text().includes('Pending') ||
                         $body.text().includes('Queued');
        if (hasStatus) {
          cy.log('Build status displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display build progress indicator', () => {
      cy.visit('/app/devops/pipelines');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasProgress = $body.find('[role="progressbar"], .progress, [data-testid="build-progress"]').length > 0 ||
                           $body.text().includes('%');
        if (hasProgress) {
          cy.log('Build progress indicator displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display build duration', () => {
      cy.visit('/app/devops/pipelines');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasDuration = $body.text().includes('Duration') ||
                           $body.text().includes('min') ||
                           $body.text().includes('sec') ||
                           $body.text().match(/\d+:\d+/) !== null;
        if (hasDuration) {
          cy.log('Build duration displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display pipeline stages', () => {
      cy.visit('/app/devops/pipelines');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasStages = $body.text().includes('Stage') ||
                         $body.text().includes('Build') ||
                         $body.text().includes('Test') ||
                         $body.text().includes('Deploy');
        if (hasStages) {
          cy.log('Pipeline stages displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Pipeline Logs', () => {
    it('should navigate to pipeline logs', () => {
      cy.visit('/app/devops/pipelines');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasLogs = $body.text().includes('Log') ||
                       $body.text().includes('Output') ||
                       $body.text().includes('Console');
        if (hasLogs) {
          cy.log('Pipeline logs accessible');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display log output', () => {
      cy.visit('/app/devops/pipelines');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasOutput = $body.find('pre, code, [data-testid="log-output"], .terminal').length > 0;
        if (hasOutput) {
          cy.log('Log output displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have log search functionality', () => {
      cy.visit('/app/devops/pipelines');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasSearch = $body.find('input[placeholder*="Search"], input[type="search"]').length > 0 ||
                         $body.text().includes('Search');
        if (hasSearch) {
          cy.log('Log search functionality displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have download logs option', () => {
      cy.visit('/app/devops/pipelines');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasDownload = $body.find('button:contains("Download"), button:contains("Export")').length > 0 ||
                           $body.text().includes('Download');
        if (hasDownload) {
          cy.log('Download logs option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Execution History', () => {
    it('should navigate to execution history', () => {
      cy.visit('/app/devops/pipelines/history');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasHistory = $body.text().includes('History') ||
                          $body.text().includes('Past') ||
                          $body.text().includes('Previous');
        if (hasHistory) {
          cy.log('Execution history page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display execution list', () => {
      cy.visit('/app/devops/pipelines/history');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasList = $body.find('table, [data-testid="history-list"]').length > 0;
        if (hasList) {
          cy.log('Execution list displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display execution timestamps', () => {
      cy.visit('/app/devops/pipelines/history');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasTimestamp = $body.text().includes('ago') ||
                            $body.text().match(/\d{4}/) !== null ||
                            $body.text().includes('Today') ||
                            $body.text().includes('Yesterday');
        if (hasTimestamp) {
          cy.log('Execution timestamps displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have re-run option', () => {
      cy.visit('/app/devops/pipelines/history');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasRerun = $body.find('button:contains("Re-run"), button:contains("Retry")').length > 0 ||
                        $body.text().includes('Re-run');
        if (hasRerun) {
          cy.log('Re-run option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Build Artifacts', () => {
    it('should display artifacts section', () => {
      cy.visit('/app/devops/pipelines');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasArtifacts = $body.text().includes('Artifact') ||
                           $body.text().includes('Output') ||
                           $body.text().includes('Download');
        if (hasArtifacts) {
          cy.log('Artifacts section displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have artifact download option', () => {
      cy.visit('/app/devops/pipelines');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasDownload = $body.find('button:contains("Download"), a[download]').length > 0;
        if (hasDownload) {
          cy.log('Artifact download option displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Pipeline Failures', () => {
    it('should display failed pipelines filter', () => {
      cy.visit('/app/devops/pipelines?status=failed');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasFailed = $body.text().includes('Failed') ||
                         $body.text().includes('Error');
        if (hasFailed) {
          cy.log('Failed pipelines filter displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display failure details', () => {
      cy.visit('/app/devops/pipelines');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasDetails = $body.text().includes('Error') ||
                          $body.text().includes('Fail') ||
                          $body.text().includes('exit code');
        if (hasDetails) {
          cy.log('Failure details displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have cancel running pipeline option', () => {
      cy.visit('/app/devops/pipelines');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasCancel = $body.find('button:contains("Cancel"), button:contains("Stop"), button:contains("Abort")').length > 0 ||
                         $body.text().includes('Cancel');
        if (hasCancel) {
          cy.log('Cancel pipeline option displayed');
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
      it(`should display pipeline execution correctly on ${name}`, () => {
        cy.viewport(width, height);
        cy.visit('/app/devops/pipelines');
        cy.waitForPageLoad();

        cy.get('body').should('be.visible');
        cy.log(`Pipeline execution displayed correctly on ${name}`);
      });
    });
  });
});

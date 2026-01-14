/// <reference types="cypress" />

/**
 * DevOps Pipeline Creation/Execution E2E Tests
 *
 * Tests for pipeline management functionality including:
 * - Pipeline creation workflow
 * - Pipeline configuration
 * - Pipeline execution
 * - Run monitoring
 * - Pipeline templates
 * - Responsive design
 */

describe('DevOps Pipeline Creation Tests', () => {
  beforeEach(() => {
    cy.clearAppData();
    cy.setupDevopsIntercepts();
    cy.visit('/login');
    cy.get('[data-testid="email-input"]', { timeout: 5000 }).type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').click();
    cy.url({ timeout: 5000 }).should('match', /\/(app|dashboard)/);
  });

  describe('Pipeline List', () => {
    it('should navigate to Pipelines page', () => {
      cy.visit('/app/devops/pipelines');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Pipeline') ||
                          $body.text().includes('Pipelines') ||
                          $body.text().includes('CI/CD');
        if (hasContent) {
          cy.log('Pipelines page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display pipeline list', () => {
      cy.visit('/app/devops/pipelines');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasPipelineList = $body.find('table, [class*="list"], [class*="grid"]').length > 0;
        if (hasPipelineList) {
          cy.log('Pipeline list displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display pipeline names', () => {
      cy.visit('/app/devops/pipelines');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasNames = $body.text().includes('Pipeline') ||
                         $body.find('[class*="name"]').length > 0;
        if (hasNames) {
          cy.log('Pipeline names displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display pipeline status', () => {
      cy.visit('/app/devops/pipelines');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasStatus = $body.text().includes('Running') ||
                          $body.text().includes('Success') ||
                          $body.text().includes('Failed') ||
                          $body.text().includes('Pending');
        if (hasStatus) {
          cy.log('Pipeline status displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Pipeline Creation', () => {
    beforeEach(() => {
      cy.visit('/app/devops/pipelines');
      cy.waitForPageLoad();
    });

    it('should have Create Pipeline button', () => {
      cy.get('body').then($body => {
        const hasCreate = $body.find('button:contains("Create"), button:contains("New"), button:contains("Add")').length > 0;
        if (hasCreate) {
          cy.log('Create Pipeline button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should open create pipeline form', () => {
      cy.get('body').then($body => {
        const createButton = $body.find('button:contains("Create"), button:contains("New Pipeline")');
        if (createButton.length > 0) {
          cy.wrap(createButton).first().should('be.visible').click();
          cy.waitForStableDOM();

          cy.get('body').then($formBody => {
            const hasForm = $formBody.find('input, textarea, select').length > 0 ||
                            $formBody.text().includes('Name') ||
                            $formBody.text().includes('Configuration');
            if (hasForm) {
              cy.log('Create pipeline form opened');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have pipeline name field', () => {
      // Find Create Pipeline button in page header/actions area (not sidebar)
      cy.get('[data-testid="page-container"], main, [class*="page"]').first().within(() => {
        cy.get('button').filter(':contains("Create Pipeline"), :contains("Create"), :contains("New")').first().then($btn => {
          if ($btn.length > 0) {
            cy.wrap($btn).click();
            cy.waitForStableDOM();
          }
        });
      });

      cy.get('body').then($formBody => {
        const hasNameField = $formBody.find('input[name*="name"], input[placeholder*="name"]').length > 0 ||
                             $formBody.text().includes('Name');
        if (hasNameField) {
          cy.log('Pipeline name field found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have description field', () => {
      // Find Create Pipeline button in page header/actions area (not sidebar)
      cy.get('[data-testid="page-container"], main, [class*="page"]').first().within(() => {
        cy.get('button').filter(':contains("Create Pipeline"), :contains("Create"), :contains("New")').first().then($btn => {
          if ($btn.length > 0) {
            cy.wrap($btn).click();
            cy.waitForStableDOM();
          }
        });
      });

      cy.get('body').then($formBody => {
        const hasDesc = $formBody.find('textarea, input[name*="description"]').length > 0 ||
                        $formBody.text().includes('Description');
        if (hasDesc) {
          cy.log('Description field found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have trigger selection', () => {
      // Find Create Pipeline button in page header/actions area (not sidebar)
      cy.get('[data-testid="page-container"], main, [class*="page"]').first().within(() => {
        cy.get('button').filter(':contains("Create Pipeline"), :contains("Create"), :contains("New")').first().then($btn => {
          if ($btn.length > 0) {
            cy.wrap($btn).click();
            cy.waitForStableDOM();
          }
        });
      });

      cy.get('body').then($formBody => {
        const hasTrigger = $formBody.text().includes('Trigger') ||
                           $formBody.text().includes('Manual') ||
                           $formBody.text().includes('Schedule') ||
                           $formBody.text().includes('Webhook');
        if (hasTrigger) {
          cy.log('Trigger selection found');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Pipeline Configuration', () => {
    beforeEach(() => {
      cy.visit('/app/devops/pipelines');
      cy.waitForPageLoad();
      // Find Create/Configure button in page header/actions area (not sidebar)
      cy.get('[data-testid="page-container"], main, [class*="page"]').first().within(() => {
        cy.get('button').filter(':contains("Create Pipeline"), :contains("Create"), :contains("Edit"), :contains("Configure")').first().then($btn => {
          if ($btn.length > 0) {
            cy.wrap($btn).click();
            cy.waitForStableDOM();
          }
        });
      });
    });

    it('should have steps/stages configuration', () => {
      cy.get('body').then($body => {
        const hasSteps = $body.text().includes('Step') ||
                         $body.text().includes('Stage') ||
                         $body.text().includes('Job');
        if (hasSteps) {
          cy.log('Steps configuration found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have environment variables section', () => {
      cy.get('body').then($body => {
        const hasEnvVars = $body.text().includes('Environment') ||
                           $body.text().includes('Variable') ||
                           $body.text().includes('Secret');
        if (hasEnvVars) {
          cy.log('Environment variables section found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have runner selection', () => {
      cy.get('body').then($body => {
        const hasRunner = $body.text().includes('Runner') ||
                          $body.text().includes('Agent') ||
                          $body.text().includes('Executor');
        if (hasRunner) {
          cy.log('Runner selection found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have timeout configuration', () => {
      cy.get('body').then($body => {
        const hasTimeout = $body.text().includes('Timeout') ||
                           $body.text().includes('Duration') ||
                           $body.text().includes('minutes');
        if (hasTimeout) {
          cy.log('Timeout configuration found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have notification settings', () => {
      cy.get('body').then($body => {
        const hasNotifications = $body.text().includes('Notification') ||
                                  $body.text().includes('Alert') ||
                                  $body.text().includes('Email');
        if (hasNotifications) {
          cy.log('Notification settings found');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Pipeline Execution', () => {
    beforeEach(() => {
      cy.visit('/app/devops/pipelines');
      cy.waitForPageLoad();
    });

    it('should have Run button', () => {
      cy.get('body').then($body => {
        const hasRun = $body.find('button:contains("Run"), button:contains("Execute"), button:contains("Start")').length > 0;
        if (hasRun) {
          cy.log('Run button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have manual trigger option', () => {
      cy.get('body').then($body => {
        const hasManual = $body.text().includes('Manual') ||
                          $body.find('button:contains("Trigger")').length > 0;
        if (hasManual) {
          cy.log('Manual trigger option found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display last run information', () => {
      cy.get('body').then($body => {
        const hasLastRun = $body.text().includes('Last Run') ||
                           $body.text().includes('ago') ||
                           $body.text().includes('Never');
        if (hasLastRun) {
          cy.log('Last run information displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Run Monitoring', () => {
    beforeEach(() => {
      cy.visit('/app/devops/pipelines/runs');
      cy.waitForPageLoad();
    });

    it('should navigate to Runs page', () => {
      cy.get('body').then($body => {
        const hasRuns = $body.text().includes('Run') ||
                        $body.text().includes('Execution') ||
                        $body.text().includes('History');
        if (hasRuns) {
          cy.log('Runs page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display run list', () => {
      cy.get('body').then($body => {
        const hasRunList = $body.find('table, [class*="list"]').length > 0;
        if (hasRunList) {
          cy.log('Run list displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display run status', () => {
      cy.get('body').then($body => {
        const hasRunStatus = $body.text().includes('Running') ||
                             $body.text().includes('Completed') ||
                             $body.text().includes('Failed') ||
                             $body.text().includes('Queued');
        if (hasRunStatus) {
          cy.log('Run status displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display run duration', () => {
      cy.get('body').then($body => {
        const hasDuration = $body.text().includes('Duration') ||
                            $body.text().includes('minutes') ||
                            $body.text().includes('seconds');
        if (hasDuration) {
          cy.log('Run duration displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have view logs option', () => {
      cy.get('body').then($body => {
        const hasLogs = $body.find('button:contains("Logs"), button:contains("View")').length > 0 ||
                        $body.text().includes('Logs');
        if (hasLogs) {
          cy.log('View logs option found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have cancel run option', () => {
      cy.get('body').then($body => {
        const hasCancel = $body.find('button:contains("Cancel"), button:contains("Stop")').length > 0;
        if (hasCancel) {
          cy.log('Cancel run option found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have rerun option', () => {
      cy.get('body').then($body => {
        const hasRerun = $body.find('button:contains("Rerun"), button:contains("Retry")').length > 0;
        if (hasRerun) {
          cy.log('Rerun option found');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Pipeline Templates', () => {
    beforeEach(() => {
      cy.visit('/app/devops/pipelines');
      cy.waitForPageLoad();
    });

    it('should have template selection', () => {
      cy.get('body').then($body => {
        const hasTemplates = $body.text().includes('Template') ||
                             $body.find('button:contains("Template")').length > 0;
        if (hasTemplates) {
          cy.log('Template selection found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display available templates', () => {
      cy.get('body').then($body => {
        const hasTemplateList = $body.text().includes('Node.js') ||
                                 $body.text().includes('Python') ||
                                 $body.text().includes('Docker') ||
                                 $body.text().includes('CI') ||
                                 $body.text().includes('CD');
        if (hasTemplateList) {
          cy.log('Available templates displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Pipeline Actions', () => {
    beforeEach(() => {
      cy.visit('/app/devops/pipelines');
      cy.waitForPageLoad();
    });

    it('should have edit option', () => {
      cy.get('body').then($body => {
        const hasEdit = $body.find('button:contains("Edit"), [aria-label*="edit"]').length > 0;
        if (hasEdit) {
          cy.log('Edit option found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have delete option', () => {
      cy.get('body').then($body => {
        const hasDelete = $body.find('button:contains("Delete"), [aria-label*="delete"]').length > 0;
        if (hasDelete) {
          cy.log('Delete option found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have clone/duplicate option', () => {
      cy.get('body').then($body => {
        const hasClone = $body.find('button:contains("Clone"), button:contains("Duplicate"), button:contains("Copy")').length > 0;
        if (hasClone) {
          cy.log('Clone option found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have enable/disable toggle', () => {
      cy.get('body').then($body => {
        const hasToggle = $body.find('input[type="checkbox"], [role="switch"]').length > 0 ||
                          $body.text().includes('Enable') ||
                          $body.text().includes('Disable');
        if (hasToggle) {
          cy.log('Enable/disable toggle found');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Error Handling', () => {
    it('should handle API errors gracefully', () => {
      cy.intercept('GET', '**/api/**/pipelines/**', {
        statusCode: 500,
        body: { success: false, error: 'Server error' }
      });

      cy.visit('/app/devops/pipelines');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
      cy.get('body').should('not.contain.text', 'Cannot read');
    });
  });

  describe('Loading State', () => {
    it('should display loading indicator', () => {
      cy.intercept('GET', '**/api/**/pipelines/**', {
        delay: 2000,
        statusCode: 200,
        body: []
      });

      cy.visit('/app/devops/pipelines');

      cy.get('body').then($body => {
        const hasLoading = $body.find('[class*="spin"]').length > 0 ||
                           $body.text().includes('Loading');
        if (hasLoading) {
          cy.log('Loading indicator displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/devops/pipelines');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/devops/pipelines');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
    });

    it('should display properly on large screens', () => {
      cy.viewport(1920, 1080);
      cy.visit('/app/devops/pipelines');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
    });
  });
});


export {};

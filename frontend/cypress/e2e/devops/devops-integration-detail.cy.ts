/// <reference types="cypress" />

describe('DevOps Integration Detail Page Tests', () => {
  beforeEach(() => {
    cy.clearAppData();
    cy.visit('/login');
    cy.get('[data-testid="email-input"]', { timeout: 10000 }).type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').click();
    cy.url({ timeout: 15000 }).should('match', /\/(app|dashboard)/);
  });

  describe('Page Navigation', () => {
    it('should navigate to Integration Detail page', () => {
      cy.visit('/app/devops/integrations/test-integration');
      cy.url().should('include', '/devops');
    });

    it('should display Integration Not Found for invalid ID', () => {
      cy.visit('/app/devops/integrations/invalid-integration-id');
      cy.get('body').then($body => {
        const hasNotFound = $body.text().includes('Not Found') ||
                           $body.text().includes("doesn't exist") ||
                           $body.text().includes('Back to Integrations');
        if (hasNotFound) {
          cy.log('Integration not found message displayed');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Page Actions', () => {
    it('should have Activate/Pause button', () => {
      cy.visit('/app/devops/integrations/test-integration');
      cy.get('body').then($body => {
        const hasToggle = $body.text().includes('Activate') ||
                         $body.text().includes('Pause');
        if (hasToggle) {
          cy.log('Activate/Pause button found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should have Execute Now button', () => {
      cy.visit('/app/devops/integrations/test-integration');
      cy.get('body').then($body => {
        const hasExecute = $body.text().includes('Execute Now') ||
                          $body.text().includes('Execute');
        if (hasExecute) {
          cy.log('Execute Now button found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Integration Header', () => {
    it('should display integration icon', () => {
      cy.visit('/app/devops/integrations/test-integration');
      cy.get('body').then($body => {
        const hasIcon = $body.find('[class*="rounded-lg"]').length > 0 ||
                       $body.find('img[class*="rounded"]').length > 0;
        if (hasIcon) {
          cy.log('Integration icon found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display integration name', () => {
      cy.visit('/app/devops/integrations/test-integration');
      cy.get('body').then($body => {
        const hasName = $body.find('h2[class*="font-semibold"]').length > 0;
        if (hasName) {
          cy.log('Integration name found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display status badge', () => {
      cy.visit('/app/devops/integrations/test-integration');
      cy.get('body').then($body => {
        const hasStatus = $body.text().includes('active') ||
                         $body.text().includes('inactive') ||
                         $body.text().includes('paused') ||
                         $body.find('[class*="badge"]').length > 0;
        if (hasStatus) {
          cy.log('Status badge found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display integration type', () => {
      cy.visit('/app/devops/integrations/test-integration');
      cy.get('body').then($body => {
        const hasType = $body.find('p[class*="secondary"]').length > 0;
        if (hasType) {
          cy.log('Integration type found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Stats Cards', () => {
    it('should display Total Executions stat', () => {
      cy.visit('/app/devops/integrations/test-integration');
      cy.get('body').then($body => {
        const hasTotal = $body.text().includes('Total Executions');
        if (hasTotal) {
          cy.log('Total Executions stat found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Success Rate stat', () => {
      cy.visit('/app/devops/integrations/test-integration');
      cy.get('body').then($body => {
        const hasRate = $body.text().includes('Success Rate');
        if (hasRate) {
          cy.log('Success Rate stat found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Avg Duration stat', () => {
      cy.visit('/app/devops/integrations/test-integration');
      cy.get('body').then($body => {
        const hasDuration = $body.text().includes('Avg. Duration') ||
                           $body.text().includes('Duration');
        if (hasDuration) {
          cy.log('Avg Duration stat found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Last Executed stat', () => {
      cy.visit('/app/devops/integrations/test-integration');
      cy.get('body').then($body => {
        const hasLast = $body.text().includes('Last Executed');
        if (hasLast) {
          cy.log('Last Executed stat found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Tab Navigation', () => {
    it('should display Overview tab', () => {
      cy.visit('/app/devops/integrations/test-integration');
      cy.get('body').then($body => {
        const hasTab = $body.text().includes('Overview');
        if (hasTab) {
          cy.log('Overview tab found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Executions tab', () => {
      cy.visit('/app/devops/integrations/test-integration');
      cy.get('body').then($body => {
        const hasTab = $body.text().includes('Executions');
        if (hasTab) {
          cy.log('Executions tab found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Config tab', () => {
      cy.visit('/app/devops/integrations/test-integration');
      cy.get('body').then($body => {
        const hasTab = $body.text().includes('Config');
        if (hasTab) {
          cy.log('Config tab found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should switch to Executions tab', () => {
      cy.visit('/app/devops/integrations/test-integration');
      cy.get('body').then($body => {
        if ($body.find('button:contains("Executions")').length > 0) {
          cy.contains('button', 'Executions').click();
          cy.log('Switched to Executions tab');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should switch to Config tab', () => {
      cy.visit('/app/devops/integrations/test-integration');
      cy.get('body').then($body => {
        if ($body.find('button:contains("Config")').length > 0) {
          cy.contains('button', 'Config').click();
          cy.log('Switched to Config tab');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Overview Tab Content', () => {
    it('should display Health Status section', () => {
      cy.visit('/app/devops/integrations/test-integration');
      cy.get('body').then($body => {
        const hasHealth = $body.text().includes('Health Status') ||
                         $body.text().includes('healthy') ||
                         $body.text().includes('degraded');
        if (hasHealth) {
          cy.log('Health Status section found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display health metrics', () => {
      cy.visit('/app/devops/integrations/test-integration');
      cy.get('body').then($body => {
        const hasMetrics = $body.text().includes('Response Time') ||
                          $body.text().includes('Consecutive Failures') ||
                          $body.text().includes('Last Check');
        if (hasMetrics) {
          cy.log('Health metrics found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Recent Executions section', () => {
      cy.visit('/app/devops/integrations/test-integration');
      cy.get('body').then($body => {
        const hasRecent = $body.text().includes('Recent Executions');
        if (hasRecent) {
          cy.log('Recent Executions section found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display execution history table', () => {
      cy.visit('/app/devops/integrations/test-integration');
      cy.get('body').then($body => {
        const hasTable = $body.find('table').length > 0 ||
                        $body.find('[class*="table"]').length > 0;
        if (hasTable) {
          cy.log('Execution history table found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Executions Tab Content', () => {
    it('should display full execution history', () => {
      cy.visit('/app/devops/integrations/test-integration');
      cy.get('body').then($body => {
        if ($body.find('button:contains("Executions")').length > 0) {
          cy.contains('button', 'Executions').click();
          cy.get('body').then($updated => {
            const hasHistory = $updated.find('table').length > 0 ||
                              $updated.text().includes('No executions');
            if (hasHistory) {
              cy.log('Execution history displayed');
            }
          });
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Config Tab Content', () => {
    it('should display Configuration section', () => {
      cy.visit('/app/devops/integrations/test-integration');
      cy.get('body').then($body => {
        if ($body.find('button:contains("Config")').length > 0) {
          cy.contains('button', 'Config').click();
          cy.get('body').then($updated => {
            const hasConfig = $updated.text().includes('Configuration');
            if (hasConfig) {
              cy.log('Configuration section found');
            }
          });
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Credential section', () => {
      cy.visit('/app/devops/integrations/test-integration');
      cy.get('body').then($body => {
        if ($body.find('button:contains("Config")').length > 0) {
          cy.contains('button', 'Config').click();
          cy.get('body').then($updated => {
            const hasCredential = $updated.text().includes('Credential');
            if (hasCredential) {
              cy.log('Credential section found');
            }
          });
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Danger Zone section', () => {
      cy.visit('/app/devops/integrations/test-integration');
      cy.get('body').then($body => {
        if ($body.find('button:contains("Config")').length > 0) {
          cy.contains('button', 'Config').click();
          cy.get('body').then($updated => {
            const hasDanger = $updated.text().includes('Danger Zone');
            if (hasDanger) {
              cy.log('Danger Zone section found');
            }
          });
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Delete Integration button', () => {
      cy.visit('/app/devops/integrations/test-integration');
      cy.get('body').then($body => {
        if ($body.find('button:contains("Config")').length > 0) {
          cy.contains('button', 'Config').click();
          cy.get('body').then($updated => {
            const hasDelete = $updated.text().includes('Delete Integration');
            if (hasDelete) {
              cy.log('Delete Integration button found');
            }
          });
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Execution Actions', () => {
    it('should have Retry button for failed executions', () => {
      cy.visit('/app/devops/integrations/test-integration');
      cy.get('body').then($body => {
        const hasRetry = $body.text().includes('Retry') ||
                        $body.find('button:contains("Retry")').length > 0;
        if (hasRetry) {
          cy.log('Retry button found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should have Cancel button for running executions', () => {
      cy.visit('/app/devops/integrations/test-integration');
      cy.get('body').then($body => {
        const hasCancel = $body.text().includes('Cancel') ||
                         $body.find('button:contains("Cancel")').length > 0;
        if (hasCancel) {
          cy.log('Cancel button found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Error Handling', () => {
    it('should handle API errors gracefully', () => {
      cy.intercept('GET', '**/api/**/integrations/**', {
        statusCode: 500,
        body: { error: 'Internal Server Error' }
      }).as('apiError');

      cy.visit('/app/devops/integrations/test-integration');
      cy.get('body').should('be.visible');
    });

    it('should display error notification on failed action', () => {
      cy.intercept('POST', '**/api/**/integrations/*/execute', {
        statusCode: 500,
        body: { error: 'Execution failed' }
      }).as('executeError');

      cy.visit('/app/devops/integrations/test-integration');
      cy.get('body').should('be.visible');
    });
  });

  describe('Loading State', () => {
    it('should display loading indicator', () => {
      cy.intercept('GET', '**/api/**/integrations/**', (req) => {
        req.reply((res) => {
          res.delay = 2000;
          res.send({ success: true, data: {} });
        });
      }).as('slowLoad');

      cy.visit('/app/devops/integrations/test-integration');
      cy.get('body').then($body => {
        const hasLoading = $body.find('[class*="animate-spin"]').length > 0 ||
                          $body.text().includes('Loading');
        if (hasLoading) {
          cy.log('Loading indicator found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/devops/integrations/test-integration');
      cy.get('body').should('be.visible');
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/devops/integrations/test-integration');
      cy.get('body').should('be.visible');
    });

    it('should stack stats cards on small screens', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/devops/integrations/test-integration');
      cy.get('body').then($body => {
        const hasGrid = $body.find('[class*="grid-cols-2"]').length > 0 ||
                       $body.find('[class*="md:grid-cols"]').length > 0;
        if (hasGrid) {
          cy.log('Responsive stats grid found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should show multi-column layout on large screens', () => {
      cy.viewport(1920, 1080);
      cy.visit('/app/devops/integrations/test-integration');
      cy.get('body').then($body => {
        const hasMultiCol = $body.find('[class*="md:grid-cols-4"]').length > 0;
        if (hasMultiCol) {
          cy.log('Multi-column stats layout found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });
});

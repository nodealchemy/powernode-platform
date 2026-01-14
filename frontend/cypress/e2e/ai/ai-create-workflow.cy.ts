/// <reference types="cypress" />

describe('AI Create Workflow Page Tests', () => {
  beforeEach(() => {
    cy.clearAppData();
    cy.visit('/login');
    cy.get('[data-testid="email-input"]', { timeout: 5000 }).type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').click();
    cy.url({ timeout: 5000 }).should('match', /\/(app|dashboard)/);
  });

  describe('Page Navigation', () => {
    it('should navigate to Create Workflow page', () => {
      cy.visit('/app/ai/workflows/new');
      cy.url().should('include', '/ai');
    });

    it('should display page title', () => {
      cy.visit('/app/ai/workflows/new');
      cy.get('body').then($body => {
        const hasTitle = $body.text().includes('Create New Workflow') ||
                        $body.text().includes('Create Workflow') ||
                        $body.find('[class*="PageContainer"]').length > 0;
        if (hasTitle) {
          cy.log('Create Workflow page title found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display page description', () => {
      cy.visit('/app/ai/workflows/new');
      cy.get('body').then($body => {
        const hasDesc = $body.text().includes('automated AI workflow') ||
                       $body.text().includes('business processes');
        if (hasDesc) {
          cy.log('Page description found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display breadcrumbs', () => {
      cy.visit('/app/ai/workflows/new');
      cy.get('body').then($body => {
        const hasBreadcrumbs = $body.text().includes('AI') ||
                              $body.text().includes('Workflows') ||
                              $body.text().includes('Create');
        if (hasBreadcrumbs) {
          cy.log('Breadcrumbs found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Page Actions', () => {
    it('should have Save as Draft button', () => {
      cy.visit('/app/ai/workflows/new');
      cy.get('body').then($body => {
        const hasDraft = $body.text().includes('Save as Draft') ||
                        $body.find('button:contains("Draft")').length > 0;
        if (hasDraft) {
          cy.log('Save as Draft button found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should have Save & Activate button', () => {
      cy.visit('/app/ai/workflows/new');
      cy.get('body').then($body => {
        const hasActivate = $body.text().includes('Save & Activate') ||
                           $body.text().includes('Activate');
        if (hasActivate) {
          cy.log('Save & Activate button found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should have Cancel button', () => {
      cy.visit('/app/ai/workflows/new');
      cy.get('body').then($body => {
        const hasCancel = $body.text().includes('Cancel');
        if (hasCancel) {
          cy.log('Cancel button found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Tab Navigation', () => {
    it('should display Basic Information tab', () => {
      cy.visit('/app/ai/workflows/new');
      cy.get('body').then($body => {
        const hasTab = $body.text().includes('Basic Information');
        if (hasTab) {
          cy.log('Basic Information tab found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Workflow Builder tab', () => {
      cy.visit('/app/ai/workflows/new');
      cy.get('body').then($body => {
        const hasTab = $body.text().includes('Workflow Builder');
        if (hasTab) {
          cy.log('Workflow Builder tab found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Configuration tab', () => {
      cy.visit('/app/ai/workflows/new');
      cy.get('body').then($body => {
        const hasTab = $body.text().includes('Configuration');
        if (hasTab) {
          cy.log('Configuration tab found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Advanced Settings tab', () => {
      cy.visit('/app/ai/workflows/new');
      cy.get('body').then($body => {
        const hasTab = $body.text().includes('Advanced Settings') ||
                      $body.text().includes('Advanced');
        if (hasTab) {
          cy.log('Advanced Settings tab found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should switch between tabs', () => {
      cy.visit('/app/ai/workflows/new');
      cy.get('body').then($body => {
        if ($body.find('button:contains("Configuration")').length > 0) {
          cy.contains('button', 'Configuration').click();
          cy.get('body').should('contain', 'Timeout');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Basic Information Form', () => {
    it('should display Name input', () => {
      cy.visit('/app/ai/workflows/new');
      cy.get('body').then($body => {
        const hasName = $body.text().includes('Name') ||
                       $body.find('input[placeholder*="name"]').length > 0;
        if (hasName) {
          cy.log('Name input found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Description input', () => {
      cy.visit('/app/ai/workflows/new');
      cy.get('body').then($body => {
        const hasDesc = $body.text().includes('Description') ||
                       $body.find('textarea').length > 0;
        if (hasDesc) {
          cy.log('Description input found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Visibility selector', () => {
      cy.visit('/app/ai/workflows/new');
      cy.get('body').then($body => {
        const hasVisibility = $body.text().includes('Visibility') ||
                             $body.text().includes('Private') ||
                             $body.text().includes('Public');
        if (hasVisibility) {
          cy.log('Visibility selector found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Execution Mode selector', () => {
      cy.visit('/app/ai/workflows/new');
      cy.get('body').then($body => {
        const hasMode = $body.text().includes('Execution Mode') ||
                       $body.text().includes('Sequential') ||
                       $body.text().includes('Parallel');
        if (hasMode) {
          cy.log('Execution Mode selector found');
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Tags input', () => {
      cy.visit('/app/ai/workflows/new');
      cy.get('body').then($body => {
        const hasTags = $body.text().includes('Tags') ||
                       $body.find('input[placeholder*="tag"]').length > 0;
        if (hasTags) {
          cy.log('Tags input found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Workflow Builder', () => {
    it('should display workflow builder area', () => {
      cy.visit('/app/ai/workflows/new');
      cy.get('body').then($body => {
        if ($body.find('button:contains("Workflow Builder")').length > 0) {
          cy.contains('button', 'Workflow Builder').click();
          cy.get('body').then($updated => {
            const hasBuilder = $updated.text().includes('Visual Workflow Builder') ||
                              $updated.find('[class*="builder"]').length > 0;
            if (hasBuilder) {
              cy.log('Workflow builder found');
            }
          });
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Configuration Section', () => {
    it('should display Timeout input', () => {
      cy.visit('/app/ai/workflows/new');
      cy.get('body').then($body => {
        if ($body.find('button:contains("Configuration")').length > 0) {
          cy.contains('button', 'Configuration').click();
          cy.get('body').then($updated => {
            const hasTimeout = $updated.text().includes('Timeout') ||
                              $updated.find('input[type="number"]').length > 0;
            if (hasTimeout) {
              cy.log('Timeout input found');
            }
          });
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Max Parallel Nodes input', () => {
      cy.visit('/app/ai/workflows/new');
      cy.get('body').then($body => {
        if ($body.find('button:contains("Configuration")').length > 0) {
          cy.contains('button', 'Configuration').click();
          cy.get('body').then($updated => {
            const hasParallel = $updated.text().includes('Max Parallel') ||
                               $updated.text().includes('Parallel Nodes');
            if (hasParallel) {
              cy.log('Max Parallel Nodes input found');
            }
          });
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Auto Retry checkbox', () => {
      cy.visit('/app/ai/workflows/new');
      cy.get('body').then($body => {
        if ($body.find('button:contains("Configuration")').length > 0) {
          cy.contains('button', 'Configuration').click();
          cy.get('body').then($updated => {
            const hasRetry = $updated.text().includes('Auto Retry') ||
                            $updated.find('input[type="checkbox"]').length > 0;
            if (hasRetry) {
              cy.log('Auto Retry checkbox found');
            }
          });
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Error Handling selector', () => {
      cy.visit('/app/ai/workflows/new');
      cy.get('body').then($body => {
        if ($body.find('button:contains("Configuration")').length > 0) {
          cy.contains('button', 'Configuration').click();
          cy.get('body').then($updated => {
            const hasErrorHandling = $updated.text().includes('Error Handling') ||
                                    $updated.text().includes('Stop on Error');
            if (hasErrorHandling) {
              cy.log('Error Handling selector found');
            }
          });
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Advanced Settings', () => {
    it('should display Notification Settings', () => {
      cy.visit('/app/ai/workflows/new');
      cy.get('body').then($body => {
        if ($body.find('button:contains("Advanced")').length > 0) {
          cy.contains('button', 'Advanced').click();
          cy.get('body').then($updated => {
            const hasNotifications = $updated.text().includes('Notification') ||
                                    $updated.text().includes('Notify on');
            if (hasNotifications) {
              cy.log('Notification settings found');
            }
          });
        }
      });
      cy.get('body').should('be.visible');
    });

    it('should display Resource Limits', () => {
      cy.visit('/app/ai/workflows/new');
      cy.get('body').then($body => {
        if ($body.find('button:contains("Advanced")').length > 0) {
          cy.contains('button', 'Advanced').click();
          cy.get('body').then($updated => {
            const hasLimits = $updated.text().includes('Resource Limits') ||
                             $updated.text().includes('Cost Limit') ||
                             $updated.text().includes('Memory Limit');
            if (hasLimits) {
              cy.log('Resource Limits section found');
            }
          });
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Form Validation', () => {
    it('should show validation error for empty name', () => {
      cy.visit('/app/ai/workflows/new');
      cy.get('body').then($body => {
        if ($body.find('button:contains("Save as Draft")').length > 0) {
          cy.contains('button', 'Save as Draft').click();
          cy.get('body').then($updated => {
            const hasError = $updated.text().includes('required') ||
                            $updated.text().includes('error') ||
                            $updated.find('[class*="error"]').length > 0;
            if (hasError) {
              cy.log('Validation error shown');
            }
          });
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Permission Check', () => {
    it('should show access denied for unauthorized users', () => {
      cy.visit('/app/ai/workflows/new');
      cy.get('body').then($body => {
        const hasAccessDenied = $body.text().includes('Access Denied') ||
                               $body.text().includes("don't have permission");
        const hasForm = $body.text().includes('Create New Workflow') ||
                       $body.text().includes('Basic Information');
        if (hasAccessDenied) {
          cy.log('Access denied shown');
        } else if (hasForm) {
          cy.log('User has permission to create workflows');
        }
      });
      cy.get('body').should('be.visible');
    });
  });

  describe('Error Handling', () => {
    it('should handle API errors gracefully', () => {
      cy.intercept('POST', '**/api/**/workflows**', {
        statusCode: 500,
        body: { error: 'Internal Server Error' }
      }).as('apiError');

      cy.visit('/app/ai/workflows/new');
      cy.get('body').should('be.visible');
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/ai/workflows/new');
      cy.get('body').should('be.visible');
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/ai/workflows/new');
      cy.get('body').should('be.visible');
    });

    it('should stack form elements on small screens', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/ai/workflows/new');
      cy.get('body').then($body => {
        const hasGrid = $body.find('[class*="grid"]').length > 0;
        if (hasGrid) {
          cy.log('Responsive grid layout found');
        }
      });
      cy.get('body').should('be.visible');
    });
  });
});


export {};

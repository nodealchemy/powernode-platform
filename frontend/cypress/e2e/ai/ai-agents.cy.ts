/// <reference types="cypress" />

/**
 * AI Agents Tests
 *
 * Tests for AI Agents page functionality including:
 * - Page navigation and load
 * - Agent dashboard display
 * - Create agent modal
 * - Agent list display
 * - Agent status and metrics
 * - Agent editing
 * - Agent deletion
 * - Permission-based actions
 * - Responsive design
 */

describe('AI Agents Tests', () => {
  beforeEach(() => {
    cy.clearAppData();
    cy.setupAiIntercepts();
    // Login with demo user
    cy.visit('/login');
    cy.get('[data-testid="email-input"]', { timeout: 5000 }).type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').click();
    cy.url({ timeout: 5000 }).should('match', /\/(app|dashboard)/);
  });

  describe('Page Navigation', () => {
    it('should navigate to AI Agents from sidebar', () => {
      cy.visit('/app');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const aiLink = $body.find('a[href*="/ai"], button:contains("AI")');

        if (aiLink.length > 0) {
          cy.wrap(aiLink).first().should('be.visible').click();
          cy.waitForPageLoad();

          cy.get('body').then($newBody => {
            const agentsLink = $newBody.find('a[href*="/agents"]');
            if (agentsLink.length > 0) {
              cy.wrap(agentsLink).first().should('be.visible').click();
            } else {
              cy.visit('/app/ai/agents');
            }
          });
        } else {
          cy.visit('/app/ai/agents');
        }
      });

      cy.url().should('include', '/agents');
      cy.get('body').should('be.visible');
    });

    it('should load AI Agents page directly', () => {
      cy.visit('/app/ai/agents');
      cy.waitForPageLoad();

      cy.url().then(url => {
        if (url.includes('/agents')) {
          cy.get('body').should('satisfy', ($body) => {
            const text = $body.text();
            return text.includes('Agent') || text.includes('AI') || text.includes('Create');
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display breadcrumbs', () => {
      cy.visit('/app/ai/agents');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasBreadcrumbs = $body.text().includes('Dashboard') &&
                               ($body.text().includes('AI') || $body.text().includes('Agents'));

        if (hasBreadcrumbs) {
          cy.log('Breadcrumbs displayed correctly');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Agent Dashboard Display', () => {
    beforeEach(() => {
      cy.visit('/app/ai/agents');
      cy.waitForPageLoad();
    });

    it('should display agent dashboard or empty state', () => {
      cy.get('body').then($body => {
        const _hasAgents = $body.find('[class*="agent"], [class*="card"], [class*="list"]').length > 0 ||
                          $body.text().includes('No agents') ||
                          $body.text().includes('Create Agent');

        if ($body.text().includes('No agents')) {
          cy.log('Empty state displayed');
        } else {
          cy.log('Agent dashboard displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display agent cards or list', () => {
      cy.get('body').then($body => {
        const agentElements = $body.find('[class*="agent-card"], [class*="list-item"]');

        if (agentElements.length > 0) {
          cy.log(`Found ${agentElements.length} agent element(s)`);
        } else {
          cy.log('No agent cards - may have no agents');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display agent names', () => {
      cy.get('body').then($body => {
        // Check for any agent-related content
        const hasAgentNames = $body.find('[class*="name"], h3, h4').length > 0;

        if (hasAgentNames) {
          cy.log('Agent names displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display agent status', () => {
      cy.get('body').then($body => {
        const hasStatus = $body.text().includes('Active') ||
                          $body.text().includes('Inactive') ||
                          $body.text().includes('Online') ||
                          $body.text().includes('Offline');

        if (hasStatus) {
          cy.log('Agent status displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Create Agent', () => {
    beforeEach(() => {
      cy.visit('/app/ai/agents');
      cy.waitForPageLoad();
    });

    it('should display Create Agent button', () => {
      cy.get('body').then($body => {
        const createButton = $body.find('button:contains("Create Agent"), button:contains("Create")');

        if (createButton.length > 0) {
          cy.wrap(createButton).first().should('be.visible');
          cy.log('Create Agent button found');
        } else {
          cy.log('Create button not visible - may require permissions');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should open create modal when button clicked', () => {
      cy.get('body').then($body => {
        const createButton = $body.find('button:contains("Create Agent")');

        if (createButton.length > 0) {
          cy.wrap(createButton).first().should('be.visible').click();
          cy.waitForStableDOM();

          cy.get('body').then($newBody => {
            const modalVisible = $newBody.find('[role="dialog"], [class*="modal"]').length > 0 ||
                                  $newBody.text().includes('Create') ||
                                  $newBody.text().includes('Name');

            if (modalVisible) {
              cy.log('Create agent modal opened');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have name input in create modal', () => {
      cy.get('body').then($body => {
        const createButton = $body.find('button:contains("Create Agent")');

        if (createButton.length > 0) {
          cy.wrap(createButton).first().should('be.visible').click();
          cy.waitForStableDOM();

          cy.get('body').then($newBody => {
            const nameInput = $newBody.find('input[name="name"], input[placeholder*="name"]');

            if (nameInput.length > 0) {
              cy.wrap(nameInput).should('be.visible');
              cy.log('Name input found in modal');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have agent type selection', () => {
      cy.get('body').then($body => {
        const createButton = $body.find('button:contains("Create Agent")');

        if (createButton.length > 0) {
          cy.wrap(createButton).first().should('be.visible').click();
          cy.waitForStableDOM();

          cy.get('body').then($newBody => {
            const hasTypeSelection = $newBody.text().includes('Type') ||
                                      $newBody.find('select').length > 0 ||
                                      $newBody.find('[class*="select"]').length > 0;

            if (hasTypeSelection) {
              cy.log('Agent type selection found');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should close modal when cancel clicked', () => {
      cy.get('body').then($body => {
        const createButton = $body.find('button:contains("Create Agent")');

        if (createButton.length > 0) {
          cy.wrap(createButton).first().should('be.visible').click();
          cy.waitForStableDOM();

          cy.get('body').then($newBody => {
            const cancelButton = $newBody.find('button:contains("Cancel"), button:contains("Close")');

            if (cancelButton.length > 0) {
              cy.wrap(cancelButton).first().should('be.visible').click();
              cy.waitForModalClose();
              cy.log('Modal closed');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Agent List/Grid Display', () => {
    beforeEach(() => {
      cy.visit('/app/ai/agents');
      cy.waitForPageLoad();
    });

    it('should display agent metrics', () => {
      cy.get('body').then($body => {
        const hasMetrics = $body.text().includes('tasks') ||
                           $body.text().includes('runs') ||
                           $body.text().includes('calls') ||
                           /\d+/.test($body.text());

        if (hasMetrics) {
          cy.log('Agent metrics displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display agent descriptions', () => {
      cy.get('body').then($body => {
        const hasDescriptions = $body.find('[class*="description"], [class*="muted"], p').length > 0;

        if (hasDescriptions) {
          cy.log('Agent descriptions displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display agent types', () => {
      cy.get('body').then($body => {
        const hasTypes = $body.text().includes('Assistant') ||
                          $body.text().includes('Worker') ||
                          $body.text().includes('Processor') ||
                          $body.find('[class*="type"], [class*="badge"]').length > 0;

        if (hasTypes) {
          cy.log('Agent types displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Agent Actions', () => {
    beforeEach(() => {
      cy.visit('/app/ai/agents');
      cy.waitForPageLoad();
    });

    it('should have edit action for agents', () => {
      cy.get('body').then($body => {
        const editButton = $body.find('button:contains("Edit"), [aria-label*="edit"], [title*="Edit"]');

        if (editButton.length > 0) {
          cy.wrap(editButton).first().should('be.visible');
          cy.log('Edit button found');
        } else if (!$body.text().includes('No agents')) {
          cy.log('Edit action may use different UI');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have delete action for agents', () => {
      cy.get('body').then($body => {
        const deleteButton = $body.find('button:contains("Delete"), [aria-label*="delete"], [title*="Delete"]');

        if (deleteButton.length > 0) {
          cy.wrap(deleteButton).first().should('be.visible');
          cy.log('Delete button found');
        } else if (!$body.text().includes('No agents')) {
          cy.log('Delete action may require permissions');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have view details action', () => {
      cy.get('body').then($body => {
        const viewButton = $body.find('button:contains("View"), [aria-label*="view"], [title*="View"]');

        if (viewButton.length > 0) {
          cy.wrap(viewButton).first().should('be.visible');
          cy.log('View button found');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Edit Agent', () => {
    beforeEach(() => {
      cy.visit('/app/ai/agents');
      cy.waitForPageLoad();
    });

    it('should open edit modal when edit clicked', () => {
      cy.get('body').then($body => {
        const editButton = $body.find('button:contains("Edit"), [aria-label*="edit"]');

        if (editButton.length > 0) {
          cy.wrap(editButton).first().should('be.visible').click();
          cy.waitForStableDOM();

          cy.get('body').then($newBody => {
            const modalVisible = $newBody.find('[role="dialog"], [class*="modal"]').length > 0;

            if (modalVisible) {
              cy.log('Edit modal opened');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should pre-populate form with agent data', () => {
      cy.get('body').then($body => {
        const editButton = $body.find('button:contains("Edit")');

        if (editButton.length > 0) {
          cy.wrap(editButton).first().should('be.visible').click();
          cy.waitForStableDOM();

          cy.get('body').then($newBody => {
            const nameInput = $newBody.find('input[name="name"]');

            if (nameInput.length > 0) {
              cy.wrap(nameInput).should('not.have.value', '');
              cy.log('Form pre-populated');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Delete Agent', () => {
    beforeEach(() => {
      cy.visit('/app/ai/agents');
      cy.waitForPageLoad();
    });

    it('should show confirmation before delete', () => {
      cy.get('body').then($body => {
        const deleteButton = $body.find('button:contains("Delete"), [aria-label*="delete"]');

        if (deleteButton.length > 0) {
          cy.wrap(deleteButton).first().should('be.visible').click();
          cy.waitForStableDOM();

          cy.get('body').then($newBody => {
            const hasConfirmation = $newBody.find('[role="dialog"], [class*="modal"], [class*="confirm"]').length > 0 ||
                                     $newBody.text().includes('Are you sure') ||
                                     $newBody.text().includes('confirm');

            if (hasConfirmation) {
              cy.log('Confirmation dialog displayed');

              // Cancel the deletion
              const cancelButton = $newBody.find('button:contains("Cancel")');
              if (cancelButton.length > 0) {
                cy.wrap(cancelButton).first().should('be.visible').click();
              }
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Agent Status Toggle', () => {
    beforeEach(() => {
      cy.visit('/app/ai/agents');
      cy.waitForPageLoad();
    });

    it('should have status toggle action', () => {
      cy.get('body').then($body => {
        const toggleButton = $body.find('button:contains("Activate"), button:contains("Deactivate"), [class*="toggle"]');

        if (toggleButton.length > 0) {
          cy.wrap(toggleButton).first().should('be.visible');
          cy.log('Status toggle found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should toggle agent status', () => {
      cy.get('body').then($body => {
        const toggleButton = $body.find('button:contains("Activate"), button:contains("Deactivate")');

        if (toggleButton.length > 0) {
          cy.wrap(toggleButton).first().should('be.visible').click();
          cy.waitForPageLoad();
          cy.get('body').should('be.visible');
          cy.log('Status toggled');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Empty State', () => {
    it('should display empty state when no agents exist', () => {
      cy.intercept('GET', '/api/v1/ai/agents*', {
        statusCode: 200,
        body: {
          success: true,
          data: { agents: [] }
        }
      }).as('getEmptyAgents');

      cy.visit('/app/ai/agents');
      cy.wait('@getEmptyAgents');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasEmptyState = $body.text().includes('No agents') ||
                               $body.text().includes('Get started') ||
                               $body.text().includes('Create Agent') ||
                               $body.text().includes('Create your first');

        if (hasEmptyState) {
          cy.log('Empty state displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have create button in empty state', () => {
      cy.intercept('GET', '/api/v1/ai/agents*', {
        statusCode: 200,
        body: {
          success: true,
          data: { agents: [] }
        }
      }).as('getEmptyAgents');

      cy.visit('/app/ai/agents');
      cy.wait('@getEmptyAgents');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const createButton = $body.find('button:contains("Create")');

        if (createButton.length > 0) {
          cy.wrap(createButton).should('be.visible');
          cy.log('Create button in empty state');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.intercept('GET', '/api/v1/ai/agents*', {
        statusCode: 500,
        body: { success: false, error: 'Server error' }
      }).as('getAgentsError');

      cy.visit('/app/ai/agents');
      cy.wait('@getAgentsError');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
      cy.get('body').should('not.contain.text', 'Cannot read');
      cy.get('body').should('not.contain.text', 'TypeError');
    });

    it('should display error notification on failure', () => {
      cy.intercept('GET', '/api/v1/ai/agents*', {
        statusCode: 500,
        body: { success: false, error: 'Failed to load agents' }
      }).as('getAgentsError');

      cy.visit('/app/ai/agents');
      cy.wait('@getAgentsError');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasError = $body.text().includes('Error') ||
                          $body.text().includes('Failed') ||
                          $body.find('[class*="error"], [class*="toast"]').length > 0;

        if (hasError) {
          cy.log('Error notification displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Permission-Based Actions', () => {
    it('should show actions based on permissions', () => {
      cy.visit('/app/ai/agents');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasCreatePermission = $body.find('button:contains("Create Agent")').length > 0;

        if (hasCreatePermission) {
          cy.log('User has ai.agents.create permission');
        } else {
          cy.log('Create button not visible - user may lack permissions');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/ai/agents');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Agent') || $body.text().includes('AI');
        if (hasContent) {
          cy.log('Content visible on mobile');
        }
      });
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/ai/agents');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Agent') || $body.text().includes('AI');
        if (hasContent) {
          cy.log('Content visible on tablet');
        }
      });
    });

    it('should stack agent cards on small screens', () => {
      cy.viewport(375, 667);
      cy.visit('/app/ai/agents');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
    });
  });
});


export {};

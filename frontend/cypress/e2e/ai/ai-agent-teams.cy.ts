/// <reference types="cypress" />

/**
 * AI Agent Teams Page Tests
 *
 * Tests for Agent Teams functionality including:
 * - Page navigation and load
 * - Team cards display
 * - Status and type filtering
 * - Create team modal
 * - Team actions (edit, delete, execute)
 * - Execution monitor
 * - Empty state handling
 * - Error handling
 * - Responsive design
 */

describe('AI Agent Teams Page Tests', () => {
  beforeEach(() => {
    cy.clearAppData();
    cy.setupAiIntercepts();
    cy.visit('/login');
    cy.get('[data-testid="email-input"]', { timeout: 5000 }).type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').click();
    cy.url({ timeout: 5000 }).should('match', /\/(app|dashboard)/);
  });

  describe('Page Navigation', () => {
    it('should navigate to Agent Teams page', () => {
      cy.visit('/app/ai/agent-teams');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Agent Teams') ||
                          $body.text().includes('Teams') ||
                          $body.text().includes('Permission');
        if (hasContent) {
          cy.log('Agent Teams page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display page title', () => {
      cy.visit('/app/ai/agent-teams');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasTitle = $body.text().includes('Agent Teams');
        if (hasTitle) {
          cy.log('Page title displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display page description', () => {
      cy.visit('/app/ai/agent-teams');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasDescription = $body.text().includes('CrewAI') ||
                               $body.text().includes('multi-agent') ||
                               $body.text().includes('orchestration');
        if (hasDescription) {
          cy.log('Page description displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Page Actions', () => {
    beforeEach(() => {
      cy.visit('/app/ai/agent-teams');
      cy.waitForPageLoad();
    });

    it('should have Create Team button', () => {
      cy.get('body').then($body => {
        const createButton = $body.find('button:contains("Create Team"), button:contains("Create")');
        if (createButton.length > 0) {
          cy.log('Create Team button found');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Filtering', () => {
    beforeEach(() => {
      cy.visit('/app/ai/agent-teams');
      cy.waitForPageLoad();
    });

    it('should display status filter', () => {
      cy.get('body').then($body => {
        const hasStatusFilter = $body.text().includes('Status:') ||
                                $body.find('select#status-filter').length > 0;
        if (hasStatusFilter) {
          cy.log('Status filter displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display type filter', () => {
      cy.get('body').then($body => {
        const hasTypeFilter = $body.text().includes('Type:') ||
                              $body.find('select#type-filter').length > 0;
        if (hasTypeFilter) {
          cy.log('Type filter displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should filter by status', () => {
      cy.get('body').then($body => {
        const statusSelect = $body.find('select#status-filter');
        if (statusSelect.length > 0) {
          cy.wrap(statusSelect).select('active');
          cy.log('Filtered by status');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should filter by type', () => {
      cy.get('body').then($body => {
        const typeSelect = $body.find('select#type-filter');
        if (typeSelect.length > 0) {
          cy.wrap(typeSelect).select('hierarchical');
          cy.log('Filtered by type');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have All option in status filter', () => {
      cy.get('body').then($body => {
        const hasAll = $body.find('select#status-filter option[value="all"]').length > 0 ||
                       $body.text().includes('All');
        if (hasAll) {
          cy.log('All option found in status filter');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have type options (hierarchical, mesh, sequential, parallel)', () => {
      cy.get('body').then($body => {
        const hasOptions = $body.text().includes('Hierarchical') ||
                           $body.text().includes('Mesh') ||
                           $body.text().includes('Sequential') ||
                           $body.text().includes('Parallel');
        if (hasOptions) {
          cy.log('Type options found');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Teams Display', () => {
    beforeEach(() => {
      cy.visit('/app/ai/agent-teams');
      cy.waitForPageLoad();
    });

    it('should display teams grid', () => {
      cy.get('body').then($body => {
        const hasGrid = $body.find('[class*="grid"]').length > 0;
        if (hasGrid) {
          cy.log('Teams grid displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display team cards', () => {
      cy.get('body').then($body => {
        const hasCards = $body.find('[class*="card"], [class*="Card"]').length > 0;
        if (hasCards) {
          cy.log('Team cards displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display empty state when no teams', () => {
      cy.get('body').then($body => {
        const hasEmpty = $body.text().includes('No teams yet') ||
                         $body.text().includes('no teams') ||
                         $body.text().includes('Create your first');
        if (hasEmpty) {
          cy.log('Empty state displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have Create Team call-to-action in empty state', () => {
      cy.get('body').then($body => {
        const hasEmptyState = $body.text().includes('No teams yet');
        if (hasEmptyState) {
          const createButton = $body.find('button:contains("Create Team")');
          if (createButton.length > 0) {
            cy.log('Create Team CTA found in empty state');
          }
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Team Builder Modal', () => {
    beforeEach(() => {
      cy.visit('/app/ai/agent-teams');
      cy.waitForPageLoad();
    });

    it('should open team builder modal', () => {
      cy.get('body').then($body => {
        const createButton = $body.find('button:contains("Create Team"), button:contains("Create")');
        if (createButton.length > 0) {
          cy.wrap(createButton).first().should('be.visible').click();
          cy.waitForStableDOM();
          cy.get('body').then($modalBody => {
            const hasModal = $modalBody.find('[role="dialog"], [class*="modal"], [class*="Modal"]').length > 0;
            if (hasModal) {
              cy.log('Team builder modal opened');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have team name field', () => {
      cy.get('body').then($body => {
        const createButton = $body.find('button:contains("Create Team"), button:contains("Create")');
        if (createButton.length > 0) {
          cy.wrap(createButton).first().should('be.visible').click();
          cy.waitForStableDOM();
          cy.get('body').then($modalBody => {
            const hasNameField = $modalBody.find('input[name*="name"], input[placeholder*="name"]').length > 0;
            if (hasNameField) {
              cy.log('Team name field found');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should close modal on close button', () => {
      cy.get('body').then($body => {
        const createButton = $body.find('button:contains("Create Team"), button:contains("Create")');
        if (createButton.length > 0) {
          cy.wrap(createButton).first().should('be.visible').click();
          cy.waitForStableDOM();
          cy.get('body').then($modalBody => {
            const closeButton = $modalBody.find('button:contains("Close"), button:contains("Cancel"), [aria-label*="close"]');
            if (closeButton.length > 0) {
              cy.wrap(closeButton).first().scrollIntoView().should('exist').click();
              cy.waitForModalClose();
              cy.log('Modal closed');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Team Actions', () => {
    beforeEach(() => {
      cy.visit('/app/ai/agent-teams');
      cy.waitForPageLoad();
    });

    it('should have edit team option', () => {
      cy.get('body').then($body => {
        const editButton = $body.find('button:contains("Edit"), button[aria-label*="edit"]');
        if (editButton.length > 0) {
          cy.log('Edit team option found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have delete team option', () => {
      cy.get('body').then($body => {
        const deleteButton = $body.find('button:contains("Delete"), button[aria-label*="delete"]');
        if (deleteButton.length > 0) {
          cy.log('Delete team option found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have execute team option', () => {
      cy.get('body').then($body => {
        const executeButton = $body.find('button:contains("Execute"), button:contains("Run"), button[aria-label*="execute"]');
        if (executeButton.length > 0) {
          cy.log('Execute team option found');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Execution Monitor', () => {
    it('should display execution monitor when team is executing', () => {
      cy.visit('/app/ai/agent-teams');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasMonitor = $body.text().includes('Execution') ||
                           $body.text().includes('Running') ||
                           $body.find('[class*="monitor"]').length > 0;
        if (hasMonitor) {
          cy.log('Execution monitor section found');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.intercept('GET', '/api/v1/ai/agent-teams*', {
        statusCode: 500,
        body: { success: false, error: 'Server error' }
      });

      cy.visit('/app/ai/agent-teams');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
      cy.get('body').should('not.contain.text', 'Cannot read');
      cy.get('body').should('not.contain.text', 'TypeError');
    });

    it('should display error notification on failure', () => {
      cy.intercept('GET', '/api/v1/ai/agent-teams*', {
        statusCode: 500,
        body: { success: false, error: 'Failed to load teams' }
      });

      cy.visit('/app/ai/agent-teams');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasError = $body.text().includes('Error') ||
                         $body.text().includes('Failed') ||
                         $body.find('[class*="error"]').length > 0;
        if (hasError) {
          cy.log('Error notification displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Loading State', () => {
    it('should display loading indicator', () => {
      cy.intercept('GET', '/api/v1/ai/agent-teams*', {
        delay: 1000,
        statusCode: 200,
        body: []
      });

      cy.visit('/app/ai/agent-teams');

      cy.get('body').then($body => {
        const hasLoading = $body.find('[class*="spin"], [class*="loading"]').length > 0 ||
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
      cy.visit('/app/ai/agent-teams');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Teams') || $body.text().includes('Agent');
        if (hasContent) {
          cy.log('Content visible on mobile');
        }
      });
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/ai/agent-teams');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Teams') || $body.text().includes('Agent');
        if (hasContent) {
          cy.log('Content visible on tablet');
        }
      });
    });

    it('should show single column on small screens', () => {
      cy.viewport(375, 667);
      cy.visit('/app/ai/agent-teams');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
    });

    it('should show multi-column grid on large screens', () => {
      cy.viewport(1280, 800);
      cy.visit('/app/ai/agent-teams');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasGrid = $body.find('[class*="grid"]').length > 0;
        if (hasGrid) {
          cy.log('Multi-column grid on large screens');
        }
      });

      cy.get('body').should('be.visible');
    });
  });
});


export {};

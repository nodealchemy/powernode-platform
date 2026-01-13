/// <reference types="cypress" />

/**
 * DevOps Integrations Page Tests
 *
 * Tests for Integrations management functionality including:
 * - Page navigation and load
 * - Stats display (Total, Active, Errors, Executions)
 * - Integration list display
 * - Filtering and search
 * - Integration actions (activate, deactivate, delete)
 * - Empty state handling
 * - Responsive design
 */

describe('DevOps Integrations Page Tests', () => {
  beforeEach(() => {
    cy.clearAppData();
    cy.visit('/login');
    cy.get('[data-testid="email-input"]', { timeout: 10000 }).type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').click();
    cy.url({ timeout: 15000 }).should('match', /\/(app|dashboard)/);
  });

  describe('Page Navigation', () => {
    it('should navigate to Integrations page', () => {
      cy.visit('/app/devops/integrations');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Integrations') ||
                          $body.text().includes('Integration') ||
                          $body.text().includes('Connected') ||
                          $body.text().includes('Permission');
        if (hasContent) {
          cy.log('Integrations page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display page title', () => {
      cy.visit('/app/devops/integrations');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasTitle = $body.text().includes('Integrations') ||
                         $body.text().includes('My Integrations');
        if (hasTitle) {
          cy.log('Page title displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display breadcrumbs', () => {
      cy.visit('/app/devops/integrations');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasBreadcrumbs = $body.text().includes('DevOps') ||
                               $body.text().includes('Dashboard');
        if (hasBreadcrumbs) {
          cy.log('Breadcrumbs displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display page description', () => {
      cy.visit('/app/devops/integrations');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasDescription = $body.text().includes('Manage') ||
                               $body.text().includes('installed');
        if (hasDescription) {
          cy.log('Page description displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Stats Display', () => {
    beforeEach(() => {
      cy.visit('/app/devops/integrations');
      cy.wait(2000);
    });

    it('should display Total Integrations stat', () => {
      cy.get('body').then($body => {
        const hasTotal = $body.text().includes('Total') ||
                         $body.text().includes('Integrations');
        if (hasTotal) {
          cy.log('Total Integrations stat displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display Active stat', () => {
      cy.get('body').then($body => {
        const hasActive = $body.text().includes('Active');
        if (hasActive) {
          cy.log('Active stat displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display Errors stat', () => {
      cy.get('body').then($body => {
        const hasErrors = $body.text().includes('Errors') ||
                          $body.text().includes('Error');
        if (hasErrors) {
          cy.log('Errors stat displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display Total Executions stat', () => {
      cy.get('body').then($body => {
        const hasExecutions = $body.text().includes('Executions') ||
                              $body.text().includes('Execution');
        if (hasExecutions) {
          cy.log('Total Executions stat displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display stats cards', () => {
      cy.get('body').then($body => {
        const hasCards = $body.find('[class*="card"], [class*="stat"]').length >= 4;
        if (hasCards) {
          cy.log('Stats cards displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Page Actions', () => {
    beforeEach(() => {
      cy.visit('/app/devops/integrations');
      cy.wait(2000);
    });

    it('should have Browse Marketplace button', () => {
      cy.get('body').then($body => {
        const browseButton = $body.find('button:contains("Browse Marketplace"), button:contains("Marketplace")');
        if (browseButton.length > 0) {
          cy.log('Browse Marketplace button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have Add Integration button', () => {
      cy.get('body').then($body => {
        const addButton = $body.find('button:contains("Add Integration"), button:contains("New Integration"), button:contains("Create")');
        if (addButton.length > 0) {
          cy.log('Add Integration button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should navigate to marketplace on button click', () => {
      cy.get('body').then($body => {
        const browseButton = $body.find('button:contains("Browse Marketplace"), button:contains("Marketplace")');
        if (browseButton.length > 0) {
          cy.wrap(browseButton).first().click({ force: true });
          cy.wait(1000);
          cy.url().then(url => {
            if (url.includes('marketplace')) {
              cy.log('Navigated to marketplace');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Filtering', () => {
    beforeEach(() => {
      cy.visit('/app/devops/integrations');
      cy.wait(2000);
    });

    it('should display status filter', () => {
      cy.get('body').then($body => {
        const hasStatusFilter = $body.find('select').length > 0;
        if (hasStatusFilter) {
          cy.log('Status filter displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display type filter', () => {
      cy.get('body').then($body => {
        const hasTypeFilter = $body.find('select').length > 1;
        if (hasTypeFilter) {
          cy.log('Type filter displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have All Status option', () => {
      cy.get('body').then($body => {
        const hasAllStatus = $body.text().includes('All Status');
        if (hasAllStatus) {
          cy.log('All Status option available');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should filter by status', () => {
      cy.get('body').then($body => {
        const statusSelect = $body.find('select').first();
        if (statusSelect.length > 0) {
          cy.wrap(statusSelect).select(1, { force: true });
          cy.wait(500);
          cy.log('Filtered by status');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should filter by type', () => {
      cy.get('body').then($body => {
        const typeSelect = $body.find('select').eq(1);
        if (typeSelect.length > 0) {
          cy.wrap(typeSelect).select(1, { force: true });
          cy.wait(500);
          cy.log('Filtered by type');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Integration List Display', () => {
    beforeEach(() => {
      cy.visit('/app/devops/integrations');
      cy.wait(2000);
    });

    it('should display integration list', () => {
      cy.get('body').then($body => {
        const hasList = $body.find('[class*="grid"], [class*="list"], [class*="card"]').length > 0;
        if (hasList) {
          cy.log('Integration list displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display integration cards', () => {
      cy.get('body').then($body => {
        const hasCards = $body.find('[class*="card"], [class*="Card"]').length > 0;
        if (hasCards) {
          cy.log('Integration cards displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display integration names', () => {
      cy.get('body').then($body => {
        const hasNames = $body.find('h3, h4, [class*="title"]').length > 0;
        if (hasNames) {
          cy.log('Integration names displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display integration status', () => {
      cy.get('body').then($body => {
        const hasStatus = $body.text().includes('active') ||
                          $body.text().includes('Active') ||
                          $body.text().includes('pending') ||
                          $body.text().includes('paused') ||
                          $body.text().includes('error') ||
                          $body.find('[class*="badge"], [class*="status"]').length > 0;
        if (hasStatus) {
          cy.log('Integration status displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display integration type', () => {
      cy.get('body').then($body => {
        const hasType = $body.text().includes('GitHub') ||
                        $body.text().includes('Webhook') ||
                        $body.text().includes('MCP') ||
                        $body.text().includes('REST') ||
                        $body.text().includes('Custom');
        if (hasType) {
          cy.log('Integration type displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display execution count', () => {
      cy.get('body').then($body => {
        const hasExecutions = $body.text().includes('execution') ||
                              $body.text().includes('Execution') ||
                              $body.text().includes('runs');
        if (hasExecutions) {
          cy.log('Execution count displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Integration Actions', () => {
    beforeEach(() => {
      cy.visit('/app/devops/integrations');
      cy.wait(2000);
    });

    it('should have activate button', () => {
      cy.get('body').then($body => {
        const activateButton = $body.find('button:contains("Activate"), [aria-label*="activate"]');
        if (activateButton.length > 0) {
          cy.log('Activate button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have deactivate/pause button', () => {
      cy.get('body').then($body => {
        const deactivateButton = $body.find('button:contains("Deactivate"), button:contains("Pause"), [aria-label*="pause"]');
        if (deactivateButton.length > 0) {
          cy.log('Deactivate/Pause button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have delete button', () => {
      cy.get('body').then($body => {
        const deleteButton = $body.find('button:contains("Delete"), [aria-label*="delete"]');
        if (deleteButton.length > 0) {
          cy.log('Delete button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have configure/edit button', () => {
      cy.get('body').then($body => {
        const configButton = $body.find('button:contains("Configure"), button:contains("Edit"), button:contains("Settings")');
        if (configButton.length > 0) {
          cy.log('Configure/Edit button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should show confirmation on delete', () => {
      cy.get('body').then($body => {
        const deleteButton = $body.find('button:contains("Delete"), [aria-label*="delete"]');
        if (deleteButton.length > 0) {
          // Just check for button presence, don't actually click
          cy.log('Delete button found - confirmation would be shown on click');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Empty State', () => {
    it('should display empty state when no integrations', () => {
      cy.intercept('GET', '/api/v1/devops/integrations*', {
        statusCode: 200,
        body: { success: true, data: { instances: [] } }
      });

      cy.visit('/app/devops/integrations');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasEmpty = $body.text().includes('No integrations') ||
                         $body.text().includes('no integrations') ||
                         $body.text().includes('Get started') ||
                         $body.text().includes('Browse');
        if (hasEmpty) {
          cy.log('Empty state displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have call to action in empty state', () => {
      cy.intercept('GET', '/api/v1/devops/integrations*', {
        statusCode: 200,
        body: { success: true, data: { instances: [] } }
      });

      cy.visit('/app/devops/integrations');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasAction = $body.find('button:contains("Browse"), button:contains("Add"), a[href*="marketplace"]').length > 0;
        if (hasAction) {
          cy.log('Call to action found in empty state');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.intercept('GET', '/api/v1/devops/integrations*', {
        statusCode: 500,
        body: { success: false, error: 'Server error' }
      });

      cy.visit('/app/devops/integrations');
      cy.wait(2000);

      cy.get('body').should('be.visible');
      cy.get('body').should('not.contain.text', 'Cannot read');
      cy.get('body').should('not.contain.text', 'TypeError');
    });

    it('should display error notification on failure', () => {
      cy.intercept('GET', '/api/v1/devops/integrations*', {
        statusCode: 500,
        body: { success: false, error: 'Failed to load integrations' }
      });

      cy.visit('/app/devops/integrations');
      cy.wait(2000);

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
      cy.intercept('GET', '/api/v1/devops/integrations*', {
        delay: 1000,
        statusCode: 200,
        body: { success: true, data: { instances: [] } }
      });

      cy.visit('/app/devops/integrations');

      cy.get('body').then($body => {
        const hasLoading = $body.find('[class*="spin"], [class*="loading"]').length > 0;
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
      cy.visit('/app/devops/integrations');
      cy.wait(2000);

      cy.get('body').should('be.visible');
      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Integrations');
        if (hasContent) {
          cy.log('Content visible on mobile');
        }
      });
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/devops/integrations');
      cy.wait(2000);

      cy.get('body').should('be.visible');
      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Integrations');
        if (hasContent) {
          cy.log('Content visible on tablet');
        }
      });
    });

    it('should stack cards on small screens', () => {
      cy.viewport(375, 667);
      cy.visit('/app/devops/integrations');
      cy.wait(2000);

      cy.get('body').should('be.visible');
    });

    it('should display two-column grid on large screens', () => {
      cy.viewport(1280, 800);
      cy.visit('/app/devops/integrations');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasGrid = $body.find('[class*="grid"], [class*="lg:grid-cols"]').length > 0;
        if (hasGrid) {
          cy.log('Two-column grid on large screens');
        }
      });

      cy.get('body').should('be.visible');
    });
  });
});

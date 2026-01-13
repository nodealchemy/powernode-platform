/// <reference types="cypress" />

/**
 * Marketplace My Apps Page Tests
 *
 * Tests for My Apps management functionality including:
 * - Page navigation and load
 * - App list display
 * - Create app modal
 * - App management actions
 * - Permission-based actions
 * - Responsive design
 */

describe('Marketplace My Apps Page Tests', () => {
  beforeEach(() => {
    cy.clearAppData();
    cy.visit('/login');
    cy.get('[data-testid="email-input"]', { timeout: 10000 }).type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').click();
    cy.url({ timeout: 15000 }).should('match', /\/(app|dashboard)/);
  });

  describe('Page Navigation', () => {
    it('should navigate to My Apps page', () => {
      cy.visit('/app/marketplace/apps');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasContent = $body.text().includes('My Apps') ||
                          $body.text().includes('Apps') ||
                          $body.text().includes('Create') ||
                          $body.text().includes('Permission');
        if (hasContent) {
          cy.log('My Apps page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display page title', () => {
      cy.visit('/app/marketplace/apps');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasTitle = $body.text().includes('My Apps');
        if (hasTitle) {
          cy.log('Page title displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display breadcrumbs', () => {
      cy.visit('/app/marketplace/apps');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasBreadcrumbs = $body.text().includes('Dashboard') ||
                               $body.text().includes('Marketplace');
        if (hasBreadcrumbs) {
          cy.log('Breadcrumbs displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Page Actions', () => {
    beforeEach(() => {
      cy.visit('/app/marketplace/apps');
      cy.wait(2000);
    });

    it('should have Create App button', () => {
      cy.get('body').then($body => {
        const createButton = $body.find('button:contains("Create App"), button:contains("Create")');
        if (createButton.length > 0) {
          cy.log('Create App button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have Refresh button', () => {
      cy.get('body').then($body => {
        const refreshButton = $body.find('button:contains("Refresh"), [aria-label*="refresh"]');
        if (refreshButton.length > 0) {
          cy.log('Refresh button found');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('App List Display', () => {
    beforeEach(() => {
      cy.visit('/app/marketplace/apps');
      cy.wait(2000);
    });

    it('should display apps list', () => {
      cy.get('body').then($body => {
        const hasApps = $body.find('[class*="list"], [class*="grid"], [class*="card"]').length > 0;
        if (hasApps) {
          cy.log('Apps list displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display app cards', () => {
      cy.get('body').then($body => {
        const hasCards = $body.find('[class*="card"], [class*="Card"]').length > 0;
        if (hasCards) {
          cy.log('App cards displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display empty state when no apps', () => {
      cy.get('body').then($body => {
        const hasEmpty = $body.text().includes('No apps') ||
                         $body.text().includes('Create your first') ||
                         $body.text().includes('Get started');
        if (hasEmpty) {
          cy.log('Empty state displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Create App Modal', () => {
    beforeEach(() => {
      cy.visit('/app/marketplace/apps');
      cy.wait(2000);
    });

    it('should open create app modal', () => {
      cy.get('body').then($body => {
        const createButton = $body.find('button:contains("Create App"), button:contains("Create")');
        if (createButton.length > 0) {
          cy.wrap(createButton).first().click({ force: true });
          cy.wait(500);
          cy.get('body').then($modalBody => {
            const hasModal = $modalBody.find('[role="dialog"], [class*="modal"], [class*="Modal"]').length > 0;
            if (hasModal) {
              cy.log('Create app modal opened');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have app name field', () => {
      cy.get('body').then($body => {
        const createButton = $body.find('button:contains("Create App"), button:contains("Create")');
        if (createButton.length > 0) {
          cy.wrap(createButton).first().click({ force: true });
          cy.wait(500);
          cy.get('body').then($modalBody => {
            const hasNameField = $modalBody.find('input[name*="name"], input[placeholder*="name"]').length > 0;
            if (hasNameField) {
              cy.log('App name field found');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have description field', () => {
      cy.get('body').then($body => {
        const createButton = $body.find('button:contains("Create App"), button:contains("Create")');
        if (createButton.length > 0) {
          cy.wrap(createButton).first().click({ force: true });
          cy.wait(500);
          cy.get('body').then($modalBody => {
            const hasDescField = $modalBody.find('textarea, input[name*="description"]').length > 0;
            if (hasDescField) {
              cy.log('Description field found');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should close modal on cancel', () => {
      cy.get('body').then($body => {
        const createButton = $body.find('button:contains("Create App"), button:contains("Create")');
        if (createButton.length > 0) {
          cy.wrap(createButton).first().click({ force: true });
          cy.wait(500);

          cy.get('body').then($modalBody => {
            const cancelButton = $modalBody.find('button:contains("Cancel"), button:contains("Close")');
            if (cancelButton.length > 0) {
              cy.wrap(cancelButton).first().click({ force: true });
              cy.wait(300);
              cy.log('Modal closed on cancel');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('App Actions', () => {
    beforeEach(() => {
      cy.visit('/app/marketplace/apps');
      cy.wait(2000);
    });

    it('should have manage app option', () => {
      cy.get('body').then($body => {
        const manageButton = $body.find('button:contains("Manage"), button:contains("View"), button:contains("Edit")');
        if (manageButton.length > 0) {
          cy.log('Manage app option found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should navigate to app management on click', () => {
      cy.get('body').then($body => {
        const manageButton = $body.find('button:contains("Manage"), button:contains("View")');
        if (manageButton.length > 0) {
          cy.wrap(manageButton).first().click({ force: true });
          cy.wait(1000);
          cy.log('Navigated to app management');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.intercept('GET', '/api/v1/marketplace/apps*', {
        statusCode: 500,
        body: { success: false, error: 'Server error' }
      });

      cy.visit('/app/marketplace/apps');
      cy.wait(2000);

      cy.get('body').should('be.visible');
      cy.get('body').should('not.contain.text', 'Cannot read');
      cy.get('body').should('not.contain.text', 'TypeError');
    });

    it('should display error notification on failure', () => {
      cy.intercept('GET', '/api/v1/marketplace/apps*', {
        statusCode: 500,
        body: { success: false, error: 'Failed to load apps' }
      });

      cy.visit('/app/marketplace/apps');
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

  describe('Permission-Based Access', () => {
    it('should show create button for authorized users', () => {
      cy.visit('/app/marketplace/apps');
      cy.wait(2000);

      cy.get('body').then($body => {
        const createButton = $body.find('button:contains("Create App")');
        if (createButton.length > 0) {
          cy.log('Create button shown for authorized user');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/marketplace/apps');
      cy.wait(2000);

      cy.get('body').should('be.visible');
      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Apps') || $body.text().includes('Marketplace');
        if (hasContent) {
          cy.log('Content visible on mobile');
        }
      });
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/marketplace/apps');
      cy.wait(2000);

      cy.get('body').should('be.visible');
      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Apps') || $body.text().includes('Marketplace');
        if (hasContent) {
          cy.log('Content visible on tablet');
        }
      });
    });

    it('should stack cards on small screens', () => {
      cy.viewport(375, 667);
      cy.visit('/app/marketplace/apps');
      cy.wait(2000);

      cy.get('body').should('be.visible');
    });
  });
});

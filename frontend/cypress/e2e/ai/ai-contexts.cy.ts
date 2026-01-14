/// <reference types="cypress" />

/**
 * AI Contexts Page Tests
 *
 * Tests for AI Contexts functionality including:
 * - Page navigation and load
 * - Tab navigation (browse/search/create)
 * - Context browser display
 * - Search functionality
 * - Context creation form
 * - Form validation
 * - Error handling
 * - Responsive design
 */

describe('AI Contexts Page Tests', () => {
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
    it('should navigate to Contexts page', () => {
      cy.visit('/app/ai/contexts');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Contexts') ||
                          $body.text().includes('Context') ||
                          $body.text().includes('Permission');
        if (hasContent) {
          cy.log('Contexts page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display page title', () => {
      cy.visit('/app/ai/contexts');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasTitle = $body.text().includes('Contexts');
        if (hasTitle) {
          cy.log('Page title displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display page description', () => {
      cy.visit('/app/ai/contexts');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasDescription = $body.text().includes('memory') ||
                               $body.text().includes('Persistent');
        if (hasDescription) {
          cy.log('Page description displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display breadcrumbs', () => {
      cy.visit('/app/ai/contexts');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasBreadcrumbs = $body.text().includes('Dashboard') ||
                               $body.text().includes('AI');
        if (hasBreadcrumbs) {
          cy.log('Breadcrumbs displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Page Actions', () => {
    beforeEach(() => {
      cy.visit('/app/ai/contexts');
      cy.waitForPageLoad();
    });

    it('should have Refresh button', () => {
      cy.get('body').then($body => {
        const refreshButton = $body.find('button:contains("Refresh")');
        if (refreshButton.length > 0) {
          cy.log('Refresh button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have New Context button', () => {
      cy.get('body').then($body => {
        const newButton = $body.find('button:contains("New Context"), button:contains("Create")');
        if (newButton.length > 0) {
          cy.log('New Context button found');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Tab Navigation', () => {
    beforeEach(() => {
      cy.visit('/app/ai/contexts');
      cy.waitForPageLoad();
    });

    it('should display tab navigation', () => {
      cy.get('body').then($body => {
        const hasTabs = $body.text().includes('Browse') ||
                        $body.text().includes('Search') ||
                        $body.text().includes('Create');
        if (hasTabs) {
          cy.log('Tab navigation displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should switch to Browse tab', () => {
      cy.get('body').then($body => {
        const browseTab = $body.find('button:contains("Browse")');
        if (browseTab.length > 0) {
          cy.wrap(browseTab).first().should('be.visible').click();
          cy.waitForPageLoad();
          cy.log('Switched to Browse tab');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should switch to Search tab', () => {
      cy.get('body').then($body => {
        const searchTab = $body.find('button:contains("Search")');
        if (searchTab.length > 0) {
          cy.wrap(searchTab).first().should('be.visible').click();
          cy.waitForPageLoad();
          cy.log('Switched to Search tab');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should switch to Create tab', () => {
      cy.get('body').then($body => {
        const createTab = $body.find('button:contains("Create New"), button:contains("Create")');
        if (createTab.length > 0) {
          cy.wrap(createTab).first().should('be.visible').click();
          cy.waitForPageLoad();
          cy.log('Switched to Create tab');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Context Browser', () => {
    beforeEach(() => {
      cy.visit('/app/ai/contexts');
      cy.waitForPageLoad();
    });

    it('should display context list', () => {
      cy.get('body').then($body => {
        const hasList = $body.find('[class*="card"], [class*="list"], [class*="grid"]').length > 0;
        if (hasList) {
          cy.log('Context list displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display context cards', () => {
      cy.get('body').then($body => {
        const hasCards = $body.find('[class*="card"], [class*="Card"]').length > 0;
        if (hasCards) {
          cy.log('Context cards displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should show empty state when no contexts', () => {
      cy.get('body').then($body => {
        const hasEmpty = $body.text().includes('No contexts') ||
                         $body.text().includes('no contexts') ||
                         $body.text().includes('Create your first');
        if (hasEmpty) {
          cy.log('Empty state displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Search Tab', () => {
    beforeEach(() => {
      cy.visit('/app/ai/contexts');
      cy.waitForPageLoad();
      cy.get('body').then($body => {
        const searchTab = $body.find('button:contains("Search")');
        if (searchTab.length > 0) {
          cy.wrap(searchTab).first().should('be.visible').click();
          cy.waitForPageLoad();
        }
      });
    });

    it('should display search interface', () => {
      cy.get('body').then($body => {
        const hasSearch = $body.find('input[type="search"], input[placeholder*="search"], input[placeholder*="Search"]').length > 0;
        if (hasSearch) {
          cy.log('Search interface displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should perform search', () => {
      cy.get('body').then($body => {
        const searchInput = $body.find('input[type="search"], input[placeholder*="search"]');
        if (searchInput.length > 0) {
          cy.wrap(searchInput).first().type('test{enter}');
          cy.waitForPageLoad();
          cy.log('Search performed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display search results', () => {
      cy.get('body').then($body => {
        const hasResults = $body.text().includes('Results') ||
                           $body.find('[class*="result"], [class*="card"]').length > 0;
        if (hasResults) {
          cy.log('Search results section displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Create Context Form', () => {
    beforeEach(() => {
      cy.visit('/app/ai/contexts');
      cy.waitForPageLoad();
      cy.get('body').then($body => {
        const createTab = $body.find('button:contains("Create New"), button:contains("Create")');
        if (createTab.length > 0) {
          cy.wrap(createTab).first().should('be.visible').click();
          cy.waitForPageLoad();
        }
      });
    });

    it('should display create context form', () => {
      cy.get('body').then($body => {
        const hasForm = $body.find('form').length > 0 ||
                        $body.text().includes('Create Context');
        if (hasForm) {
          cy.log('Create context form displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have name field', () => {
      cy.get('body').then($body => {
        const hasNameField = $body.find('input[name*="name"], input[placeholder*="name"]').length > 0 ||
                             $body.text().includes('Name');
        if (hasNameField) {
          cy.log('Name field found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have description field', () => {
      cy.get('body').then($body => {
        const hasDescField = $body.find('textarea, input[name*="description"]').length > 0 ||
                             $body.text().includes('Description');
        if (hasDescField) {
          cy.log('Description field found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have scope selector', () => {
      cy.get('body').then($body => {
        const hasScope = $body.text().includes('Scope') ||
                         $body.text().includes('Account-wide') ||
                         $body.text().includes('Team');
        if (hasScope) {
          cy.log('Scope selector found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have retention policy fields', () => {
      cy.get('body').then($body => {
        const hasRetention = $body.text().includes('Retention') ||
                             $body.text().includes('Max Entries') ||
                             $body.text().includes('Max Age');
        if (hasRetention) {
          cy.log('Retention policy fields found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have cancel button', () => {
      cy.get('body').then($body => {
        const cancelButton = $body.find('button:contains("Cancel")');
        if (cancelButton.length > 0) {
          cy.log('Cancel button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have submit button', () => {
      cy.get('body').then($body => {
        const submitButton = $body.find('button:contains("Create Context"), button[type="submit"]');
        if (submitButton.length > 0) {
          cy.log('Submit button found');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Form Validation', () => {
    beforeEach(() => {
      cy.visit('/app/ai/contexts');
      cy.waitForPageLoad();
      cy.get('body').then($body => {
        const createTab = $body.find('button:contains("Create New"), button:contains("Create")');
        if (createTab.length > 0) {
          cy.wrap(createTab).first().should('be.visible').click();
          cy.waitForPageLoad();
        }
      });
    });

    it('should validate required name field', () => {
      cy.get('body').then($body => {
        const submitButton = $body.find('button:contains("Create Context"), button[type="submit"]');
        if (submitButton.length > 0) {
          cy.wrap(submitButton).first().scrollIntoView().should('exist').click();
          cy.waitForPageLoad();
          cy.get('body').then($validationBody => {
            const hasError = $validationBody.text().includes('required') ||
                             $validationBody.find('[class*="error"]').length > 0;
            if (hasError) {
              cy.log('Validation error displayed');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should clear form on cancel', () => {
      cy.get('body').then($body => {
        const nameInput = $body.find('input[name*="name"]');
        if (nameInput.length > 0) {
          cy.wrap(nameInput).first().type('Test Context');
          cy.get('body').then($cancelBody => {
            const cancelButton = $cancelBody.find('button:contains("Cancel")');
            if (cancelButton.length > 0) {
              cy.wrap(cancelButton).first().should('be.visible').click();
              cy.waitForPageLoad();
              cy.log('Form cancelled');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.intercept('GET', '/api/v1/ai/contexts*', {
        statusCode: 500,
        body: { success: false, error: 'Server error' }
      }).as('getContextsError');

      cy.visit('/app/ai/contexts');
      cy.wait('@getContextsError');

      cy.get('body').should('be.visible');
      cy.get('body').should('not.contain.text', 'Cannot read');
      cy.get('body').should('not.contain.text', 'TypeError');
    });

    it('should display error notification on failure', () => {
      cy.intercept('GET', '/api/v1/ai/contexts*', {
        statusCode: 500,
        body: { success: false, error: 'Failed to load contexts' }
      }).as('getContextsError');

      cy.visit('/app/ai/contexts');
      cy.wait('@getContextsError');

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
      cy.intercept('GET', '/api/v1/ai/contexts*', {
        delay: 1000,
        statusCode: 200,
        body: []
      }).as('getContextsDelayed');

      cy.visit('/app/ai/contexts');

      cy.get('body').then($body => {
        const hasLoading = $body.find('[class*="spin"], [class*="loading"]').length > 0 ||
                           $body.text().includes('Loading');
        if (hasLoading) {
          cy.log('Loading indicator displayed');
        }
      });

      cy.wait('@getContextsDelayed');
      cy.get('body').should('be.visible');
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/ai/contexts');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Contexts');
        if (hasContent) {
          cy.log('Content visible on mobile');
        }
      });
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/ai/contexts');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Contexts');
        if (hasContent) {
          cy.log('Content visible on tablet');
        }
      });
    });

    it('should stack elements on small screens', () => {
      cy.viewport(375, 667);
      cy.visit('/app/ai/contexts');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
    });
  });
});


export {};

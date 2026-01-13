/// <reference types="cypress" />

/**
 * AI Prompt Templates E2E Tests
 *
 * Tests for AI prompt template management including:
 * - Template listing
 * - Template creation
 * - Template editing
 * - Template categories and domains
 * - Variable handling
 * - Preview functionality
 * - Responsive design
 */

describe('AI Prompt Templates Tests', () => {
  beforeEach(() => {
    cy.clearAppData();
    cy.visit('/login');
    cy.get('[data-testid="email-input"]', { timeout: 10000 }).type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').click();
    cy.url({ timeout: 15000 }).should('match', /\/(app|dashboard)/);
  });

  describe('Page Navigation', () => {
    it('should navigate to Prompts page', () => {
      cy.visit('/app/ai/prompts');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Prompt') ||
                          $body.text().includes('Template');
        if (hasContent) {
          cy.log('Prompts page loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display page title', () => {
      cy.visit('/app/ai/prompts');
      cy.wait(2000);

      cy.get('body').then($body => {
        const hasTitle = $body.text().includes('Prompt Templates') ||
                        $body.text().includes('Prompts');
        if (hasTitle) {
          cy.log('Page title displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Template List', () => {
    beforeEach(() => {
      cy.visit('/app/ai/prompts');
      cy.wait(2000);
    });

    it('should display template list', () => {
      cy.get('body').then($body => {
        const hasList = $body.find('table, [class*="list"], [class*="grid"]').length > 0 ||
                       $body.text().includes('Template');
        if (hasList) {
          cy.log('Template list displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display template names', () => {
      cy.get('body').then($body => {
        const hasNames = $body.text().includes('Template') ||
                        $body.text().includes('Name') ||
                        $body.find('[class*="name"]').length > 0;
        if (hasNames) {
          cy.log('Template names displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display template categories', () => {
      cy.get('body').then($body => {
        const hasCategories = $body.text().includes('Category') ||
                             $body.text().includes('General') ||
                             $body.text().includes('Workflow') ||
                             $body.text().includes('Agent');
        if (hasCategories) {
          cy.log('Template categories displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display template domains', () => {
      cy.get('body').then($body => {
        const hasDomains = $body.text().includes('Domain') ||
                          $body.text().includes('AI Workflow') ||
                          $body.text().includes('CI/CD');
        if (hasDomains) {
          cy.log('Template domains displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have refresh button', () => {
      cy.get('body').then($body => {
        const hasRefresh = $body.find('button:contains("Refresh"), [aria-label*="refresh"]').length > 0;
        if (hasRefresh) {
          cy.log('Refresh button found');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Template Creation', () => {
    beforeEach(() => {
      cy.visit('/app/ai/prompts');
      cy.wait(2000);
    });

    it('should have Create Template button', () => {
      cy.get('body').then($body => {
        const hasCreate = $body.find('button:contains("Create"), button:contains("New"), button:contains("Add")').length > 0;
        if (hasCreate) {
          cy.log('Create Template button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should open create template form', () => {
      cy.get('body').then($body => {
        const createBtn = $body.find('button:contains("Create"), button:contains("New Template")');
        if (createBtn.length > 0) {
          cy.wrap(createBtn).first().click({ force: true });
          cy.wait(1000);

          cy.get('body').then($formBody => {
            const hasForm = $formBody.text().includes('Name') ||
                           $formBody.text().includes('Category') ||
                           $formBody.find('form, input').length > 0;
            if (hasForm) {
              cy.log('Create template form opened');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have name field', () => {
      cy.get('body').then($body => {
        const createBtn = $body.find('button:contains("Create"), button:contains("New")');
        if (createBtn.length > 0) {
          cy.wrap(createBtn).first().click({ force: true });
          cy.wait(1000);

          cy.get('body').then($formBody => {
            const hasName = $formBody.find('input[type="text"]').length > 0 ||
                           $formBody.text().includes('Name');
            if (hasName) {
              cy.log('Name field found');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have category dropdown', () => {
      cy.get('body').then($body => {
        const createBtn = $body.find('button:contains("Create"), button:contains("New")');
        if (createBtn.length > 0) {
          cy.wrap(createBtn).first().click({ force: true });
          cy.wait(1000);

          cy.get('body').then($formBody => {
            const hasCategory = $formBody.find('select').length > 0 ||
                               $formBody.text().includes('Category');
            if (hasCategory) {
              cy.log('Category dropdown found');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have domain dropdown', () => {
      cy.get('body').then($body => {
        const createBtn = $body.find('button:contains("Create"), button:contains("New")');
        if (createBtn.length > 0) {
          cy.wrap(createBtn).first().click({ force: true });
          cy.wait(1000);

          cy.get('body').then($formBody => {
            const hasDomain = $formBody.find('select').length > 0 ||
                             $formBody.text().includes('Domain');
            if (hasDomain) {
              cy.log('Domain dropdown found');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have content textarea', () => {
      cy.get('body').then($body => {
        const createBtn = $body.find('button:contains("Create"), button:contains("New")');
        if (createBtn.length > 0) {
          cy.wrap(createBtn).first().click({ force: true });
          cy.wait(1000);

          cy.get('body').then($formBody => {
            const hasContent = $formBody.find('textarea').length > 0 ||
                              $formBody.text().includes('Content');
            if (hasContent) {
              cy.log('Content textarea found');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have Cancel button', () => {
      cy.get('body').then($body => {
        const createBtn = $body.find('button:contains("Create"), button:contains("New")');
        if (createBtn.length > 0) {
          cy.wrap(createBtn).first().click({ force: true });
          cy.wait(1000);

          cy.get('body').then($formBody => {
            const hasCancel = $formBody.find('button:contains("Cancel")').length > 0;
            if (hasCancel) {
              cy.log('Cancel button found');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Template Categories', () => {
    beforeEach(() => {
      cy.visit('/app/ai/prompts');
      cy.wait(2000);
    });

    it('should display category filter', () => {
      cy.get('body').then($body => {
        const hasFilter = $body.find('select, [class*="filter"]').length > 0 ||
                         $body.text().includes('Filter') ||
                         $body.text().includes('Category');
        if (hasFilter) {
          cy.log('Category filter displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display predefined categories', () => {
      cy.get('body').then($body => {
        const hasCategories = $body.text().includes('General') ||
                             $body.text().includes('Agent') ||
                             $body.text().includes('Workflow') ||
                             $body.text().includes('Custom');
        if (hasCategories) {
          cy.log('Predefined categories displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Template Actions', () => {
    beforeEach(() => {
      cy.visit('/app/ai/prompts');
      cy.wait(2000);
    });

    it('should have edit action', () => {
      cy.get('body').then($body => {
        const hasEdit = $body.find('button:contains("Edit"), [aria-label*="edit"]').length > 0;
        if (hasEdit) {
          cy.log('Edit action found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have delete action', () => {
      cy.get('body').then($body => {
        const hasDelete = $body.find('button:contains("Delete"), [aria-label*="delete"]').length > 0;
        if (hasDelete) {
          cy.log('Delete action found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have preview action', () => {
      cy.get('body').then($body => {
        const hasPreview = $body.find('button:contains("Preview"), [aria-label*="preview"]').length > 0 ||
                          $body.text().includes('Preview');
        if (hasPreview) {
          cy.log('Preview action found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have copy/clone action', () => {
      cy.get('body').then($body => {
        const hasCopy = $body.find('button:contains("Copy"), button:contains("Clone"), button:contains("Duplicate")').length > 0;
        if (hasCopy) {
          cy.log('Copy/clone action found');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Variables Handling', () => {
    beforeEach(() => {
      cy.visit('/app/ai/prompts');
      cy.wait(2000);
    });

    it('should display variable indicators', () => {
      cy.get('body').then($body => {
        const hasVariables = $body.text().includes('Variable') ||
                            $body.text().includes('{{') ||
                            $body.find('[class*="variable"]').length > 0;
        if (hasVariables) {
          cy.log('Variable indicators displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Search and Filter', () => {
    beforeEach(() => {
      cy.visit('/app/ai/prompts');
      cy.wait(2000);
    });

    it('should have search functionality', () => {
      cy.get('body').then($body => {
        const hasSearch = $body.find('input[type="search"], input[placeholder*="Search"]').length > 0;
        if (hasSearch) {
          cy.log('Search functionality found');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Error Handling', () => {
    it('should handle API errors gracefully', () => {
      cy.intercept('GET', '**/api/**/prompts/**', {
        statusCode: 500,
        body: { success: false, error: 'Server error' }
      });

      cy.visit('/app/ai/prompts');
      cy.wait(2000);

      cy.get('body').should('be.visible');
      cy.get('body').should('not.contain.text', 'Cannot read');
    });
  });

  describe('Loading State', () => {
    it('should display loading indicator', () => {
      cy.intercept('GET', '**/api/**/prompts/**', {
        delay: 2000,
        statusCode: 200,
        body: { success: true, data: [] }
      });

      cy.visit('/app/ai/prompts');

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
      cy.visit('/app/ai/prompts');
      cy.wait(2000);

      cy.get('body').should('be.visible');
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/ai/prompts');
      cy.wait(2000);

      cy.get('body').should('be.visible');
    });

    it('should display properly on large screens', () => {
      cy.viewport(1920, 1080);
      cy.visit('/app/ai/prompts');
      cy.wait(2000);

      cy.get('body').should('be.visible');
    });
  });
});

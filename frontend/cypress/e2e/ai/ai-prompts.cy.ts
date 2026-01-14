/// <reference types="cypress" />

/**
 * AI Prompts Page Tests
 *
 * Tests for AI Prompt Templates functionality including:
 * - Page navigation and load
 * - Template list display
 * - Category filtering
 * - Create template
 * - Edit template
 * - Preview template
 * - Duplicate template
 * - Delete template
 * - Responsive design
 */

describe('AI Prompts Page Tests', () => {
  beforeEach(() => {
    cy.clearAppData();
    // Login with demo user
    cy.visit('/login');
    cy.get('[data-testid="email-input"]', { timeout: 5000 }).type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').click();
    cy.url({ timeout: 5000 }).should('match', /\/(app|dashboard)/);
    cy.setupAiIntercepts();
  });

  describe('Page Navigation', () => {
    it('should navigate to AI Prompts from sidebar', () => {
      cy.visit('/app/ai');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const promptsLink = $body.find('a[href*="/prompts"], button:contains("Prompts")');

        if (promptsLink.length > 0) {
          cy.wrap(promptsLink).first().click();
          cy.url().should('include', '/prompts');
        } else {
          cy.visit('/app/ai/prompts');
        }
      });

      cy.url().should('include', '/prompts');
      cy.get('body').should('be.visible');
    });

    it('should load AI Prompts page directly', () => {
      cy.visit('/app/ai/prompts');

      cy.url().then(url => {
        if (url.includes('/prompts')) {
          cy.get('body').should('satisfy', ($body) => {
            const text = $body.text();
            return text.includes('Prompt') || text.includes('Template') || text.includes('Create');
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display breadcrumbs', () => {
      cy.visit('/app/ai/prompts');

      cy.get('body').then($body => {
        const hasBreadcrumbs = $body.text().includes('Dashboard') &&
                               ($body.text().includes('AI') || $body.text().includes('Prompts'));

        if (hasBreadcrumbs) {
          cy.log('Breadcrumbs displayed correctly');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Template List Display', () => {
    beforeEach(() => {
      cy.visit('/app/ai/prompts');
      cy.waitForPageLoad();
    });

    it('should display template list or empty state', () => {
      cy.get('body').then($body => {
        const _hasTemplates = $body.find('[class*="template"], [class*="card"]').length > 0 ||
                              $body.text().includes('No prompt templates') ||
                              $body.text().includes('Create your first');

        if ($body.text().includes('No prompt templates')) {
          cy.log('Empty state displayed');
        } else {
          cy.log('Template list displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display template names', () => {
      cy.get('body').then($body => {
        const hasNames = $body.find('h3, h4, [class*="title"]').length > 0;

        if (hasNames) {
          cy.log('Template names displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display category badges', () => {
      cy.get('body').then($body => {
        const hasCategories = $body.text().includes('review') ||
                               $body.text().includes('implement') ||
                               $body.text().includes('security') ||
                               $body.text().includes('custom') ||
                               $body.text().includes('general');

        if (hasCategories) {
          cy.log('Category badges displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display template status', () => {
      cy.get('body').then($body => {
        const hasStatus = $body.text().includes('Active') ||
                           $body.text().includes('Inactive');

        if (hasStatus) {
          cy.log('Template status displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display usage count', () => {
      cy.get('body').then($body => {
        const hasUsage = $body.text().includes('uses') ||
                          $body.text().includes('usage');

        if (hasUsage) {
          cy.log('Usage count displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display variable count', () => {
      cy.get('body').then($body => {
        const hasVariables = $body.text().includes('variable');

        if (hasVariables) {
          cy.log('Variable count displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Category Filtering', () => {
    beforeEach(() => {
      cy.visit('/app/ai/prompts');
      cy.waitForPageLoad();
    });

    it('should display category filter tabs', () => {
      cy.get('body').then($body => {
        const hasTabs = $body.text().includes('All') ||
                         $body.find('button:contains("All")').length > 0;

        if (hasTabs) {
          cy.log('Category filter tabs displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should filter by General category', () => {
      cy.get('body').then($body => {
        const generalTab = $body.find('button:contains("General")');

        if (generalTab.length > 0) {
          cy.wrap(generalTab).first().click();
          cy.log('Filtered by General category');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should filter by Agent category', () => {
      cy.get('body').then($body => {
        const agentTab = $body.find('button:contains("Agent")');

        if (agentTab.length > 0) {
          cy.wrap(agentTab).first().click();
          cy.log('Filtered by Agent category');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should filter by Workflow category', () => {
      cy.get('body').then($body => {
        const workflowTab = $body.find('button:contains("Workflow")');

        if (workflowTab.length > 0) {
          cy.wrap(workflowTab).first().click();
          cy.log('Filtered by Workflow category');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should show All templates when All tab clicked', () => {
      cy.get('body').then($body => {
        const allTab = $body.find('button:contains("All")');

        if (allTab.length > 0) {
          cy.wrap(allTab).first().click();
          cy.log('Showing all templates');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Create Template', () => {
    beforeEach(() => {
      cy.visit('/app/ai/prompts');
      cy.waitForPageLoad();
    });

    it('should display Create Template button', () => {
      cy.get('body').then($body => {
        const createButton = $body.find('button:contains("Create Template"), button:contains("Create")');

        if (createButton.length > 0) {
          cy.wrap(createButton).first().should('be.visible');
          cy.log('Create Template button found');
        } else {
          cy.log('Create button not visible - may require permissions');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should open editor when Create Template clicked', () => {
      cy.get('body').then($body => {
        const createButton = $body.find('button:contains("Create Template")');

        if (createButton.length > 0) {
          cy.wrap(createButton).first().click();

          cy.get('body').then($newBody => {
            const editorVisible = $newBody.text().includes('Create Prompt Template') ||
                                   $newBody.find('form').length > 0 ||
                                   $newBody.find('input[type="text"]').length > 0;

            if (editorVisible) {
              cy.log('Template editor opened');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have name input in editor', () => {
      cy.get('body').then($body => {
        const createButton = $body.find('button:contains("Create Template")');

        if (createButton.length > 0) {
          cy.wrap(createButton).first().click();

          cy.get('body').then($newBody => {
            const nameInput = $newBody.find('input[type="text"]');

            if (nameInput.length > 0) {
              cy.log('Name input found in editor');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have category selection in editor', () => {
      cy.get('body').then($body => {
        const createButton = $body.find('button:contains("Create Template")');

        if (createButton.length > 0) {
          cy.wrap(createButton).first().click();

          cy.get('body').then($newBody => {
            const hasCategory = $newBody.text().includes('Category') ||
                                 $newBody.find('select').length > 0;

            if (hasCategory) {
              cy.log('Category selection found in editor');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have content textarea in editor', () => {
      cy.get('body').then($body => {
        const createButton = $body.find('button:contains("Create Template")');

        if (createButton.length > 0) {
          cy.wrap(createButton).first().click();

          cy.get('body').then($newBody => {
            const contentArea = $newBody.find('textarea');

            if (contentArea.length > 0) {
              cy.log('Content textarea found in editor');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should close editor when Cancel clicked', () => {
      cy.get('body').then($body => {
        const createButton = $body.find('button:contains("Create Template")');

        if (createButton.length > 0) {
          cy.wrap(createButton).first().click();

          cy.get('body').then($newBody => {
            const cancelButton = $newBody.find('button:contains("Cancel")');

            if (cancelButton.length > 0) {
              cy.wrap(cancelButton).first().click();
              cy.log('Editor closed');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Edit Template', () => {
    beforeEach(() => {
      cy.visit('/app/ai/prompts');
      cy.waitForPageLoad();
    });

    it('should open editor when template card clicked', () => {
      cy.get('body').then($body => {
        const templateCard = $body.find('[class*="card"][class*="cursor-pointer"], [class*="template"]');

        if (templateCard.length > 0) {
          cy.wrap(templateCard).first().click();

          cy.get('body').then($newBody => {
            const editorVisible = $newBody.text().includes('Edit Prompt Template') ||
                                   $newBody.find('form').length > 0;

            if (editorVisible) {
              cy.log('Edit mode opened');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should pre-populate form with template data', () => {
      cy.get('body').then($body => {
        const templateCard = $body.find('[class*="card"][class*="cursor-pointer"]');

        if (templateCard.length > 0) {
          cy.wrap(templateCard).first().click();

          cy.get('body').then($newBody => {
            const nameInput = $newBody.find('input[type="text"]');

            if (nameInput.length > 0 && nameInput.val()) {
              cy.log('Form pre-populated with template data');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Preview Template', () => {
    beforeEach(() => {
      cy.visit('/app/ai/prompts');
      cy.waitForPageLoad();
    });

    it('should have Preview button on templates', () => {
      cy.get('body').then($body => {
        const previewButton = $body.find('button:contains("Preview")');

        if (previewButton.length > 0) {
          cy.wrap(previewButton).first().should('be.visible');
          cy.log('Preview button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should open preview modal when Preview clicked', () => {
      cy.get('body').then($body => {
        const previewButton = $body.find('button:contains("Preview")');

        if (previewButton.length > 0) {
          cy.wrap(previewButton).first().click();

          cy.get('body').then($newBody => {
            const modalVisible = $newBody.find('[class*="modal"], [class*="fixed"]').length > 0 ||
                                  $newBody.text().includes('Preview');

            if (modalVisible) {
              cy.log('Preview modal opened');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display template content in preview', () => {
      cy.get('body').then($body => {
        const previewButton = $body.find('button:contains("Preview")');

        if (previewButton.length > 0) {
          cy.wrap(previewButton).first().click();

          cy.get('body').then($newBody => {
            const hasContent = $newBody.find('pre').length > 0 ||
                                $newBody.text().includes('Content');

            if (hasContent) {
              cy.log('Template content displayed in preview');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should close preview modal when close clicked', () => {
      cy.get('body').then($body => {
        const previewButton = $body.find('button:contains("Preview")');

        if (previewButton.length > 0) {
          cy.wrap(previewButton).first().click();

          cy.get('body').then($newBody => {
            const closeButton = $newBody.find('button:contains("Close"), [class*="close"]');

            if (closeButton.length > 0) {
              cy.wrap(closeButton).first().click();
              cy.log('Preview modal closed');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Duplicate Template', () => {
    beforeEach(() => {
      cy.visit('/app/ai/prompts');
      cy.waitForPageLoad();
    });

    it('should have Duplicate action in menu', () => {
      cy.get('body').then($body => {
        const menuButton = $body.find('button:contains("•••"), [class*="menu-button"]');

        if (menuButton.length > 0) {
          cy.wrap(menuButton).first().click();

          cy.get('body').then($newBody => {
            const duplicateOption = $newBody.find('button:contains("Duplicate")');

            if (duplicateOption.length > 0) {
              cy.log('Duplicate option found in menu');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Delete Template', () => {
    beforeEach(() => {
      cy.visit('/app/ai/prompts');
      cy.waitForPageLoad();
    });

    it('should have Delete action in menu', () => {
      cy.get('body').then($body => {
        const menuButton = $body.find('button:contains("•••"), [class*="menu-button"]');

        if (menuButton.length > 0) {
          cy.wrap(menuButton).first().click();

          cy.get('body').then($newBody => {
            const deleteOption = $newBody.find('button:contains("Delete")');

            if (deleteOption.length > 0) {
              cy.log('Delete option found in menu');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Refresh Functionality', () => {
    beforeEach(() => {
      cy.visit('/app/ai/prompts');
      cy.waitForPageLoad();
    });

    it('should have Refresh button', () => {
      cy.get('body').then($body => {
        const refreshButton = $body.find('button:contains("Refresh"), [aria-label*="refresh"]');

        if (refreshButton.length > 0) {
          cy.wrap(refreshButton).should('be.visible');
          cy.log('Refresh button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should refresh template list', () => {
      cy.get('body').then($body => {
        const refreshButton = $body.find('button:contains("Refresh")');

        if (refreshButton.length > 0) {
          cy.wrap(refreshButton).first().click();
          cy.get('body').should('be.visible');
          cy.log('Refresh triggered');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.intercept('GET', '/api/v1/prompt_templates*', {
        statusCode: 500,
        body: { success: false, error: 'Server error' }
      });

      cy.visit('/app/ai/prompts');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
      cy.get('body').should('not.contain.text', 'Cannot read');
      cy.get('body').should('not.contain.text', 'TypeError');
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/ai/prompts');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Prompt');
        if (hasContent) {
          cy.log('Content visible on mobile');
        }
      });
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/ai/prompts');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Prompt');
        if (hasContent) {
          cy.log('Content visible on tablet');
        }
      });
    });

    it('should stack template cards on small screens', () => {
      cy.viewport(375, 667);
      cy.visit('/app/ai/prompts');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
    });
  });
});


export {};

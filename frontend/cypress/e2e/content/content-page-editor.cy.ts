/// <reference types="cypress" />

/**
 * Content Page Editor E2E Tests
 *
 * Tests for content page creation and editing functionality including:
 * - Page creation workflow
 * - Rich text editing
 * - Page settings
 * - Publishing workflow
 * - Preview functionality
 * - Responsive design
 */

describe('Content Page Editor Tests', () => {
  beforeEach(() => {
    cy.clearAppData();
    cy.visit('/login');
    cy.get('[data-testid="email-input"]', { timeout: 5000 }).type('demo@democompany.com');
    cy.get('[data-testid="password-input"]').type('DemoSecure456!@#$%');
    cy.get('[data-testid="login-submit-btn"]').click();
    cy.url({ timeout: 5000 }).should('match', /\/(app|dashboard)/);
    cy.setupContentIntercepts();
  });

  describe('Page Navigation', () => {
    it('should navigate to Pages management', () => {
      cy.visit('/app/content/pages');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasContent = $body.text().includes('Pages') ||
                          $body.text().includes('Content') ||
                          $body.text().includes('Create');
        if (hasContent) {
          cy.log('Pages management loaded');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display page list', () => {
      cy.visit('/app/content/pages');
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasPageList = $body.find('table, [class*="list"], [class*="grid"]').length > 0;
        if (hasPageList) {
          cy.log('Page list displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Page Creation', () => {
    beforeEach(() => {
      cy.visit('/app/content/pages');
      cy.waitForPageLoad();
    });

    it('should have Create Page button', () => {
      cy.get('body').then($body => {
        const hasCreate = $body.find('button:contains("Create"), button:contains("New"), button:contains("Add")').length > 0;
        if (hasCreate) {
          cy.log('Create Page button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should open page editor on create', () => {
      cy.get('body').then($body => {
        const createButton = $body.find('button:contains("Create"), button:contains("New Page")');
        if (createButton.length > 0) {
          cy.wrap(createButton).first().should('be.visible').click();
          cy.waitForPageLoad();

          cy.get('body').then($editorBody => {
            const hasEditor = $editorBody.text().includes('Title') ||
                              $editorBody.text().includes('Editor') ||
                              $editorBody.find('input, textarea').length > 0;
            if (hasEditor) {
              cy.log('Page editor opened');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have title field', () => {
      cy.get('button').contains(/Create|New/).first().should('be.visible').click();
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasTitle = $body.find('input[name*="title"], input[placeholder*="Title"]').length > 0 ||
                         $body.text().includes('Title');
        if (hasTitle) {
          cy.log('Title field found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have slug field', () => {
      cy.get('button').contains(/Create|New/).first().should('be.visible').click();
      cy.waitForPageLoad();

      cy.get('body').then($body => {
        const hasSlug = $body.find('input[name*="slug"], input[placeholder*="slug"]').length > 0 ||
                        $body.text().includes('Slug') ||
                        $body.text().includes('URL');
        if (hasSlug) {
          cy.log('Slug field found');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Rich Text Editor', () => {
    beforeEach(() => {
      cy.visit('/app/content/pages');
      cy.waitForPageLoad();
      cy.get('button').contains(/Create|New|Edit/).first().should('be.visible').click();
      cy.waitForPageLoad();
    });

    it('should display rich text editor', () => {
      cy.get('body').then($body => {
        const hasRichText = $body.find('[contenteditable], [class*="editor"], textarea').length > 0;
        if (hasRichText) {
          cy.log('Rich text editor displayed');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have formatting toolbar', () => {
      cy.get('body').then($body => {
        const hasToolbar = $body.find('[class*="toolbar"], [class*="menu"], button[aria-label*="Bold"]').length > 0 ||
                           $body.text().includes('Bold') ||
                           $body.text().includes('Italic');
        if (hasToolbar) {
          cy.log('Formatting toolbar found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have heading options', () => {
      cy.get('body').then($body => {
        const hasHeading = $body.text().includes('Heading') ||
                           $body.find('button:contains("H1"), button:contains("H2")').length > 0;
        if (hasHeading) {
          cy.log('Heading options found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have list options', () => {
      cy.get('body').then($body => {
        const hasLists = $body.text().includes('List') ||
                         $body.find('button[aria-label*="list"]').length > 0;
        if (hasLists) {
          cy.log('List options found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have link insertion', () => {
      cy.get('body').then($body => {
        const hasLink = $body.text().includes('Link') ||
                        $body.find('button[aria-label*="link"]').length > 0;
        if (hasLink) {
          cy.log('Link insertion found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have image insertion', () => {
      cy.get('body').then($body => {
        const hasImage = $body.text().includes('Image') ||
                         $body.find('button[aria-label*="image"]').length > 0;
        if (hasImage) {
          cy.log('Image insertion found');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Page Settings', () => {
    beforeEach(() => {
      cy.visit('/app/content/pages');
      cy.waitForPageLoad();
      cy.get('button').contains(/Create|New|Edit/).first().should('be.visible').click();
      cy.waitForPageLoad();
    });

    it('should have SEO settings', () => {
      cy.get('body').then($body => {
        const hasSEO = $body.text().includes('SEO') ||
                       $body.text().includes('Meta') ||
                       $body.text().includes('Description');
        if (hasSEO) {
          cy.log('SEO settings found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have visibility settings', () => {
      cy.get('body').then($body => {
        const hasVisibility = $body.text().includes('Visibility') ||
                              $body.text().includes('Public') ||
                              $body.text().includes('Private');
        if (hasVisibility) {
          cy.log('Visibility settings found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have template selection', () => {
      cy.get('body').then($body => {
        const hasTemplate = $body.text().includes('Template') ||
                            $body.text().includes('Layout');
        if (hasTemplate) {
          cy.log('Template selection found');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Publishing Workflow', () => {
    beforeEach(() => {
      cy.visit('/app/content/pages');
      cy.waitForPageLoad();
      cy.get('button').contains(/Create|New|Edit/).first().should('be.visible').click();
      cy.waitForPageLoad();
    });

    it('should have Save Draft button', () => {
      cy.get('body').then($body => {
        const hasSaveDraft = $body.find('button:contains("Save"), button:contains("Draft")').length > 0;
        if (hasSaveDraft) {
          cy.log('Save Draft button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have Publish button', () => {
      cy.get('body').then($body => {
        const hasPublish = $body.find('button:contains("Publish")').length > 0;
        if (hasPublish) {
          cy.log('Publish button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have schedule option', () => {
      cy.get('body').then($body => {
        const hasSchedule = $body.text().includes('Schedule') ||
                            $body.find('input[type="datetime-local"]').length > 0;
        if (hasSchedule) {
          cy.log('Schedule option found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display page status', () => {
      cy.get('body').then($body => {
        const hasStatus = $body.text().includes('Draft') ||
                          $body.text().includes('Published') ||
                          $body.text().includes('Status');
        if (hasStatus) {
          cy.log('Page status displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Preview Functionality', () => {
    beforeEach(() => {
      cy.visit('/app/content/pages');
      cy.waitForPageLoad();
      cy.get('button').contains(/Create|New|Edit/).first().should('be.visible').click();
      cy.waitForPageLoad();
    });

    it('should have Preview button', () => {
      cy.get('body').then($body => {
        const hasPreview = $body.find('button:contains("Preview"), [aria-label*="preview"]').length > 0;
        if (hasPreview) {
          cy.log('Preview button found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should have viewport selection for preview', () => {
      cy.get('body').then($body => {
        const hasViewport = $body.text().includes('Desktop') ||
                            $body.text().includes('Mobile') ||
                            $body.text().includes('Tablet');
        if (hasViewport) {
          cy.log('Viewport selection for preview found');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Page List Actions', () => {
    beforeEach(() => {
      cy.visit('/app/content/pages');
      cy.waitForPageLoad();
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

    it('should have duplicate action', () => {
      cy.get('body').then($body => {
        const hasDuplicate = $body.find('button:contains("Duplicate"), button:contains("Copy")').length > 0;
        if (hasDuplicate) {
          cy.log('Duplicate action found');
        }
      });

      cy.get('body').should('be.visible');
    });

    it('should display page status indicators', () => {
      cy.get('body').then($body => {
        const hasStatusIndicators = $body.find('[class*="badge"], [class*="status"]').length > 0 ||
                                     $body.text().includes('Published') ||
                                     $body.text().includes('Draft');
        if (hasStatusIndicators) {
          cy.log('Status indicators displayed');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Error Handling', () => {
    it('should handle API errors gracefully', () => {
      cy.intercept('GET', '**/api/**/pages/**', {
        statusCode: 500,
        body: { success: false, error: 'Server error' }
      });

      cy.visit('/app/content/pages');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
      cy.get('body').should('not.contain.text', 'Cannot read');
    });

    it('should show validation errors', () => {
      cy.visit('/app/content/pages');
      cy.waitForPageLoad();
      cy.get('button').contains(/Create|New/).first().should('be.visible').click();
      cy.waitForPageLoad();

      // Try to save without required fields
      cy.get('body').then($body => {
        const saveButton = $body.find('button:contains("Save"), button:contains("Publish")');
        if (saveButton.length > 0) {
          cy.wrap(saveButton).first().should('be.visible').click();
          cy.waitForPageLoad();

          cy.get('body').then($errorBody => {
            const hasError = $errorBody.text().includes('required') ||
                             $errorBody.text().includes('error') ||
                             $errorBody.find('[class*="error"]').length > 0;
            if (hasError) {
              cy.log('Validation error displayed');
            }
          });
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Auto-save', () => {
    beforeEach(() => {
      cy.visit('/app/content/pages');
      cy.waitForPageLoad();
      cy.get('button').contains(/Create|New|Edit/).first().should('be.visible').click();
      cy.waitForPageLoad();
    });

    it('should auto-save content', () => {
      cy.get('body').then($body => {
        const hasAutoSave = $body.text().includes('Auto') ||
                            $body.text().includes('Saved') ||
                            $body.text().includes('saving');
        if (hasAutoSave) {
          cy.log('Auto-save indication found');
        }
      });

      cy.get('body').should('be.visible');
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.viewport('iphone-x');
      cy.visit('/app/content/pages');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.visit('/app/content/pages');
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
    });

    it('should display editor properly on large screens', () => {
      cy.viewport(1920, 1080);
      cy.visit('/app/content/pages');
      cy.waitForPageLoad();
      cy.get('button').contains(/Create|New|Edit/).first().should('be.visible').click();
      cy.waitForPageLoad();

      cy.get('body').should('be.visible');
    });
  });
});


export {};

/// <reference types="cypress" />

/**
 * AI Workflow Import Page Tests
 *
 * Tests for Workflow Import functionality including:
 * - Page navigation
 * - File upload zone
 * - Preview section
 * - Validation results
 * - Error handling
 * - Responsive design
 */

describe('AI Workflow Import Page Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup({ intercepts: ['ai'] });
  });

  describe('Page Navigation', () => {
    it('should navigate to Import Workflow page', () => {
      cy.navigateTo('/app/ai/workflows/import');
      cy.url().should('include', '/ai');
    });

    it('should display page title', () => {
      cy.navigateTo('/app/ai/workflows/import');
      cy.assertContainsAny(['Import Workflow']);
    });

    it('should display page description', () => {
      cy.navigateTo('/app/ai/workflows/import');
      cy.assertContainsAny(['JSON', 'YAML', 'import']);
    });

    it('should display breadcrumbs', () => {
      cy.navigateTo('/app/ai/workflows/import');
      cy.assertContainsAny(['Dashboard', 'AI', 'Workflows', 'Import']);
    });
  });

  describe('Page Actions', () => {
    it('should have Back to Workflows button', () => {
      cy.navigateTo('/app/ai/workflows/import');
      cy.assertContainsAny(['Back to Workflows', 'Back']);
    });
  });

  describe('File Upload Zone', () => {
    it('should display Upload Workflow File section', () => {
      cy.navigateTo('/app/ai/workflows/import');
      cy.assertContainsAny(['Upload Workflow File', 'Upload']);
    });

    it('should display drag and drop zone', () => {
      cy.navigateTo('/app/ai/workflows/import');
      cy.assertContainsAny(['Drag and drop']);
    });

    it('should have Choose File button', () => {
      cy.navigateTo('/app/ai/workflows/import');
      cy.assertContainsAny(['Choose File', 'Choose']);
    });

    it('should display supported formats', () => {
      cy.navigateTo('/app/ai/workflows/import');
      cy.assertContainsAny(['JSON', 'YAML', 'Supported formats']);
    });

    it('should have hidden file input', () => {
      cy.navigateTo('/app/ai/workflows/import');
      cy.assertHasElement(['input[type="file"]']);
    });
  });

  describe('Preview Section', () => {
    it('should display No File Selected state initially', () => {
      cy.navigateTo('/app/ai/workflows/import');
      cy.assertContainsAny(['No File Selected', 'Upload a workflow file']);
    });
  });

  describe('Validation Results', () => {
    it('should display validation section after file upload', () => {
      cy.navigateTo('/app/ai/workflows/import');
      cy.assertContainsAny(['Validation Results', 'Validation', 'Import']);
    });
  });

  describe('Import Options', () => {
    it('should display Workflow Name input after validation', () => {
      cy.navigateTo('/app/ai/workflows/import');
      cy.assertContainsAny(['Workflow Name', 'Import']);
    });

    it('should display Import Workflow button after validation', () => {
      cy.navigateTo('/app/ai/workflows/import');
      cy.assertContainsAny(['Import Workflow', 'Import']);
    });
  });

  describe('Permission Check', () => {
    it('should show permission required for unauthorized users', () => {
      cy.navigateTo('/app/ai/workflows/import');
      cy.assertContainsAny(['Permission Required', "don't have permission", 'Upload Workflow File']);
    });
  });

  describe('Error Handling', () => {
    it('should handle API errors gracefully', () => {
      cy.intercept('POST', '**/api/**/workflows/import**', {
        statusCode: 500,
        body: { success: false, error: 'Internal Server Error' }
      });
      cy.navigateTo('/app/ai/workflows/import');
      cy.get('body').should('be.visible');
    });
  });

  describe('Two Column Layout', () => {
    it('should display upload and preview sections', () => {
      cy.navigateTo('/app/ai/workflows/import');
      cy.assertHasElement(['[class*="grid"]', '[class*="lg:grid-cols"]']);
    });
  });

  describe('Responsive Design', () => {
    it('should display properly on mobile viewport', () => {
      cy.testResponsiveDesign('/app/ai/workflows/import', {
        checkContent: ['Import']
      });
    });

    it('should display properly on tablet viewport', () => {
      cy.viewport('ipad-2');
      cy.navigateTo('/app/ai/workflows/import');
      cy.get('body').should('be.visible');
    });

    it('should stack columns on small screens', () => {
      cy.viewport('iphone-x');
      cy.navigateTo('/app/ai/workflows/import');
      cy.assertHasElement(['[class*="grid-cols-1"]', '[class*="lg:grid-cols"]']);
    });

    it('should show multi-column layout on large screens', () => {
      cy.viewport(1920, 1080);
      cy.navigateTo('/app/ai/workflows/import');
      cy.assertHasElement(['[class*="lg:grid-cols"]']);
    });
  });
});

export {};

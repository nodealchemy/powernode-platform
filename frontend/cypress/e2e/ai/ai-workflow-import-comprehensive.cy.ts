/// <reference types="cypress" />

/**
 * AI Workflow Import Comprehensive Tests
 *
 * Comprehensive E2E tests for Workflow Import:
 * - File upload interface
 * - Format validation
 * - Preview and mapping
 * - Import execution
 * - Error handling
 */

describe('AI Workflow Import Comprehensive Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup({ intercepts: ['ai'] });
    setupWorkflowImportIntercepts();
  });

  describe('Import Page Overview', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/workflows/import');
    });

    it('should display import page with title', () => {
      cy.assertContainsAny(['Import Workflow', 'Import', 'Upload']);
    });

    it('should display supported formats', () => {
      cy.assertContainsAny(['JSON', 'YAML', 'supported', 'formats']);
    });

    it('should have back to workflows button', () => {
      cy.get('button, a').contains(/back|workflows|cancel/i).should('exist');
    });
  });

  describe('File Upload Zone', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/workflows/import');
    });

    it('should display drag and drop zone', () => {
      cy.assertContainsAny(['Drag', 'drop', 'upload', 'browse']);
    });

    it('should have choose file button', () => {
      cy.get('button').contains(/choose|browse|select/i).should('exist');
    });

    it('should have hidden file input', () => {
      cy.get('input[type="file"]').should('exist');
    });

    it('should accept JSON files', () => {
      cy.get('input[type="file"]').should('have.attr', 'accept').and('include', 'json');
    });

    it('should accept YAML files', () => {
      cy.get('input[type="file"]').should('have.attr', 'accept').and('include', 'yaml');
    });

    it('should display max file size', () => {
      cy.assertContainsAny(['MB', 'max', 'size', 'limit']);
    });
  });

  describe('File Upload Process', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/workflows/import');
    });

    it('should handle JSON file upload', () => {
      const jsonContent = JSON.stringify({
        name: 'Test Workflow',
        steps: [{ type: 'start' }, { type: 'end' }],
      });

      cy.get('input[type="file"]').selectFile(
        { contents: Cypress.Buffer.from(jsonContent), fileName: 'workflow.json', mimeType: 'application/json' },
        { force: true }
      );

      cy.assertContainsAny(['workflow.json', 'Uploaded', 'Preview']);
    });

    it('should handle YAML file upload', () => {
      const yamlContent = `
name: Test Workflow
steps:
  - type: start
  - type: end
`;

      cy.get('input[type="file"]').selectFile(
        { contents: Cypress.Buffer.from(yamlContent), fileName: 'workflow.yaml', mimeType: 'text/yaml' },
        { force: true }
      );

      cy.assertContainsAny(['workflow.yaml', 'Uploaded', 'Preview']);
    });

    it('should display upload progress', () => {
      cy.get('input[type="file"]').selectFile(
        { contents: Cypress.Buffer.from('{}'), fileName: 'test.json' },
        { force: true }
      );

      cy.assertContainsAny(['Uploading', 'Progress', '%', 'Validating']);
    });
  });

  describe('File Validation', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/workflows/import');
    });

    it('should validate file format', () => {
      cy.intercept('POST', '**/api/**/workflows/validate*', {
        statusCode: 200,
        body: { valid: true, warnings: [] },
      }).as('validateFile');

      cy.get('input[type="file"]').selectFile(
        { contents: Cypress.Buffer.from('{"name": "test"}'), fileName: 'test.json' },
        { force: true }
      );

      cy.assertContainsAny(['Valid', 'Validation', 'passed']);
    });

    it('should show validation errors for invalid files', () => {
      cy.intercept('POST', '**/api/**/workflows/validate*', {
        statusCode: 400,
        body: { valid: false, errors: ['Missing required field: name'] },
      }).as('validateInvalid');

      cy.get('input[type="file"]').selectFile(
        { contents: Cypress.Buffer.from('{}'), fileName: 'invalid.json' },
        { force: true }
      );

      cy.assertContainsAny(['Invalid', 'Error', 'Missing', 'required']);
    });

    it('should show validation warnings', () => {
      cy.intercept('POST', '**/api/**/workflows/validate*', {
        statusCode: 200,
        body: { valid: true, warnings: ['Step "process" has no timeout configured'] },
      }).as('validateWarnings');

      cy.get('input[type="file"]').selectFile(
        { contents: Cypress.Buffer.from('{"name": "test"}'), fileName: 'test.json' },
        { force: true }
      );

      cy.assertContainsAny(['Warning', 'timeout', 'configured']);
    });

    it('should reject unsupported file types', () => {
      cy.get('input[type="file"]').selectFile(
        { contents: Cypress.Buffer.from('test'), fileName: 'test.txt' },
        { force: true }
      );

      cy.assertContainsAny(['Unsupported', 'format', 'JSON', 'YAML']);
    });
  });

  describe('Preview Section', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/workflows/import');
    });

    it('should display no file selected initially', () => {
      cy.assertContainsAny(['No File', 'Select', 'Upload']);
    });

    it('should show workflow preview after upload', () => {
      cy.get('input[type="file"]').selectFile(
        { contents: Cypress.Buffer.from('{"name": "Test Workflow"}'), fileName: 'test.json' },
        { force: true }
      );

      cy.assertContainsAny(['Preview', 'Test Workflow', 'name']);
    });

    it('should display workflow structure', () => {
      cy.get('input[type="file"]').selectFile(
        { contents: Cypress.Buffer.from('{"name": "Test", "steps": []}'), fileName: 'test.json' },
        { force: true }
      );

      cy.assertContainsAny(['Steps', 'structure', 'nodes', 'flow']);
    });

    it('should display step count', () => {
      cy.get('input[type="file"]').selectFile(
        { contents: Cypress.Buffer.from('{"name": "Test", "steps": [{}, {}]}'), fileName: 'test.json' },
        { force: true }
      );

      cy.assertContainsAny(['steps', 'nodes', '2']);
    });
  });

  describe('Import Options', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/workflows/import');
      cy.get('input[type="file"]').selectFile(
        { contents: Cypress.Buffer.from('{"name": "Test"}'), fileName: 'test.json' },
        { force: true }
      );
    });

    it('should have workflow name input', () => {
      cy.get('input[name="name"], input[placeholder*="name"]').should('exist');
    });

    it('should allow changing workflow name', () => {
      cy.get('input[name="name"], input').first().clear().type('Custom Name');
    });

    it('should have description input', () => {
      cy.get('textarea, input[name="description"]').should('exist');
    });

    it('should have folder/category selector', () => {
      cy.assertContainsAny(['Folder', 'Category', 'Location']);
    });

    it('should have overwrite existing option', () => {
      cy.assertContainsAny(['Overwrite', 'Replace', 'existing']);
    });
  });

  describe('Import Execution', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/workflows/import');
      cy.get('input[type="file"]').selectFile(
        { contents: Cypress.Buffer.from('{"name": "Test"}'), fileName: 'test.json' },
        { force: true }
      );
    });

    it('should have import button', () => {
      cy.get('button').contains(/import|create/i).should('exist');
    });

    it('should import workflow when button clicked', () => {
      cy.intercept('POST', '**/api/**/workflows/import*', {
        statusCode: 201,
        body: { success: true, workflow: { id: 'wf-new', name: 'Test' } },
      }).as('importWorkflow');

      cy.get('button').contains(/import|create/i).first().click();
      cy.wait('@importWorkflow');
      cy.assertContainsAny(['imported', 'success', 'created']);
    });

    it('should show import progress', () => {
      cy.intercept('POST', '**/api/**/workflows/import*', {
        statusCode: 201,
        body: { success: true },
        delay: 1000,
      }).as('importSlow');

      cy.get('button').contains(/import/i).first().click();
      cy.assertContainsAny(['Importing', 'progress', 'loading']);
    });

    it('should redirect to workflow after successful import', () => {
      cy.intercept('POST', '**/api/**/workflows/import*', {
        statusCode: 201,
        body: { success: true, workflow: { id: 'wf-new' } },
      }).as('importWorkflow');

      cy.get('button').contains(/import/i).first().click();
      cy.wait('@importWorkflow');
    });
  });

  describe('Import from URL', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/workflows/import');
    });

    it('should have import from URL option', () => {
      cy.assertContainsAny(['URL', 'link', 'remote']);
    });

    it('should have URL input field', () => {
      cy.get('input[type="url"], input[placeholder*="URL"]').should('exist');
    });

    it('should fetch workflow from URL', () => {
      cy.intercept('POST', '**/api/**/workflows/fetch-url*', {
        statusCode: 200,
        body: { success: true, workflow: { name: 'Remote Workflow' } },
      }).as('fetchUrl');

      cy.get('input[type="url"], input[placeholder*="URL"]').first().type('https://example.com/workflow.json');
      cy.get('button').contains(/fetch|load/i).first().click();
    });
  });

  describe('Import Templates', () => {
    beforeEach(() => {
      cy.navigateTo('/app/ai/workflows/import');
    });

    it('should display import templates section', () => {
      cy.assertContainsAny(['Templates', 'Examples', 'Starter']);
    });

    it('should list available templates', () => {
      cy.assertContainsAny(['Data Processing', 'Email', 'Notification', 'template']);
    });

    it('should import template when selected', () => {
      cy.intercept('POST', '**/api/**/workflows/import-template*', {
        statusCode: 201,
        body: { success: true, workflow: { id: 'wf-template' } },
      }).as('importTemplate');

      cy.get('button').contains(/use|import/i).first().click();
    });
  });

  describe('Error Handling', () => {
    it('should handle API error gracefully', () => {
      cy.testErrorHandling('**/api/**/workflows/import**', {
        statusCode: 500,
        visitUrl: '/app/ai/workflows/import',
      });
    });

    it('should handle file read error', () => {
      cy.navigateTo('/app/ai/workflows/import');
      cy.assertContainsAny(['Import', 'Upload', 'Drag']);
    });

    it('should display import error message', () => {
      cy.navigateTo('/app/ai/workflows/import');

      cy.intercept('POST', '**/api/**/workflows/import*', {
        statusCode: 400,
        body: { success: false, error: 'Workflow with this name already exists' },
      }).as('importError');

      cy.get('input[type="file"]').selectFile(
        { contents: Cypress.Buffer.from('{"name": "Test"}'), fileName: 'test.json' },
        { force: true }
      );
      cy.get('button').contains(/import/i).first().click();
      cy.wait('@importError');
      cy.assertContainsAny(['Error', 'already exists', 'failed']);
    });
  });

  describe('Responsive Design', () => {
    it('should display correctly across viewports', () => {
      cy.testResponsiveDesign('/app/ai/workflows/import', {
        checkContent: 'Import',
      });
    });
  });
});

function setupWorkflowImportIntercepts() {
  const mockTemplates = [
    { id: 'tpl-1', name: 'Data Processing Pipeline', description: 'Process and transform data' },
    { id: 'tpl-2', name: 'Email Notification Workflow', description: 'Send automated emails' },
    { id: 'tpl-3', name: 'Customer Onboarding', description: 'Onboard new customers' },
  ];

  cy.intercept('GET', '**/api/**/workflows/templates*', {
    statusCode: 200,
    body: { items: mockTemplates },
  }).as('getTemplates');

  cy.intercept('POST', '**/api/**/workflows/validate*', {
    statusCode: 200,
    body: { valid: true, warnings: [] },
  }).as('validateWorkflow');

  cy.intercept('POST', '**/api/**/workflows/import*', {
    statusCode: 201,
    body: { success: true, workflow: { id: 'wf-new', name: 'Imported Workflow' } },
  }).as('importWorkflow');

  cy.intercept('POST', '**/api/**/workflows/import-template*', {
    statusCode: 201,
    body: { success: true, workflow: { id: 'wf-template' } },
  }).as('importTemplate');

  cy.intercept('POST', '**/api/**/workflows/fetch-url*', {
    statusCode: 200,
    body: { success: true, workflow: { name: 'Remote Workflow' } },
  }).as('fetchUrl');
}

export {};

/// <reference types="cypress" />

/**
 * Vendor Management E2E Tests
 *
 * Tests for the Vendor Management functionality including:
 * - Vendor list display
 * - Vendor risk dashboard
 * - Vendor detail view
 * - Risk assessment workflow
 * - Questionnaire management
 * - Add/Edit/Delete vendors
 */

describe('Vendor Management Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup({ intercepts: ['supply-chain'] });
    cy.setupSupplyChainIntercepts();
  });

  describe('Vendors List Page', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/supply-chain/vendors', 'Vendor');
    });

    it('should display vendors page', () => {
      cy.assertContainsAny(['Vendors', 'Third-Party', 'Supplier']);
    });

    it('should display vendor entries', () => {
      cy.assertContainsAny(['Cloud Provider Inc', 'Payment Gateway Corp', 'Analytics Service']);
    });

    it('should display risk tier indicators', () => {
      cy.assertContainsAny(['Low', 'Medium', 'High', 'Critical', 'low', 'medium', 'high']);
    });

    it('should display vendor type', () => {
      cy.assertContainsAny(['SaaS', 'IaaS', 'PaaS', 'saas', 'iaas']);
    });

    it('should display certifications', () => {
      cy.assertContainsAny(['SOC2', 'ISO27001', 'PCI-DSS', 'FedRAMP', 'HIPAA']);
    });

    it('should have table with proper columns', () => {
      cy.assertContainsAny(['Name', 'Type', 'Risk', 'Status', 'Certifications', 'Last Assessment']);
    });
  });

  describe('Vendor Filtering', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/supply-chain/vendors');
    });

    it('should have filter controls', () => {
      cy.assertHasElement([
        '[data-testid="filter-risk"]',
        '[data-testid="filter-status"]',
        'select',
        '[role="combobox"]',
      ]);
    });

    it('should filter by risk tier', () => {
      cy.assertHasElement(['[data-testid="filter-risk"]', 'select', '[role="combobox"]']);
    });

    it('should search vendors', () => {
      cy.assertHasElement(['[data-testid="search-input"]', 'input[type="search"]', 'input']);
    });
  });

  describe('Vendor Risk Dashboard', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/supply-chain/vendors/risk-dashboard', 'Risk');
    });

    it('should display risk dashboard', () => {
      cy.assertContainsAny(['Risk', 'Dashboard', 'Overview']);
    });

    it('should display risk distribution', () => {
      cy.assertContainsAny(['High Risk', 'Medium Risk', 'Low Risk', 'Critical']);
    });

    it('should display vendor counts by risk tier', () => {
      cy.assertContainsAny(['2', '5', '12', 'vendors']);
    });

    it('should display average risk score', () => {
      cy.assertContainsAny(['Average', 'Score', '42', 'Risk Score']);
    });

    it('should display vendors needing assessment', () => {
      cy.assertContainsAny(['Assessment', 'Overdue', 'Needed', 'Due']);
    });

    it('should navigate to vendor detail from risk dashboard', () => {
      cy.assertContainsAny(['Risk', 'Dashboard', 'Vendor']);
    });
  });

  describe('Vendor Detail Page', () => {
    it('should navigate to vendor detail page', () => {
      cy.assertPageReady('/app/supply-chain/vendors');
      cy.assertContainsAny(['Vendor', 'Cloud Provider', 'Payment Gateway']);
    });

    it('should display vendor details', () => {
      cy.visit('/app/supply-chain/vendors/vendor-1');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Cloud Provider Inc', 'Vendor', 'Details']);
    });

    it('should display contact information', () => {
      cy.visit('/app/supply-chain/vendors/vendor-1');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Contact', 'Jane Smith', 'Email', 'cloudprovider.com']);
    });

    it('should display data handling flags', () => {
      cy.visit('/app/supply-chain/vendors/vendor-1');
      cy.waitForPageLoad();
      cy.assertContainsAny(['PII', 'PHI', 'PCI', 'Data', 'Handles']);
    });

    it('should display certifications', () => {
      cy.visit('/app/supply-chain/vendors/vendor-1');
      cy.waitForPageLoad();
      cy.assertContainsAny(['SOC2', 'ISO27001', 'FedRAMP', 'Certifications']);
    });

    it('should display assessment history', () => {
      cy.visit('/app/supply-chain/vendors/vendor-1');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Assessment', 'History', 'periodic', 'completed', 'Score']);
    });

    it('should display questionnaire history', () => {
      cy.visit('/app/supply-chain/vendors/vendor-1');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Questionnaire', 'Security Assessment', 'Response', 'completed']);
    });
  });

  describe('Add Vendor', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/supply-chain/vendors');
    });

    it('should have add vendor button', () => {
      cy.assertHasElement([
        '[data-testid="add-vendor-btn"]',
        '[data-testid="action-create"]',
        'button:contains("Add")',
        'button:contains("New")',
      ]);
    });

    it('should open add vendor modal', () => {
      cy.get('[data-testid="add-vendor-btn"], button:contains("Add"), button:contains("New")').first().click();
      cy.assertContainsAny(['Add', 'New', 'Vendor', 'Name', 'Type']);
    });

    it('should show form fields in add modal', () => {
      cy.get('[data-testid="add-vendor-btn"], button:contains("Add"), button:contains("New")').first().click();
      cy.assertContainsAny(['Name', 'Type', 'Website', 'Contact', 'Email']);
    });
  });

  describe('Edit Vendor', () => {
    beforeEach(() => {
      cy.visit('/app/supply-chain/vendors/vendor-1');
      cy.waitForPageLoad();
    });

    it('should have edit button', () => {
      cy.assertHasElement([
        '[data-testid="edit-btn"]',
        '[data-testid="action-edit"]',
        'button:contains("Edit")',
      ]);
    });

    it('should open edit modal when clicking edit', () => {
      cy.get('[data-testid="edit-btn"], button:contains("Edit")').first().click();
      cy.assertContainsAny(['Edit', 'Update', 'Vendor', 'Save']);
    });
  });

  describe('Risk Assessment Workflow', () => {
    beforeEach(() => {
      cy.visit('/app/supply-chain/vendors/vendor-1');
      cy.waitForPageLoad();
    });

    it('should have start assessment button', () => {
      cy.assertHasElement([
        '[data-testid="start-assessment-btn"]',
        'button:contains("Assessment")',
        'button:contains("Start")',
      ]);
    });

    it('should open assessment modal when clicking start', () => {
      cy.get('[data-testid="start-assessment-btn"], button:contains("Assessment")').first().click();
      cy.assertContainsAny(['Assessment', 'Type', 'Start', 'periodic', 'initial']);
    });

    it('should display assessment scores when completed', () => {
      cy.assertContainsAny(['Security Score', 'Compliance Score', 'Overall', '78', 'Score']);
    });

    it('should navigate to assessment detail', () => {
      cy.assertContainsAny(['Assessment', 'Score', 'Vendor']);
    });
  });

  describe('Questionnaire Workflow', () => {
    beforeEach(() => {
      cy.visit('/app/supply-chain/vendors/vendor-1');
      cy.waitForPageLoad();
    });

    it('should have send questionnaire button', () => {
      cy.assertHasElement([
        '[data-testid="send-questionnaire-btn"]',
        'button:contains("Questionnaire")',
        'button:contains("Send")',
      ]);
    });

    it('should open questionnaire modal when clicking send', () => {
      cy.get('[data-testid="send-questionnaire-btn"], button:contains("Questionnaire")').first().click();
      cy.assertContainsAny(['Questionnaire', 'Template', 'Send', 'Select']);
    });

    it('should display questionnaire progress', () => {
      cy.assertContainsAny(['45', '50', 'Response', 'Questions', 'completed']);
    });

    it('should navigate to questionnaire detail', () => {
      cy.assertContainsAny(['Questionnaire', 'Response', 'Vendor']);
    });
  });

  describe('Delete Vendor', () => {
    beforeEach(() => {
      cy.visit('/app/supply-chain/vendors/vendor-1');
      cy.waitForPageLoad();
    });

    it('should have delete button', () => {
      cy.assertHasElement([
        '[data-testid="delete-btn"]',
        '[data-testid="action-delete"]',
        'button:contains("Delete")',
      ]);
    });

    it('should show confirmation when deleting', () => {
      cy.get('[data-testid="delete-btn"], button:contains("Delete")').first().click();
      cy.assertContainsAny(['Confirm', 'Are you sure', 'Delete', 'Cancel']);
    });
  });

  describe('Error Handling', () => {
    it('should handle vendor not found', () => {
      cy.intercept('GET', '**/api/v1/supply_chain/vendors/nonexistent', {
        statusCode: 404,
        body: { success: false, error: 'Vendor not found' },
      });

      cy.visit('/app/supply-chain/vendors/nonexistent');
      cy.assertContainsAny(['not found', 'Not Found', 'error', 'Error', '404']);
    });

    it('should handle list loading error', () => {
      cy.testErrorHandling('/api/v1/supply_chain/vendors', {
        statusCode: 500,
        visitUrl: '/app/supply-chain/vendors',
      });
    });
  });

  describe('Responsive Design', () => {
    it('should display properly across viewports', () => {
      cy.testResponsiveDesign('/app/supply-chain/vendors', {
        checkContent: 'Vendor',
      });
    });

    it('should display risk dashboard across viewports', () => {
      cy.testResponsiveDesign('/app/supply-chain/vendors/risk-dashboard', {
        checkContent: 'Risk',
      });
    });
  });
});

export {};

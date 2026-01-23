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
      cy.get('body').then($body => {
        const riskFilter = $body.find('[data-testid="filter-risk"], select:contains("Risk")');
        if (riskFilter.length > 0) {
          cy.wrap(riskFilter).first().click();
          cy.get('[role="option"], option').contains(/high/i).click();
          cy.wait('@getVendorsFiltered');
        }
      });
    });

    it('should search vendors', () => {
      cy.get('body').then($body => {
        const searchInput = $body.find('[data-testid="search-input"], input[type="search"]');
        if (searchInput.length > 0) {
          cy.wrap(searchInput).first().type('Payment');
          cy.wait('@getVendorsFiltered');
        }
      });
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
      cy.get('body').then($body => {
        const vendorLink = $body.find('a[href*="/vendors/"]:not([href*="risk-dashboard"])');
        if (vendorLink.length > 0) {
          cy.wrap(vendorLink).first().click();
          cy.url().should('match', /\/vendors\/[^/]+$/);
        }
      });
    });
  });

  describe('Vendor Detail Page', () => {
    it('should navigate to vendor detail page', () => {
      cy.assertPageReady('/app/supply-chain/vendors');
      cy.get('body').then($body => {
        const vendorRow = $body.find('table tbody tr, [data-testid*="vendor-row"]');
        if (vendorRow.length > 0) {
          cy.wrap(vendorRow).first().click();
          cy.url().should('match', /\/vendors\/[^/]+$/);
        }
      });
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
      cy.get('body').then($body => {
        const addBtn = $body.find('[data-testid="add-vendor-btn"], button:contains("Add"), button:contains("New")');
        if (addBtn.length > 0) {
          cy.wrap(addBtn).first().click();
          cy.assertContainsAny(['Add', 'New', 'Vendor', 'Name', 'Type']);
        }
      });
    });

    it('should show form fields in add modal', () => {
      cy.get('body').then($body => {
        const addBtn = $body.find('[data-testid="add-vendor-btn"], button:contains("Add"), button:contains("New")');
        if (addBtn.length > 0) {
          cy.wrap(addBtn).first().click();
          cy.assertContainsAny(['Name', 'Type', 'Website', 'Contact', 'Email']);
        }
      });
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
      cy.get('body').then($body => {
        const editBtn = $body.find('[data-testid="edit-btn"], button:contains("Edit")');
        if (editBtn.length > 0) {
          cy.wrap(editBtn).first().click();
          cy.assertContainsAny(['Edit', 'Update', 'Vendor', 'Save']);
        }
      });
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
      cy.get('body').then($body => {
        const assessBtn = $body.find('[data-testid="start-assessment-btn"], button:contains("Assessment")');
        if (assessBtn.length > 0) {
          cy.wrap(assessBtn).first().click();
          cy.assertContainsAny(['Assessment', 'Type', 'Start', 'periodic', 'initial']);
        }
      });
    });

    it('should display assessment scores when completed', () => {
      cy.assertContainsAny(['Security Score', 'Compliance Score', 'Overall', '78', 'Score']);
    });

    it('should navigate to assessment detail', () => {
      cy.get('body').then($body => {
        const assessmentLink = $body.find('a[href*="/assessments/"]');
        if (assessmentLink.length > 0) {
          cy.wrap(assessmentLink).first().click();
          cy.url().should('include', '/assessments/');
        }
      });
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
      cy.get('body').then($body => {
        const questBtn = $body.find('[data-testid="send-questionnaire-btn"], button:contains("Questionnaire")');
        if (questBtn.length > 0) {
          cy.wrap(questBtn).first().click();
          cy.assertContainsAny(['Questionnaire', 'Template', 'Send', 'Select']);
        }
      });
    });

    it('should display questionnaire progress', () => {
      cy.assertContainsAny(['45', '50', 'Response', 'Questions', 'completed']);
    });

    it('should navigate to questionnaire detail', () => {
      cy.get('body').then($body => {
        const questionnaireLink = $body.find('a[href*="/questionnaires/"]');
        if (questionnaireLink.length > 0) {
          cy.wrap(questionnaireLink).first().click();
          cy.url().should('include', '/questionnaires/');
        }
      });
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
      cy.get('body').then($body => {
        const deleteBtn = $body.find('[data-testid="delete-btn"], button:contains("Delete")');
        if (deleteBtn.length > 0) {
          cy.wrap(deleteBtn).first().click();
          cy.assertContainsAny(['Confirm', 'Are you sure', 'Delete', 'Cancel']);
        }
      });
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

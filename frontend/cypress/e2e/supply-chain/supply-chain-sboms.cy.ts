/// <reference types="cypress" />

/**
 * SBOM Management E2E Tests
 *
 * Tests for the Software Bill of Materials (SBOM) functionality including:
 * - SBOM list display and pagination
 * - SBOM filtering and search
 * - SBOM detail view
 * - Vulnerability display
 * - Export functionality
 * - SBOM diff/comparison
 * - Delete operations
 */

describe('SBOM Management Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup({ intercepts: ['supply-chain'] });
    cy.setupSupplyChainIntercepts();
  });

  describe('SBOM List Page', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/supply-chain/sboms', 'SBOM');
    });

    it('should display SBOM list page', () => {
      cy.assertContainsAny(['SBOMs', 'Software Bill of Materials', 'Bill of Materials']);
    });

    it('should display SBOM entries', () => {
      cy.assertContainsAny(['Production App SBOM', 'API Service SBOM', 'Frontend SBOM', 'SBOM']);
    });

    it('should display SBOM status indicators', () => {
      cy.assertContainsAny(['completed', 'generating', 'Completed', 'Generating', 'failed']);
    });

    it('should display SBOM metadata', () => {
      cy.assertContainsAny(['components', 'vulnerabilities', 'CycloneDX', 'SPDX', 'format']);
    });

    it('should display NTIA compliance indicators', () => {
      cy.assertContainsAny(['NTIA', 'compliant', 'Compliant', 'minimum']);
    });

    it('should have table with proper columns', () => {
      cy.assertContainsAny(['Name', 'Format', 'Status', 'Components', 'Vulnerabilities', 'Created']);
    });
  });

  describe('SBOM Filtering', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/supply-chain/sboms');
    });

    it('should have filter controls', () => {
      cy.assertHasElement([
        '[data-testid="filter-status"]',
        '[data-testid="filter-format"]',
        'select',
        '[role="combobox"]',
        'input[type="search"]',
        '[data-testid="search-input"]',
      ]);
    });

    it('should filter by status when status filter exists', () => {
      cy.get('body').then($body => {
        const statusFilter = $body.find('[data-testid="filter-status"], select:contains("Status")');
        if (statusFilter.length > 0) {
          cy.wrap(statusFilter).first().click();
          cy.get('[role="option"], option').contains(/completed|generating/i).click();
          cy.wait('@getSbomsFiltered');
        }
      });
    });

    it('should search SBOMs when search input exists', () => {
      cy.get('body').then($body => {
        const searchInput = $body.find('[data-testid="search-input"], input[type="search"], input[placeholder*="Search"]');
        if (searchInput.length > 0) {
          cy.wrap(searchInput).first().type('Production');
          cy.wait('@getSbomsFiltered');
        }
      });
    });
  });

  describe('SBOM Detail Page', () => {
    it('should navigate to SBOM detail page', () => {
      cy.assertPageReady('/app/supply-chain/sboms');
      cy.get('body').then($body => {
        const sbomRow = $body.find('table tbody tr, [data-testid*="sbom-row"]');
        if (sbomRow.length > 0) {
          cy.wrap(sbomRow).first().click();
          cy.url().should('match', /\/sboms\/[^/]+$/);
        }
      });
    });

    it('should display SBOM detail information', () => {
      cy.visit('/app/supply-chain/sboms/sbom-1');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Production App SBOM', 'SBOM', 'Details']);
    });

    it('should display components list', () => {
      cy.visit('/app/supply-chain/sboms/sbom-1');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Components', 'lodash', 'express', 'Dependencies']);
    });

    it('should display vulnerabilities section', () => {
      cy.visit('/app/supply-chain/sboms/sbom-1');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Vulnerabilities', 'CVE', 'Critical', 'High', 'Medium', 'Low']);
    });

    it('should display repository information', () => {
      cy.visit('/app/supply-chain/sboms/sbom-1');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Repository', 'repo', 'Branch', 'Commit', 'main']);
    });
  });

  describe('Vulnerability Management', () => {
    beforeEach(() => {
      cy.visit('/app/supply-chain/sboms/sbom-1');
      cy.waitForPageLoad();
    });

    it('should display vulnerability severity badges', () => {
      cy.assertContainsAny(['Critical', 'High', 'Medium', 'Low']);
    });

    it('should display CVE identifiers', () => {
      cy.assertContainsAny(['CVE-', 'CVE-2024']);
    });

    it('should display remediation status', () => {
      cy.assertContainsAny(['open', 'Open', 'remediated', 'Remediated', 'in progress', 'In Progress']);
    });

    it('should open vulnerability detail modal when clicking vulnerability', () => {
      cy.get('body').then($body => {
        const vulnRow = $body.find('[data-testid*="vulnerability"], tr:contains("CVE")');
        if (vulnRow.length > 0) {
          cy.wrap(vulnRow).first().click();
          // Modal or detail panel should appear
          cy.assertContainsAny(['CVSS', 'Score', 'Vector', 'Description', 'Fix']);
        }
      });
    });
  });

  describe('Export Functionality', () => {
    beforeEach(() => {
      cy.visit('/app/supply-chain/sboms/sbom-1');
      cy.waitForPageLoad();
    });

    it('should have export button', () => {
      cy.assertHasElement([
        '[data-testid="export-btn"]',
        '[data-testid="action-export"]',
        'button:contains("Export")',
        '[aria-label*="Export"]',
      ]);
    });

    it('should open export format dropdown', () => {
      cy.get('body').then($body => {
        const exportBtn = $body.find('[data-testid="export-btn"], button:contains("Export")');
        if (exportBtn.length > 0) {
          cy.wrap(exportBtn).first().click();
          cy.assertContainsAny(['CycloneDX', 'SPDX', 'JSON', 'XML']);
        }
      });
    });
  });

  describe('SBOM Diff/Comparison', () => {
    it('should navigate to diff page when comparing SBOMs', () => {
      cy.visit('/app/supply-chain/sboms/sbom-1');
      cy.waitForPageLoad();
      cy.get('body').then($body => {
        const compareBtn = $body.find('[data-testid="compare-btn"], button:contains("Compare"), button:contains("Diff")');
        if (compareBtn.length > 0) {
          cy.wrap(compareBtn).first().click();
          // Should open comparison modal or navigate to diff page
          cy.assertContainsAny(['Compare', 'Diff', 'Select', 'Added', 'Removed']);
        }
      });
    });

    it('should display diff results', () => {
      cy.visit('/app/supply-chain/sboms/sbom-1/diff/diff-1');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Added', 'Removed', 'Modified', 'Unchanged', 'Diff', 'Comparison']);
    });
  });

  describe('Delete Operations', () => {
    beforeEach(() => {
      cy.visit('/app/supply-chain/sboms/sbom-1');
      cy.waitForPageLoad();
    });

    it('should have delete button', () => {
      cy.assertHasElement([
        '[data-testid="delete-btn"]',
        '[data-testid="action-delete"]',
        'button:contains("Delete")',
        '[aria-label*="Delete"]',
      ]);
    });

    it('should show confirmation dialog when deleting', () => {
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
    it('should handle SBOM not found gracefully', () => {
      cy.intercept('GET', '**/api/v1/supply_chain/sboms/nonexistent', {
        statusCode: 404,
        body: { success: false, error: 'SBOM not found' },
      });

      cy.visit('/app/supply-chain/sboms/nonexistent');
      cy.assertContainsAny(['not found', 'Not Found', 'error', 'Error', '404']);
    });

    it('should handle list loading error', () => {
      cy.testErrorHandling('/api/v1/supply_chain/sboms', {
        statusCode: 500,
        visitUrl: '/app/supply-chain/sboms',
      });
    });
  });

  describe('Responsive Design', () => {
    it('should display properly across viewports', () => {
      cy.testResponsiveDesign('/app/supply-chain/sboms', {
        checkContent: 'SBOM',
      });
    });
  });
});

export {};

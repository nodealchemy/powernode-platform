/// <reference types="cypress" />

/**
 * License Compliance E2E Tests
 *
 * Tests for the License Compliance functionality including:
 * - License policies list
 * - Policy creation/editing
 * - License violations list
 * - Violation resolution
 * - Exception granting
 */

describe('License Compliance Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup({ intercepts: ['supply-chain'] });
    cy.setupSupplyChainIntercepts();
  });

  describe('License Policies List Page', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/supply-chain/licenses/policies', 'Policy');
    });

    it('should display license policies page', () => {
      cy.assertContainsAny(['License', 'Policies', 'Compliance']);
    });

    it('should display policy entries', () => {
      cy.assertContainsAny(['Production License Policy', 'Development Policy']);
    });

    it('should display policy type', () => {
      cy.assertContainsAny(['allowlist', 'Allowlist', 'blocklist', 'Blocklist']);
    });

    it('should display enforcement level', () => {
      cy.assertContainsAny(['block', 'Block', 'warn', 'Warn', 'monitor', 'Monitor']);
    });

    it('should display active status', () => {
      cy.assertContainsAny(['Active', 'Inactive', 'active', 'inactive', 'Enabled', 'Disabled']);
    });

    it('should have table with proper columns', () => {
      cy.assertContainsAny(['Name', 'Type', 'Enforcement', 'Status', 'Created']);
    });
  });

  describe('Create License Policy', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/supply-chain/licenses/policies');
    });

    it('should have create policy button', () => {
      cy.assertHasElement([
        '[data-testid="create-policy-btn"]',
        '[data-testid="action-create"]',
        'button:contains("Create")',
        'button:contains("New")',
        'a[href*="/policies/new"]',
      ]);
    });

    it('should navigate to policy form page', () => {
      cy.get('[data-testid="create-policy-btn"], button:contains("Create"), a[href*="/policies/new"]').first().click();
      cy.url().should('include', '/policies/new');
    });

    it('should display policy form fields', () => {
      cy.visit('/app/supply-chain/licenses/policies/new');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Name', 'Type', 'Enforcement', 'Allowlist', 'Blocklist']);
    });

    it('should display license selection options', () => {
      cy.visit('/app/supply-chain/licenses/policies/new');
      cy.waitForPageLoad();
      cy.assertContainsAny(['MIT', 'Apache', 'BSD', 'GPL', 'AGPL', 'License']);
    });

    it('should have copyleft options', () => {
      cy.visit('/app/supply-chain/licenses/policies/new');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Copyleft', 'copyleft', 'Block copyleft', 'Strong copyleft']);
    });
  });

  describe('License Policy Detail Page', () => {
    it('should navigate to policy detail page', () => {
      cy.assertPageReady('/app/supply-chain/licenses/policies');
      cy.get('table tbody tr, [data-testid*="policy-row"]').first().click();
      cy.url().should('match', /\/policies\/[^/]+$/);
    });

    it('should display policy details', () => {
      cy.visit('/app/supply-chain/licenses/policies/lp-1');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Production License Policy', 'Policy', 'Details']);
    });

    it('should display allowed licenses', () => {
      cy.visit('/app/supply-chain/licenses/policies/lp-1');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Allowed', 'MIT', 'Apache-2.0', 'BSD']);
    });

    it('should display denied licenses', () => {
      cy.visit('/app/supply-chain/licenses/policies/lp-1');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Denied', 'Blocked', 'AGPL', 'GPL']);
    });

    it('should have edit button', () => {
      cy.visit('/app/supply-chain/licenses/policies/lp-1');
      cy.waitForPageLoad();
      cy.assertHasElement([
        '[data-testid="edit-btn"]',
        'button:contains("Edit")',
        'a[href*="/edit"]',
      ]);
    });

    it('should have toggle active button', () => {
      cy.visit('/app/supply-chain/licenses/policies/lp-1');
      cy.waitForPageLoad();
      cy.assertHasElement([
        '[data-testid="toggle-btn"]',
        'button:contains("Disable")',
        'button:contains("Enable")',
        'button:contains("Deactivate")',
      ]);
    });

    it('should have delete button', () => {
      cy.visit('/app/supply-chain/licenses/policies/lp-1');
      cy.waitForPageLoad();
      cy.assertHasElement([
        '[data-testid="delete-btn"]',
        'button:contains("Delete")',
      ]);
    });
  });

  describe('Edit License Policy', () => {
    beforeEach(() => {
      cy.visit('/app/supply-chain/licenses/policies/lp-1');
      cy.waitForPageLoad();
    });

    it('should open edit form when clicking edit', () => {
      cy.get('[data-testid="edit-btn"], button:contains("Edit"), a[href*="/edit"]').first().click();
      cy.assertContainsAny(['Edit', 'Update', 'Policy', 'Save']);
    });

    it('should toggle policy active status', () => {
      cy.get('[data-testid="toggle-btn"], button:contains("Disable"), button:contains("Enable")').first().click();
      cy.wait('@toggleLicensePolicy');
    });
  });

  describe('License Violations List Page', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/supply-chain/licenses/violations', 'Violation');
    });

    it('should display license violations page', () => {
      cy.assertContainsAny(['License', 'Violations', 'Compliance']);
    });

    it('should display violation entries', () => {
      cy.assertContainsAny(['gpl-library', 'agpl-tool', 'lgpl-util', 'GPL-3.0']);
    });

    it('should display violation severity', () => {
      cy.assertContainsAny(['Critical', 'High', 'Medium', 'Low', 'critical', 'high']);
    });

    it('should display violation type', () => {
      cy.assertContainsAny(['copyleft', 'Copyleft', 'contamination', 'incompatible']);
    });

    it('should display violation status', () => {
      cy.assertContainsAny(['Open', 'Resolved', 'Exception', 'open', 'resolved']);
    });

    it('should have table with proper columns', () => {
      cy.assertContainsAny(['Component', 'License', 'Severity', 'Status', 'SBOM', 'Created']);
    });
  });

  describe('Violation Filtering', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/supply-chain/licenses/violations');
    });

    it('should have filter controls', () => {
      cy.assertHasElement([
        '[data-testid="filter-severity"]',
        '[data-testid="filter-status"]',
        'select',
        '[role="combobox"]',
      ]);
    });

    it('should filter by severity', () => {
      cy.get('[data-testid="filter-severity"], select:contains("Severity")').first().click();
      cy.get('[role="option"], option').contains(/critical/i).click();
      cy.wait('@getLicenseViolationsFiltered');
    });

    it('should filter by status', () => {
      cy.get('[data-testid="filter-status"], select:contains("Status")').first().click();
      cy.get('[role="option"], option').contains(/open/i).click();
      cy.wait('@getLicenseViolationsFiltered');
    });

    it('should search violations', () => {
      cy.get('[data-testid="search-input"], input[type="search"]').first().type('GPL');
      cy.wait('@getLicenseViolationsFiltered');
    });
  });

  describe('Violation Detail Page', () => {
    it('should navigate to violation detail page', () => {
      cy.assertPageReady('/app/supply-chain/licenses/violations');
      cy.get('table tbody tr, [data-testid*="violation-row"]').first().click();
      cy.url().should('match', /\/violations\/[^/]+$/);
    });

    it('should display violation details', () => {
      cy.visit('/app/supply-chain/licenses/violations/viol-1');
      cy.waitForPageLoad();
      cy.assertContainsAny(['gpl-library', 'GPL-3.0', 'Violation', 'Details']);
    });

    it('should display component information', () => {
      cy.visit('/app/supply-chain/licenses/violations/viol-1');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Component', 'Version', 'gpl-library']);
    });

    it('should display associated SBOM', () => {
      cy.visit('/app/supply-chain/licenses/violations/viol-1');
      cy.waitForPageLoad();
      cy.assertContainsAny(['SBOM', 'Production App SBOM']);
    });

    it('should display policy that triggered violation', () => {
      cy.visit('/app/supply-chain/licenses/violations/viol-1');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Policy', 'Production License Policy']);
    });
  });

  describe('Violation Resolution', () => {
    beforeEach(() => {
      cy.visit('/app/supply-chain/licenses/violations/viol-1');
      cy.waitForPageLoad();
    });

    it('should have resolve button', () => {
      cy.assertHasElement([
        '[data-testid="resolve-btn"]',
        'button:contains("Resolve")',
        'button:contains("Mark Resolved")',
      ]);
    });

    it('should open resolution modal when clicking resolve', () => {
      cy.get('[data-testid="resolve-btn"], button:contains("Resolve")').first().click();
      cy.assertContainsAny(['Resolve', 'Resolution', 'Note', 'Comment']);
    });

    it('should have grant exception button', () => {
      cy.assertHasElement([
        '[data-testid="exception-btn"]',
        'button:contains("Exception")',
        'button:contains("Grant Exception")',
      ]);
    });

    it('should open exception modal when clicking grant exception', () => {
      cy.get('[data-testid="exception-btn"], button:contains("Exception")').first().click();
      cy.assertContainsAny(['Exception', 'Justification', 'Reason', 'Grant']);
    });
  });

  describe('Violation Actions', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/supply-chain/licenses/violations');
    });

    it('should have bulk action options', () => {
      cy.get('[data-testid="select-all"], input[type="checkbox"]').first().check();
      cy.assertContainsAny(['Bulk', 'Selected', 'Action']);
    });
  });

  describe('Error Handling', () => {
    it('should handle policy not found', () => {
      cy.intercept('GET', '**/api/v1/supply_chain/license_policies/nonexistent', {
        statusCode: 404,
        body: { success: false, error: 'Policy not found' },
      });

      cy.visit('/app/supply-chain/licenses/policies/nonexistent');
      cy.assertContainsAny(['not found', 'Not Found', 'error', 'Error', '404']);
    });

    it('should handle violation not found', () => {
      cy.intercept('GET', '**/api/v1/supply_chain/license_violations/nonexistent', {
        statusCode: 404,
        body: { success: false, error: 'Violation not found' },
      });

      cy.visit('/app/supply-chain/licenses/violations/nonexistent');
      cy.assertContainsAny(['not found', 'Not Found', 'error', 'Error', '404']);
    });

    it('should handle policies list loading error', () => {
      cy.testErrorHandling('/api/v1/supply_chain/license_policies', {
        statusCode: 500,
        visitUrl: '/app/supply-chain/licenses/policies',
      });
    });

    it('should handle violations list loading error', () => {
      cy.testErrorHandling('/api/v1/supply_chain/license_violations', {
        statusCode: 500,
        visitUrl: '/app/supply-chain/licenses/violations',
      });
    });
  });

  describe('Responsive Design', () => {
    it('should display policies page properly across viewports', () => {
      cy.testResponsiveDesign('/app/supply-chain/licenses/policies', {
        checkContent: 'Policy',
      });
    });

    it('should display violations page properly across viewports', () => {
      cy.testResponsiveDesign('/app/supply-chain/licenses/violations', {
        checkContent: 'Violation',
      });
    });
  });
});

export {};

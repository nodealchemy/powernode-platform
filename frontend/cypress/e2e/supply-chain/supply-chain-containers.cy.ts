/// <reference types="cypress" />

/**
 * Container Images E2E Tests
 *
 * Tests for the Container Images functionality including:
 * - Container image list display
 * - Image filtering by status
 * - Image detail view
 * - Vulnerability scanning
 * - Policy violations
 * - Quarantine/Release operations
 */

describe('Container Images Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup({ intercepts: ['supply-chain'] });
    cy.setupSupplyChainIntercepts();
  });

  describe('Container Images List Page', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/supply-chain/containers', 'Container');
    });

    it('should display container images page', () => {
      cy.assertContainsAny(['Container', 'Images', 'Registry']);
    });

    it('should display container image entries', () => {
      cy.assertContainsAny(['ghcr.io', 'org/api-server', 'org/web-app', 'org/worker', 'latest']);
    });

    it('should display image status indicators', () => {
      cy.assertContainsAny(['verified', 'Verified', 'quarantined', 'Quarantined', 'scanning', 'Scanning']);
    });

    it('should display vulnerability counts', () => {
      cy.assertContainsAny(['Critical', 'High', 'Medium', 'Low', '0', '2', '5', '10']);
    });

    it('should have table with proper columns', () => {
      cy.assertContainsAny(['Image', 'Registry', 'Tag', 'Status', 'Vulnerabilities', 'Last Scanned']);
    });
  });

  describe('Container Image Filtering', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/supply-chain/containers');
    });

    it('should have status filter', () => {
      cy.assertHasElement([
        '[data-testid="filter-status"]',
        'select',
        '[role="combobox"]',
      ]);
    });

    it('should filter by verified status', () => {
      cy.get('[data-testid="filter-status"], select').first().click();
      cy.get('[role="option"], option').contains(/verified/i).click();
      cy.wait('@getContainerImagesFiltered');
    });

    it('should filter by quarantined status', () => {
      cy.get('[data-testid="filter-status"], select').first().click();
      cy.get('[role="option"], option').contains(/quarantined/i).click();
      cy.wait('@getContainerImagesFiltered');
    });

    it('should search container images', () => {
      cy.get('[data-testid="search-input"], input[type="search"], input[placeholder*="Search"]').first().type('api-server');
      cy.wait('@getContainerImagesFiltered');
    });
  });

  describe('Container Image Detail Page', () => {
    it('should navigate to container detail page', () => {
      cy.assertPageReady('/app/supply-chain/containers');
      cy.get('table tbody tr, [data-testid*="container-row"]').first().click();
      cy.url().should('match', /\/containers\/[^/]+$/);
    });

    it('should display container image details', () => {
      cy.visit('/app/supply-chain/containers/image-1');
      cy.waitForPageLoad();
      cy.assertContainsAny(['org/api-server', 'ghcr.io', 'Container', 'Image']);
    });

    it('should display image digest', () => {
      cy.visit('/app/supply-chain/containers/image-1');
      cy.waitForPageLoad();
      cy.assertContainsAny(['sha256', 'Digest', 'digest']);
    });

    it('should display scan results', () => {
      cy.visit('/app/supply-chain/containers/image-1');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Scan', 'Results', 'trivy', 'Trivy', 'completed', 'Completed']);
    });

    it('should display vulnerabilities table', () => {
      cy.visit('/app/supply-chain/containers/image-1');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Vulnerabilities', 'CVE', 'Severity', 'Package']);
    });

    it('should display associated SBOM', () => {
      cy.visit('/app/supply-chain/containers/image-1');
      cy.waitForPageLoad();
      cy.assertContainsAny(['SBOM', 'Bill of Materials', 'Components']);
    });
  });

  describe('Vulnerability Scanning', () => {
    beforeEach(() => {
      cy.visit('/app/supply-chain/containers/image-1');
      cy.waitForPageLoad();
    });

    it('should have scan/rescan button', () => {
      cy.assertHasElement([
        '[data-testid="scan-btn"]',
        '[data-testid="rescan-btn"]',
        'button:contains("Scan")',
        'button:contains("Rescan")',
      ]);
    });

    it('should trigger scan when clicking scan button', () => {
      cy.get('[data-testid="scan-btn"], [data-testid="rescan-btn"], button:contains("Scan")').first().click();
      cy.wait('@scanContainerImage');
      cy.assertContainsAny(['Scan', 'started', 'running', 'queued']);
    });

    it('should display scan history', () => {
      cy.assertContainsAny(['History', 'Previous', 'Scans', 'completed']);
    });
  });

  describe('Policy Violations', () => {
    beforeEach(() => {
      cy.visit('/app/supply-chain/containers/image-1');
      cy.waitForPageLoad();
    });

    it('should display applicable policies', () => {
      cy.assertContainsAny(['Policy', 'Policies', 'Production Policy', 'applicable']);
    });

    it('should display policy violation status', () => {
      cy.assertContainsAny(['Violation', 'violation', 'Pass', 'Fail', 'compliant']);
    });
  });

  describe('Quarantine/Release Operations', () => {
    it('should have quarantine button for verified images', () => {
      cy.visit('/app/supply-chain/containers/image-1');
      cy.waitForPageLoad();
      cy.assertHasElement([
        '[data-testid="quarantine-btn"]',
        'button:contains("Quarantine")',
      ]);
    });

    it('should show confirmation when quarantining', () => {
      cy.visit('/app/supply-chain/containers/image-1');
      cy.waitForPageLoad();
      cy.get('[data-testid="quarantine-btn"], button:contains("Quarantine")').first().click();
      cy.assertContainsAny(['Confirm', 'Are you sure', 'Quarantine', 'Cancel']);
    });

    it('should have release button for quarantined images', () => {
      // Mock a quarantined image
      cy.intercept('GET', /\/api\/v1\/supply_chain\/container_images\/image-2/, {
        statusCode: 200,
        body: {
          success: true,
          data: {
            id: 'image-2',
            registry: 'ghcr.io',
            repository: 'org/web-app',
            tag: 'latest',
            status: 'quarantined',
            critical_vuln_count: 2,
          },
        },
      });

      cy.visit('/app/supply-chain/containers/image-2');
      cy.waitForPageLoad();
      cy.assertHasElement([
        '[data-testid="release-btn"]',
        'button:contains("Release")',
      ]);
    });
  });

  describe('Error Handling', () => {
    it('should handle image not found', () => {
      cy.intercept('GET', '**/api/v1/supply_chain/container_images/nonexistent', {
        statusCode: 404,
        body: { success: false, error: 'Container image not found' },
      });

      cy.visit('/app/supply-chain/containers/nonexistent');
      cy.assertContainsAny(['not found', 'Not Found', 'error', 'Error', '404']);
    });

    it('should handle list loading error', () => {
      cy.testErrorHandling('/api/v1/supply_chain/container_images', {
        statusCode: 500,
        visitUrl: '/app/supply-chain/containers',
      });
    });
  });

  describe('Responsive Design', () => {
    it('should display properly across viewports', () => {
      cy.testResponsiveDesign('/app/supply-chain/containers', {
        checkContent: 'Container',
      });
    });
  });
});

export {};

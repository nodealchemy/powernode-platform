/// <reference types="cypress" />

/**
 * Attestations E2E Tests
 *
 * Tests for the Attestations/SLSA functionality including:
 * - Attestation list display
 * - Attestation detail view
 * - Build provenance display
 * - Verification status
 * - Signing operations
 * - SLSA level indicators
 */

describe('Attestations Tests', () => {
  beforeEach(() => {
    cy.standardTestSetup({ intercepts: ['supply-chain'] });
    cy.setupSupplyChainIntercepts();
  });

  describe('Attestations List Page', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/supply-chain/attestations', 'Attestation');
    });

    it('should display attestations page', () => {
      cy.assertContainsAny(['Attestations', 'SLSA', 'Provenance']);
    });

    it('should display attestation entries', () => {
      cy.assertContainsAny(['api-server:v1.0.0', 'web-app:v2.1.0', 'worker:v1.5.0']);
    });

    it('should display verification status', () => {
      cy.assertContainsAny(['verified', 'Verified', 'pending', 'Pending', 'failed', 'Failed']);
    });

    it('should display SLSA level indicators', () => {
      cy.assertContainsAny(['SLSA', 'Level', 'L1', 'L2', 'L3', 'Level 3', 'Level 2']);
    });

    it('should display signing status', () => {
      cy.assertContainsAny(['Signed', 'signed', 'Unsigned', 'unsigned']);
    });

    it('should have table with proper columns', () => {
      cy.assertContainsAny(['Subject', 'Type', 'SLSA Level', 'Verification', 'Signed', 'Created']);
    });
  });

  describe('Attestation Filtering', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/supply-chain/attestations');
    });

    it('should have filter controls', () => {
      cy.assertHasElement([
        '[data-testid="filter-status"]',
        '[data-testid="filter-slsa"]',
        'select',
        '[role="combobox"]',
      ]);
    });

    it('should filter by verification status', () => {
      cy.get('[data-testid="filter-status"], select').first().click();
      cy.get('[role="option"], option').contains(/verified/i).click();
      cy.wait('@getAttestationsFiltered');
    });

    it('should search attestations', () => {
      cy.get('[data-testid="search-input"], input[type="search"]').first().type('api-server');
      cy.wait('@getAttestationsFiltered');
    });
  });

  describe('Attestation Detail Page', () => {
    it('should navigate to attestation detail page', () => {
      cy.assertPageReady('/app/supply-chain/attestations');
      cy.get('table tbody tr, [data-testid*="attestation-row"]').first().click();
      cy.url().should('match', /\/attestations\/[^/]+$/);
    });

    it('should display attestation details', () => {
      cy.visit('/app/supply-chain/attestations/att-1');
      cy.waitForPageLoad();
      cy.assertContainsAny(['api-server:v1.0.0', 'Attestation', 'Details']);
    });

    it('should display attestation type', () => {
      cy.visit('/app/supply-chain/attestations/att-1');
      cy.waitForPageLoad();
      cy.assertContainsAny(['slsa_provenance', 'SLSA Provenance', 'Provenance', 'Type']);
    });

    it('should display subject information', () => {
      cy.visit('/app/supply-chain/attestations/att-1');
      cy.waitForPageLoad();
      cy.assertContainsAny(['Subject', 'Digest', 'sha256']);
    });
  });

  describe('Build Provenance', () => {
    beforeEach(() => {
      cy.visit('/app/supply-chain/attestations/att-1');
      cy.waitForPageLoad();
    });

    it('should display build provenance section', () => {
      cy.assertContainsAny(['Provenance', 'Build', 'Builder']);
    });

    it('should display builder information', () => {
      cy.assertContainsAny(['github.com/actions', 'GitHub Actions', 'Builder ID']);
    });

    it('should display invocation details', () => {
      cy.assertContainsAny(['Invocation', 'Actor', 'Event', 'push', 'test-user']);
    });

    it('should display materials/sources', () => {
      cy.assertContainsAny(['Materials', 'Source', 'git', 'repo', 'Commit']);
    });
  });

  describe('Verification', () => {
    beforeEach(() => {
      cy.visit('/app/supply-chain/attestations/att-1');
      cy.waitForPageLoad();
    });

    it('should display verification status', () => {
      cy.assertContainsAny(['Verification', 'Status', 'verified', 'Verified']);
    });

    it('should display verification logs', () => {
      cy.assertContainsAny(['Logs', 'verified successfully', 'Signature']);
    });

    it('should have verify button for unverified attestations', () => {
      cy.assertHasElement([
        '[data-testid="verify-btn"]',
        'button:contains("Verify")',
      ]);
    });

    it('should trigger verification when clicking verify', () => {
      cy.get('[data-testid="verify-btn"], button:contains("Verify")').first().click();
      cy.wait('@verifyAttestation');
    });
  });

  describe('Signing Operations', () => {
    beforeEach(() => {
      cy.visit('/app/supply-chain/attestations/att-1');
      cy.waitForPageLoad();
    });

    it('should display signing key information', () => {
      cy.assertContainsAny(['Signing', 'Key', 'Production Key', 'cosign']);
    });

    it('should display Rekor log status', () => {
      cy.assertContainsAny(['Rekor', 'logged', 'Transparency', 'Log']);
    });

    it('should have sign button for unsigned attestations', () => {
      // Mock an unsigned attestation
      cy.intercept('GET', /\/api\/v1\/supply_chain\/attestations\/att-3/, {
        statusCode: 200,
        body: {
          success: true,
          data: {
            id: 'att-3',
            subject_name: 'worker:v1.5.0',
            signed: false,
            verification_status: 'pending',
          },
        },
      });

      cy.visit('/app/supply-chain/attestations/att-3');
      cy.waitForPageLoad();
      cy.assertHasElement([
        '[data-testid="sign-btn"]',
        'button:contains("Sign")',
      ]);
    });
  });

  describe('SLSA Compliance', () => {
    beforeEach(() => {
      cy.visit('/app/supply-chain/attestations/att-1');
      cy.waitForPageLoad();
    });

    it('should display SLSA level', () => {
      cy.assertContainsAny(['SLSA', 'Level 3', 'L3', 'Level']);
    });

    it('should display SLSA requirements status', () => {
      cy.assertContainsAny(['Requirements', 'completeness', 'reproducibility', 'hermetic']);
    });
  });

  describe('Create Attestation', () => {
    beforeEach(() => {
      cy.assertPageReady('/app/supply-chain/attestations');
    });

    it('should have create attestation button', () => {
      cy.assertHasElement([
        '[data-testid="create-btn"]',
        '[data-testid="action-create"]',
        'button:contains("Create")',
        'button:contains("New")',
      ]);
    });

    it('should open create attestation modal', () => {
      cy.get('[data-testid="create-btn"], button:contains("Create"), button:contains("New")').first().click();
      cy.assertContainsAny(['Create', 'New', 'Attestation', 'Subject', 'Type']);
    });
  });

  describe('Error Handling', () => {
    it('should handle attestation not found', () => {
      cy.intercept('GET', '**/api/v1/supply_chain/attestations/nonexistent', {
        statusCode: 404,
        body: { success: false, error: 'Attestation not found' },
      });

      cy.visit('/app/supply-chain/attestations/nonexistent');
      cy.assertContainsAny(['not found', 'Not Found', 'error', 'Error', '404']);
    });

    it('should handle list loading error', () => {
      cy.testErrorHandling('/api/v1/supply_chain/attestations', {
        statusCode: 500,
        visitUrl: '/app/supply-chain/attestations',
      });
    });
  });

  describe('Responsive Design', () => {
    it('should display properly across viewports', () => {
      cy.testResponsiveDesign('/app/supply-chain/attestations', {
        checkContent: 'Attestation',
      });
    });
  });
});

export {};

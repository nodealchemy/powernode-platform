/// <reference types="cypress" />

/**
 * Supply Chain E2E Test Commands
 *
 * Provides API intercepts and helper commands for supply chain feature testing.
 * Includes mock data for SBOMs, container images, attestations, vendors, and license compliance.
 */

declare global {
  namespace Cypress {
    interface Chainable {
      /**
       * Set up supply chain API intercepts with mock data
       * @example cy.setupSupplyChainIntercepts()
       */
      setupSupplyChainIntercepts(): Chainable<void>;

      /**
       * Navigate to a supply chain page
       * @example cy.visitSupplyChainPage('sboms')
       */
      visitSupplyChainPage(page: string): Chainable<void>;

      /**
       * Assert supply chain stat card is displayed
       * @example cy.assertSupplyChainStatCard('SBOMs', '15')
       */
      assertSupplyChainStatCard(label: string, value?: string): Chainable<void>;
    }
  }
}

// ============================================================================
// Mock Data Factories
// ============================================================================

const createMockSbom = (overrides: Record<string, unknown> = {}) => ({
  id: 'sbom-' + Math.random().toString(36).substr(2, 9),
  sbom_id: 'SBOM-' + Date.now(),
  name: 'Test Application SBOM',
  format: 'cyclonedx_1_5',
  version: '1.0.0',
  status: 'completed',
  component_count: 150,
  vulnerability_count: 5,
  risk_score: 45,
  ntia_minimum_compliant: true,
  commit_sha: 'abc123def456',
  branch: 'main',
  repository_id: 'repo-123',
  created_at: new Date().toISOString(),
  updated_at: new Date().toISOString(),
  ...overrides,
});

const createMockContainerImage = (overrides: Record<string, unknown> = {}) => ({
  id: 'image-' + Math.random().toString(36).substr(2, 9),
  registry: 'ghcr.io',
  repository: 'org/app',
  tag: 'latest',
  digest: 'sha256:' + 'a'.repeat(64),
  status: 'verified',
  critical_vuln_count: 0,
  high_vuln_count: 2,
  medium_vuln_count: 5,
  low_vuln_count: 10,
  is_deployed: true,
  last_scanned_at: new Date().toISOString(),
  created_at: new Date(Date.now() - 86400000).toISOString(),
  updated_at: new Date().toISOString(),
  ...overrides,
});

const createMockAttestation = (overrides: Record<string, unknown> = {}) => ({
  id: 'att-' + Math.random().toString(36).substr(2, 9),
  attestation_id: 'ATT-' + Date.now(),
  attestation_type: 'slsa_provenance',
  slsa_level: 3,
  subject_name: 'app:latest',
  subject_digest: 'sha256:' + 'b'.repeat(64),
  verification_status: 'verified',
  signed: true,
  rekor_logged: true,
  created_at: new Date(Date.now() - 3600000).toISOString(),
  updated_at: new Date().toISOString(),
  ...overrides,
});

const createMockVendor = (overrides: Record<string, unknown> = {}) => ({
  id: 'vendor-' + Math.random().toString(36).substr(2, 9),
  name: 'Test Vendor Inc',
  vendor_type: 'saas',
  risk_tier: 'medium',
  risk_score: 35,
  status: 'active',
  handles_pii: true,
  handles_phi: false,
  handles_pci: true,
  certifications: ['SOC2', 'ISO27001'],
  contact_name: 'John Doe',
  contact_email: 'john@vendor.com',
  website: 'https://vendor.com',
  last_assessment_at: new Date(Date.now() - 2592000000).toISOString(),
  next_assessment_due: new Date(Date.now() + 2592000000).toISOString(),
  created_at: new Date(Date.now() - 7776000000).toISOString(),
  updated_at: new Date().toISOString(),
  ...overrides,
});

const createMockLicensePolicy = (overrides: Record<string, unknown> = {}) => ({
  id: 'lp-' + Math.random().toString(36).substr(2, 9),
  name: 'Production License Policy',
  policy_type: 'allowlist',
  enforcement_level: 'block',
  is_active: true,
  block_copyleft: true,
  block_strong_copyleft: true,
  allowed_licenses: ['MIT', 'Apache-2.0', 'BSD-3-Clause'],
  denied_licenses: ['AGPL-3.0', 'GPL-3.0'],
  created_at: new Date(Date.now() - 2592000000).toISOString(),
  updated_at: new Date().toISOString(),
  ...overrides,
});

const createMockLicenseViolation = (overrides: Record<string, unknown> = {}) => ({
  id: 'viol-' + Math.random().toString(36).substr(2, 9),
  component_name: 'copyleft-lib',
  component_version: '1.2.3',
  license_name: 'GPL-3.0',
  license_spdx_id: 'GPL-3.0-only',
  violation_type: 'copyleft_contamination',
  severity: 'high',
  status: 'open',
  sbom_id: 'sbom-123',
  policy_id: 'policy-456',
  created_at: new Date().toISOString(),
  ...overrides,
});

const createMockVulnerability = (overrides: Record<string, unknown> = {}) => ({
  id: 'vuln-' + Math.random().toString(36).substr(2, 9),
  vulnerability_id: 'CVE-2024-12345',
  severity: 'high',
  cvss_score: 7.5,
  cvss_vector: 'CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:N/A:N',
  remediation_status: 'open',
  fixed_version: '4.17.22',
  component: {
    name: 'lodash',
    version: '4.17.21',
  },
  ...overrides,
});

// ============================================================================
// Supply Chain API Intercepts
// ============================================================================

Cypress.Commands.add('setupSupplyChainIntercepts', () => {
  // IMPORTANT: Register catch-all intercepts FIRST (Cypress uses LIFO order for matching)
  // More specific patterns registered later will take precedence
  cy.intercept('GET', '**/api/v1/supply_chain/**', {
    statusCode: 200,
    body: { success: true, data: {} },
  }).as('getSupplyChainGeneric');

  cy.intercept('POST', '**/api/v1/supply_chain/**', {
    statusCode: 200,
    body: { success: true, data: {} },
  }).as('postSupplyChainGeneric');

  cy.intercept('PUT', '**/api/v1/supply_chain/**', {
    statusCode: 200,
    body: { success: true, data: {} },
  }).as('putSupplyChainGeneric');

  cy.intercept('DELETE', '**/api/v1/supply_chain/**', {
    statusCode: 200,
    body: { success: true, data: null },
  }).as('deleteSupplyChainGeneric');

  // Create mock data arrays
  const mockSboms = [
    createMockSbom({ id: 'sbom-1', name: 'Production App SBOM', vulnerability_count: 3 }),
    createMockSbom({ id: 'sbom-2', name: 'API Service SBOM', status: 'generating' }),
    createMockSbom({ id: 'sbom-3', name: 'Frontend SBOM', ntia_minimum_compliant: false }),
  ];

  const mockContainerImages = [
    createMockContainerImage({ id: 'image-1', repository: 'org/api-server', status: 'verified' }),
    createMockContainerImage({ id: 'image-2', repository: 'org/web-app', status: 'quarantined', critical_vuln_count: 2 }),
    createMockContainerImage({ id: 'image-3', repository: 'org/worker', status: 'verified' }),
  ];

  const mockAttestations = [
    createMockAttestation({ id: 'att-1', subject_name: 'api-server:v1.0.0', verification_status: 'verified' }),
    createMockAttestation({ id: 'att-2', subject_name: 'web-app:v2.1.0', verification_status: 'pending' }),
    createMockAttestation({ id: 'att-3', subject_name: 'worker:v1.5.0', signed: false }),
  ];

  const mockVendors = [
    createMockVendor({ id: 'vendor-1', name: 'Cloud Provider Inc', risk_tier: 'low' }),
    createMockVendor({ id: 'vendor-2', name: 'Payment Gateway Corp', risk_tier: 'high', handles_pci: true }),
    createMockVendor({ id: 'vendor-3', name: 'Analytics Service', risk_tier: 'medium' }),
  ];

  const mockLicensePolicies = [
    createMockLicensePolicy({ id: 'lp-1', name: 'Production Policy', is_active: true }),
    createMockLicensePolicy({ id: 'lp-2', name: 'Development Policy', enforcement_level: 'warn' }),
  ];

  const mockLicenseViolations = [
    createMockLicenseViolation({ id: 'viol-1', component_name: 'gpl-library', severity: 'critical' }),
    createMockLicenseViolation({ id: 'viol-2', component_name: 'agpl-tool', severity: 'high' }),
    createMockLicenseViolation({ id: 'viol-3', component_name: 'lgpl-util', severity: 'medium', status: 'resolved' }),
  ];

  const mockVulnerabilities = [
    createMockVulnerability({ id: 'vuln-1', vulnerability_id: 'CVE-2024-12345', severity: 'critical' }),
    createMockVulnerability({ id: 'vuln-2', vulnerability_id: 'CVE-2024-12346', severity: 'high' }),
    createMockVulnerability({ id: 'vuln-3', vulnerability_id: 'CVE-2024-12347', severity: 'medium' }),
  ];

  // Dashboard endpoint - matches DashboardApiResponse structure from supplyChainApi.ts
  const mockDashboard = {
    overview: {
      sboms: {
        total: 15,
        with_vulnerabilities: 5,
        ntia_compliant: 10,
      },
      vulnerabilities: {
        total: 42,
        critical: 2,
        high: 8,
        open: 3,
      },
      attestations: {
        total: 18,
        signed: 15,
        verified: 16,
      },
      container_images: {
        total: 25,
        verified: 20,
        quarantined: 1,
      },
      vendors: {
        total: 12,
        active: 10,
        high_risk: 2,
      },
    },
    quick_stats: {
      sboms_this_month: 3,
      scans_this_month: 5,
      attestations_this_month: 2,
      average_risk_score: 45.5,
    },
    alerts: [
      {
        severity: 'critical',
        type: 'vulnerability',
        message: 'Critical vulnerability detected in production SBOM',
        action_url: '/supply-chain/sboms/sbom-1',
      },
      {
        severity: 'high',
        type: 'license',
        message: 'GPL-3.0 license violation found',
        action_url: '/supply-chain/licenses/violations',
      },
      {
        severity: 'medium',
        type: 'vendor',
        message: 'Vendor assessment overdue',
        action_url: '/supply-chain/vendors/vendor-2',
      },
    ],
    recent_activity: [
      {
        type: 'sbom_created',
        title: 'SBOM generated for api-server:v1.0.0',
        timestamp: new Date().toISOString(),
        details: { format: 'CycloneDX', components: 150 },
      },
      {
        type: 'scan_completed',
        title: 'Container scan completed for web-app',
        timestamp: new Date(Date.now() - 3600000).toISOString(),
        details: { image: 'web-app:latest', vulnerabilities: 5 },
      },
      {
        type: 'attestation_verified',
        title: 'Attestation verified for worker:v1.5.0',
        timestamp: new Date(Date.now() - 7200000).toISOString(),
        details: { slsa_level: 3 },
      },
    ],
  };

  // Dashboard endpoints
  cy.intercept('GET', '**/api/v1/supply_chain/dashboard', {
    statusCode: 200,
    body: { success: true, data: mockDashboard },
  }).as('getSupplyChainDashboard');

  cy.intercept('GET', '**/api/v1/supply_chain/analytics*', {
    statusCode: 200,
    body: {
      success: true,
      data: {
        vulnerability_trends: [
          { date: '2024-01-01', critical: 1, high: 5, medium: 10, low: 15 },
          { date: '2024-01-08', critical: 2, high: 6, medium: 12, low: 18 },
          { date: '2024-01-15', critical: 2, high: 8, medium: 15, low: 20 },
        ],
        sbom_generation_rate: { total: 15, this_week: 3, last_week: 2 },
        compliance_score: 85,
      },
    },
  }).as('getSupplyChainAnalytics');

  cy.intercept('GET', '**/api/v1/supply_chain/compliance_summary*', {
    statusCode: 200,
    body: {
      success: true,
      data: {
        ntia_compliance: { compliant: 10, non_compliant: 5, percentage: 66.7 },
        slsa_compliance: { level_0: 2, level_1: 5, level_2: 8, level_3: 3 },
        license_compliance: { compliant: 12, violations: 3, percentage: 80 },
      },
    },
  }).as('getComplianceSummary');

  // SBOM endpoints
  cy.intercept('GET', '**/api/v1/supply_chain/sboms', {
    statusCode: 200,
    body: {
      success: true,
      data: {
        items: mockSboms,
        pagination: { current_page: 1, per_page: 20, total_pages: 1, total_count: 3 },
      },
    },
  }).as('getSboms');

  cy.intercept('GET', '**/api/v1/supply_chain/sboms?*', {
    statusCode: 200,
    body: {
      success: true,
      data: {
        items: mockSboms,
        pagination: { current_page: 1, per_page: 20, total_pages: 1, total_count: 3 },
      },
    },
  }).as('getSbomsFiltered');

  cy.intercept('GET', /\/api\/v1\/supply_chain\/sboms\/[^\/]+$/, {
    statusCode: 200,
    body: {
      success: true,
      data: {
        ...mockSboms[0],
        components: [
          { id: 'comp-1', purl: 'pkg:npm/lodash@4.17.21', name: 'lodash', version: '4.17.21', ecosystem: 'npm' },
          { id: 'comp-2', purl: 'pkg:npm/express@4.18.2', name: 'express', version: '4.18.2', ecosystem: 'npm' },
        ],
        vulnerabilities: mockVulnerabilities,
        repository: { id: 'repo-123', name: 'my-repo', full_name: 'org/my-repo' },
      },
    },
  }).as('getSbom');

  cy.intercept('POST', '**/api/v1/supply_chain/sboms', {
    statusCode: 201,
    body: { success: true, data: mockSboms[0] },
  }).as('createSbom');

  cy.intercept('DELETE', /\/api\/v1\/supply_chain\/sboms\/[^\/]+$/, {
    statusCode: 200,
    body: { success: true, data: null },
  }).as('deleteSbom');

  cy.intercept('GET', /\/api\/v1\/supply_chain\/sboms\/[^\/]+\/export/, {
    statusCode: 200,
    body: { success: true, data: { content: '<?xml version="1.0"?><sbom/>', format: 'cyclonedx' } },
  }).as('exportSbom');

  cy.intercept('POST', /\/api\/v1\/supply_chain\/sboms\/[^\/]+\/diff/, {
    statusCode: 200,
    body: {
      success: true,
      data: {
        id: 'diff-1',
        added_components: [{ name: 'new-lib', version: '1.0.0' }],
        removed_components: [{ name: 'old-lib', version: '0.9.0' }],
        modified_components: [],
      },
    },
  }).as('createSbomDiff');

  // Container Images endpoints
  cy.intercept('GET', '**/api/v1/supply_chain/container_images', {
    statusCode: 200,
    body: {
      success: true,
      data: {
        items: mockContainerImages,
        pagination: { current_page: 1, per_page: 20, total_pages: 1, total_count: 3 },
      },
    },
  }).as('getContainerImages');

  cy.intercept('GET', '**/api/v1/supply_chain/container_images?*', {
    statusCode: 200,
    body: {
      success: true,
      data: {
        items: mockContainerImages,
        pagination: { current_page: 1, per_page: 20, total_pages: 1, total_count: 3 },
      },
    },
  }).as('getContainerImagesFiltered');

  cy.intercept('GET', /\/api\/v1\/supply_chain\/container_images\/[^\/]+$/, {
    statusCode: 200,
    body: {
      success: true,
      data: {
        ...mockContainerImages[0],
        scans: [
          {
            id: 'scan-1',
            scanner: 'trivy',
            status: 'completed',
            critical_count: 0,
            high_count: 2,
            medium_count: 5,
            low_count: 10,
            completed_at: new Date().toISOString(),
          },
        ],
        applicable_policies: [{ id: 'policy-1', name: 'Production Policy' }],
        sbom: { id: 'sbom-1', name: 'API Server SBOM' },
      },
    },
  }).as('getContainerImage');

  cy.intercept('POST', /\/api\/v1\/supply_chain\/container_images\/[^\/]+\/scan/, {
    statusCode: 200,
    body: { success: true, data: { scan_id: 'scan-new', status: 'running' } },
  }).as('scanContainerImage');

  cy.intercept('POST', /\/api\/v1\/supply_chain\/container_images\/[^\/]+\/quarantine/, {
    statusCode: 200,
    body: { success: true, data: { ...mockContainerImages[0], status: 'quarantined' } },
  }).as('quarantineContainerImage');

  cy.intercept('POST', /\/api\/v1\/supply_chain\/container_images\/[^\/]+\/release/, {
    statusCode: 200,
    body: { success: true, data: { ...mockContainerImages[0], status: 'verified' } },
  }).as('releaseContainerImage');

  // Attestations endpoints
  cy.intercept('GET', '**/api/v1/supply_chain/attestations', {
    statusCode: 200,
    body: {
      success: true,
      data: {
        items: mockAttestations,
        pagination: { current_page: 1, per_page: 20, total_pages: 1, total_count: 3 },
      },
    },
  }).as('getAttestations');

  cy.intercept('GET', '**/api/v1/supply_chain/attestations?*', {
    statusCode: 200,
    body: {
      success: true,
      data: {
        items: mockAttestations,
        pagination: { current_page: 1, per_page: 20, total_pages: 1, total_count: 3 },
      },
    },
  }).as('getAttestationsFiltered');

  cy.intercept('GET', /\/api\/v1\/supply_chain\/attestations\/[^\/]+$/, {
    statusCode: 200,
    body: {
      success: true,
      data: {
        ...mockAttestations[0],
        build_provenance: {
          builder_id: 'https://github.com/actions',
          build_type: 'https://github.com/Attestations/GitHubActionsWorkflow@v1',
          invocation: { github_actor: 'test-user', github_event: 'push', github_ref: 'refs/heads/main' },
          materials: [{ uri: 'git+https://github.com/org/repo@main', digest: { gitCommit: 'abc123' } }],
        },
        signing_key: { id: 'key-1', name: 'Production Key', key_type: 'cosign' },
        verification_logs: [
          { verified_at: new Date().toISOString(), status: 'verified', message: 'Signature verified successfully' },
        ],
      },
    },
  }).as('getAttestation');

  cy.intercept('POST', '**/api/v1/supply_chain/attestations', {
    statusCode: 201,
    body: { success: true, data: mockAttestations[0] },
  }).as('createAttestation');

  cy.intercept('POST', /\/api\/v1\/supply_chain\/attestations\/[^\/]+\/sign/, {
    statusCode: 200,
    body: { success: true, data: { ...mockAttestations[0], signed: true } },
  }).as('signAttestation');

  cy.intercept('POST', /\/api\/v1\/supply_chain\/attestations\/[^\/]+\/verify/, {
    statusCode: 200,
    body: { success: true, data: { ...mockAttestations[0], verification_status: 'verified' } },
  }).as('verifyAttestation');

  // Vendors endpoints
  cy.intercept('GET', '**/api/v1/supply_chain/vendors', {
    statusCode: 200,
    body: {
      success: true,
      data: {
        items: mockVendors,
        pagination: { current_page: 1, per_page: 20, total_pages: 1, total_count: 3 },
      },
    },
  }).as('getVendors');

  cy.intercept('GET', '**/api/v1/supply_chain/vendors?*', {
    statusCode: 200,
    body: {
      success: true,
      data: {
        items: mockVendors,
        pagination: { current_page: 1, per_page: 20, total_pages: 1, total_count: 3 },
      },
    },
  }).as('getVendorsFiltered');

  cy.intercept('GET', '**/api/v1/supply_chain/vendors/risk_dashboard*', {
    statusCode: 200,
    body: {
      success: true,
      data: {
        total_vendors: 12,
        high_risk: 2,
        medium_risk: 5,
        low_risk: 5,
        average_risk_score: 42,
        vendors_needing_assessment: 3,
        recent_assessments: [],
      },
    },
  }).as('getVendorRiskDashboard');

  cy.intercept('GET', /\/api\/v1\/supply_chain\/vendors\/[^\/]+$/, {
    statusCode: 200,
    body: {
      success: true,
      data: {
        vendor: {
          ...mockVendors[0],
          assessments: [
            {
              id: 'assess-1',
              assessment_type: 'periodic',
              status: 'completed',
              overall_score: 78,
              valid_until: new Date(Date.now() + 31536000000).toISOString(),
            },
          ],
          questionnaires: [
            {
              id: 'quest-1',
              template_name: 'Security Assessment Q1 2024',
              status: 'completed',
              response_count: 45,
              total_questions: 50,
            },
          ],
        },
      },
    },
  }).as('getVendor');

  cy.intercept('POST', '**/api/v1/supply_chain/vendors', {
    statusCode: 201,
    body: { success: true, data: mockVendors[0] },
  }).as('createVendor');

  cy.intercept('PUT', /\/api\/v1\/supply_chain\/vendors\/[^\/]+$/, {
    statusCode: 200,
    body: { success: true, data: mockVendors[0] },
  }).as('updateVendor');

  cy.intercept('DELETE', /\/api\/v1\/supply_chain\/vendors\/[^\/]+$/, {
    statusCode: 200,
    body: { success: true, data: null },
  }).as('deleteVendor');

  cy.intercept('POST', /\/api\/v1\/supply_chain\/vendors\/[^\/]+\/assessments/, {
    statusCode: 201,
    body: { success: true, data: { id: 'assess-new', status: 'in_progress' } },
  }).as('startVendorAssessment');

  cy.intercept('POST', /\/api\/v1\/supply_chain\/vendors\/[^\/]+\/questionnaires/, {
    statusCode: 201,
    body: { success: true, data: { id: 'quest-new', status: 'sent' } },
  }).as('sendVendorQuestionnaire');

  // License Policies endpoints
  cy.intercept('GET', '**/api/v1/supply_chain/license_policies', {
    statusCode: 200,
    body: {
      success: true,
      data: {
        items: mockLicensePolicies,
        pagination: { current_page: 1, per_page: 20, total_pages: 1, total_count: 2 },
      },
    },
  }).as('getLicensePolicies');

  cy.intercept('GET', '**/api/v1/supply_chain/license_policies?*', {
    statusCode: 200,
    body: {
      success: true,
      data: {
        items: mockLicensePolicies,
        pagination: { current_page: 1, per_page: 20, total_pages: 1, total_count: 2 },
      },
    },
  }).as('getLicensePoliciesFiltered');

  cy.intercept('GET', /\/api\/v1\/supply_chain\/license_policies\/[^\/]+$/, {
    statusCode: 200,
    body: { success: true, data: mockLicensePolicies[0] },
  }).as('getLicensePolicy');

  cy.intercept('POST', '**/api/v1/supply_chain/license_policies', {
    statusCode: 201,
    body: { success: true, data: mockLicensePolicies[0] },
  }).as('createLicensePolicy');

  cy.intercept('PUT', /\/api\/v1\/supply_chain\/license_policies\/[^\/]+$/, {
    statusCode: 200,
    body: { success: true, data: mockLicensePolicies[0] },
  }).as('updateLicensePolicy');

  cy.intercept('DELETE', /\/api\/v1\/supply_chain\/license_policies\/[^\/]+$/, {
    statusCode: 200,
    body: { success: true, data: null },
  }).as('deleteLicensePolicy');

  cy.intercept('POST', /\/api\/v1\/supply_chain\/license_policies\/[^\/]+\/toggle/, {
    statusCode: 200,
    body: { success: true, data: { ...mockLicensePolicies[0], is_active: false } },
  }).as('toggleLicensePolicy');

  // License Violations endpoints
  cy.intercept('GET', '**/api/v1/supply_chain/license_violations', {
    statusCode: 200,
    body: {
      success: true,
      data: {
        items: mockLicenseViolations,
        pagination: { current_page: 1, per_page: 20, total_pages: 1, total_count: 3 },
      },
    },
  }).as('getLicenseViolations');

  cy.intercept('GET', '**/api/v1/supply_chain/license_violations?*', {
    statusCode: 200,
    body: {
      success: true,
      data: {
        items: mockLicenseViolations,
        pagination: { current_page: 1, per_page: 20, total_pages: 1, total_count: 3 },
      },
    },
  }).as('getLicenseViolationsFiltered');

  cy.intercept('GET', /\/api\/v1\/supply_chain\/license_violations\/[^\/]+$/, {
    statusCode: 200,
    body: {
      success: true,
      data: {
        ...mockLicenseViolations[0],
        sbom: { id: 'sbom-1', name: 'Production App SBOM' },
        policy: { id: 'lp-1', name: 'Production License Policy' },
      },
    },
  }).as('getLicenseViolation');

  cy.intercept('POST', /\/api\/v1\/supply_chain\/license_violations\/[^\/]+\/resolve/, {
    statusCode: 200,
    body: { success: true, data: { ...mockLicenseViolations[0], status: 'resolved' } },
  }).as('resolveLicenseViolation');

  cy.intercept('POST', /\/api\/v1\/supply_chain\/license_violations\/[^\/]+\/exception/, {
    statusCode: 200,
    body: { success: true, data: { ...mockLicenseViolations[0], status: 'exception_granted' } },
  }).as('grantLicenseException');

  // ============================================================================
  // File Management Intercepts for Supply Chain
  // ============================================================================

  const createMockFileObject = (overrides: Record<string, unknown> = {}) => ({
    id: 'file-' + Math.random().toString(36).substr(2, 9),
    filename: 'document.pdf',
    file_size: 1024000,
    content_type: 'application/pdf',
    category: 'vendor_compliance',
    created_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
    uploaded_by: {
      id: 'user-1',
      name: 'Test User',
      email: 'test@example.com',
    },
    ...overrides,
  });

  const mockVendorFiles = [
    createMockFileObject({
      id: 'file-1',
      filename: 'soc2-report-2024.pdf',
      category: 'vendor_compliance',
      file_size: 2048000,
    }),
    createMockFileObject({
      id: 'file-2',
      filename: 'iso27001-certificate.pdf',
      category: 'vendor_certificate',
      file_size: 512000,
    }),
    createMockFileObject({
      id: 'file-3',
      filename: 'risk-assessment-q1.pdf',
      category: 'vendor_assessment',
      file_size: 1536000,
    }),
  ];

  const mockSbomFiles = [
    createMockFileObject({
      id: 'file-sbom-1',
      filename: 'sbom-cyclonedx.json',
      category: 'sbom_export',
      content_type: 'application/json',
      file_size: 256000,
    }),
    createMockFileObject({
      id: 'file-sbom-2',
      filename: 'sbom-spdx.json',
      category: 'sbom_export',
      content_type: 'application/json',
      file_size: 384000,
    }),
  ];

  const mockAttestationFiles = [
    createMockFileObject({
      id: 'file-att-1',
      filename: 'attestation.sig',
      category: 'attestation_proof',
      content_type: 'application/octet-stream',
      file_size: 4096,
    }),
    createMockFileObject({
      id: 'file-att-2',
      filename: 'attestation.bundle',
      category: 'attestation_proof',
      content_type: 'application/octet-stream',
      file_size: 8192,
    }),
  ];

  const mockContainerScanFiles = [
    createMockFileObject({
      id: 'file-scan-1',
      filename: 'trivy-scan-report.json',
      category: 'supply_chain_scan_report',
      content_type: 'application/json',
      file_size: 512000,
    }),
    createMockFileObject({
      id: 'file-scan-2',
      filename: 'grype-scan-report.json',
      category: 'supply_chain_scan_report',
      content_type: 'application/json',
      file_size: 384000,
    }),
  ];

  // Files API - Get files for vendor (handles URL-encoded colons %3A%3A)
  cy.intercept('GET', /\/api\/v1\/files.*attachable_type=SupplyChain(%3A%3A|::)Vendor/i, {
    statusCode: 200,
    body: { success: true, data: { files: mockVendorFiles, pagination: { current_page: 1, per_page: 20, total_pages: 1, total_count: 3 } } },
  }).as('getVendorFiles');

  // Files API - Get files for SBOM (handles URL-encoded colons %3A%3A)
  cy.intercept('GET', /\/api\/v1\/files.*attachable_type=SupplyChain(%3A%3A|::)Sbom/i, {
    statusCode: 200,
    body: { success: true, data: { files: mockSbomFiles, pagination: { current_page: 1, per_page: 20, total_pages: 1, total_count: 2 } } },
  }).as('getSbomFiles');

  // Files API - Get files for Attestation (handles URL-encoded colons %3A%3A)
  cy.intercept('GET', /\/api\/v1\/files.*attachable_type=SupplyChain(%3A%3A|::)Attestation/i, {
    statusCode: 200,
    body: { success: true, data: { files: mockAttestationFiles, pagination: { current_page: 1, per_page: 20, total_pages: 1, total_count: 2 } } },
  }).as('getAttestationFiles');

  // Files API - Get files for ContainerImage (handles URL-encoded colons %3A%3A)
  cy.intercept('GET', /\/api\/v1\/files.*attachable_type=SupplyChain(%3A%3A|::)ContainerImage/i, {
    statusCode: 200,
    body: { success: true, data: { files: mockContainerScanFiles, pagination: { current_page: 1, per_page: 20, total_pages: 1, total_count: 2 } } },
  }).as('getContainerImageFiles');

  // Files API - Upload file
  cy.intercept('POST', '**/api/v1/files/upload', {
    statusCode: 201,
    body: { success: true, data: { file: createMockFileObject({ id: 'file-new-upload' }) } },
  }).as('uploadFile');

  // Files API - Download file
  cy.intercept('GET', /\/api\/v1\/files\/[^\/]+\/download/, {
    statusCode: 200,
    body: { success: true, data: { download_url: 'https://storage.example.com/presigned-url' } },
  }).as('getFileDownloadUrl');

  // Files API - Delete file
  cy.intercept('DELETE', /\/api\/v1\/files\/[^\/]+$/, {
    statusCode: 200,
    body: { success: true, data: null },
  }).as('deleteFile');

  // Files API - Get single file info
  cy.intercept('GET', /\/api\/v1\/files\/[^\/]+$/, {
    statusCode: 200,
    body: { success: true, data: { file: createMockFileObject() } },
  }).as('getFileInfo');
});

// Navigate to supply chain page
Cypress.Commands.add('visitSupplyChainPage', (page: string) => {
  const pages: Record<string, string> = {
    dashboard: '/app/supply-chain',
    sboms: '/app/supply-chain/sboms',
    containers: '/app/supply-chain/containers',
    attestations: '/app/supply-chain/attestations',
    vendors: '/app/supply-chain/vendors',
    'vendor-risk': '/app/supply-chain/vendors/risk-dashboard',
    'license-policies': '/app/supply-chain/licenses/policies',
    'license-violations': '/app/supply-chain/licenses/violations',
  };

  const url = pages[page] || `/app/supply-chain/${page}`;
  cy.visit(url);
  cy.waitForPageLoad();
});

// Assert supply chain stat card
Cypress.Commands.add('assertSupplyChainStatCard', (label: string, value?: string) => {
  cy.get('body').should('contain.text', label);
  if (value) {
    cy.get('body').should('contain.text', value);
  }
});

export {};

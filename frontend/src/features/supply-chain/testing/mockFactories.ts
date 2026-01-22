/**
 * Supply Chain Feature Test Utilities
 *
 * Mock factories and helper utilities for supply chain feature tests.
 * Provides consistent test data creation with sensible defaults and override support.
 */

import type {
  Sbom,
  SbomComponent,
  SbomVulnerability,
  SbomFormat,
  SbomStatus,
  DependencyType,
  RemediationStatus,
  Severity as SbomSeverity,
  SbomDetail,
} from '../types/sbom';

import type {
  Attestation,
  AttestationType,
  SlsaLevel,
  VerificationStatus,
  BuildProvenance,
  SigningKey,
  AttestationDetail,
} from '../types/attestation';

import type {
  ContainerImage,
  ContainerStatus,
  ImagePolicy,
  PolicyType,
  EnforcementLevel,
  Severity as ContainerSeverity,
  VulnerabilityScan,
  ContainerImageDetail,
} from '../types/container';

import type {
  Vendor,
  VendorType,
  RiskTier,
  VendorStatus,
  RiskAssessment,
  AssessmentType,
  AssessmentStatus,
  Questionnaire,
  VendorDetail,
} from '../types/vendor';

import type {
  License,
  LicensePolicy,
  LicensePolicyType,
  LicenseViolation,
  ViolationType,
  Severity as LicenseSeverity,
  LicenseCategory,
} from '../types/license';

import type {
  Alert,
  ActivityItem,
  SupplyChainDashboard,
  Pagination,
  ApiResponse,
  PaginatedResponse,
} from '../types/dashboard';

// ============================================================================
// SBOM Factories
// ============================================================================

/**
 * Creates a mock SBOM with sensible defaults
 */
export const createMockSbom = (overrides: Partial<Sbom> = {}): Sbom => ({
  id: 'sbom-' + Math.random().toString(36).substr(2, 9),
  sbom_id: 'SBOM-' + Date.now(),
  name: 'Test SBOM',
  format: 'cyclonedx_1_5' as SbomFormat,
  version: '1.0.0',
  status: 'completed' as SbomStatus,
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

/**
 * Creates a mock SBOM component
 */
export const createMockSbomComponent = (
  overrides: Partial<SbomComponent> = {}
): SbomComponent => ({
  id: 'component-' + Math.random().toString(36).substr(2, 9),
  purl: 'pkg:npm/lodash@4.17.21',
  name: 'lodash',
  version: '4.17.21',
  ecosystem: 'npm',
  dependency_type: 'direct' as DependencyType,
  depth: 0,
  risk_score: 25,
  has_known_vulnerabilities: false,
  license_id: 'license-123',
  ...overrides,
});

/**
 * Creates a mock SBOM vulnerability
 */
export const createMockSbomVulnerability = (
  overrides: Partial<SbomVulnerability> = {}
): SbomVulnerability => ({
  id: 'vuln-' + Math.random().toString(36).substr(2, 9),
  vulnerability_id: 'CVE-2024-12345',
  severity: 'high' as SbomSeverity,
  cvss_score: 7.5,
  cvss_vector: 'CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:N/A:N',
  remediation_status: 'open' as RemediationStatus,
  fixed_version: '4.17.22',
  component: {
    name: 'lodash',
    version: '4.17.21',
  },
  ...overrides,
});

/**
 * Creates a mock SBOM detail with components and vulnerabilities
 */
export const createMockSbomDetail = (
  overrides: Partial<SbomDetail> = {}
): SbomDetail => ({
  ...createMockSbom(),
  components: [
    createMockSbomComponent(),
    createMockSbomComponent({ name: 'express', version: '4.18.2' }),
  ],
  vulnerabilities: [createMockSbomVulnerability()],
  repository: {
    id: 'repo-123',
    name: 'my-repo',
    full_name: 'org/my-repo',
  },
  ...overrides,
});

// ============================================================================
// Container Image Factories
// ============================================================================

/**
 * Creates a mock container image
 */
export const createMockContainerImage = (
  overrides: Partial<ContainerImage> = {}
): ContainerImage => ({
  id: 'image-' + Math.random().toString(36).substr(2, 9),
  registry: 'ghcr.io',
  repository: 'org/app',
  tag: 'latest',
  digest: 'sha256:' + 'a'.repeat(64),
  status: 'verified' as ContainerStatus,
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

/**
 * Creates a mock image policy
 */
export const createMockImagePolicy = (
  overrides: Partial<ImagePolicy> = {}
): ImagePolicy => ({
  id: 'policy-' + Math.random().toString(36).substr(2, 9),
  name: 'Production Policy',
  policy_type: 'vulnerability_threshold' as PolicyType,
  enforcement_level: 'block' as EnforcementLevel,
  is_active: true,
  configuration: {
    max_critical: 0,
    max_high: 5,
    max_medium: 20,
  },
  created_at: new Date(Date.now() - 2592000000).toISOString(),
  ...overrides,
});

/**
 * Creates a mock vulnerability scan
 */
export const createMockVulnerabilityScan = (
  overrides: Partial<VulnerabilityScan> = {}
): VulnerabilityScan => ({
  id: 'scan-' + Math.random().toString(36).substr(2, 9),
  container_image_id: 'image-123',
  scanner: 'trivy',
  status: 'completed',
  critical_count: 0,
  high_count: 2,
  medium_count: 5,
  low_count: 10,
  started_at: new Date(Date.now() - 600000).toISOString(),
  completed_at: new Date().toISOString(),
  created_at: new Date().toISOString(),
  ...overrides,
});

/**
 * Creates a mock container image detail with scans and policies
 */
export const createMockContainerImageDetail = (
  overrides: Partial<ContainerImageDetail> = {}
): ContainerImageDetail => ({
  ...createMockContainerImage(),
  scans: [createMockVulnerabilityScan()],
  applicable_policies: [createMockImagePolicy()],
  sbom: {
    id: 'sbom-123',
    name: 'App SBOM',
  },
  ...overrides,
});

// ============================================================================
// Attestation Factories
// ============================================================================

/**
 * Creates a mock attestation
 */
export const createMockAttestation = (
  overrides: Partial<Attestation> = {}
): Attestation => ({
  id: 'att-' + Math.random().toString(36).substr(2, 9),
  attestation_id: 'ATT-' + Date.now(),
  attestation_type: 'slsa_provenance' as AttestationType,
  slsa_level: 3 as SlsaLevel,
  subject_name: 'app:latest',
  subject_digest: 'sha256:' + 'b'.repeat(64),
  verification_status: 'verified' as VerificationStatus,
  signed: true,
  rekor_logged: true,
  created_at: new Date(Date.now() - 3600000).toISOString(),
  updated_at: new Date().toISOString(),
  ...overrides,
});

/**
 * Creates a mock build provenance
 */
export const createMockBuildProvenance = (
  overrides: Partial<BuildProvenance> = {}
): BuildProvenance => ({
  id: 'prov-' + Math.random().toString(36).substr(2, 9),
  builder_id: 'https://github.com/actions',
  build_type: 'https://github.com/Attestations/GitHubActionsWorkflow@v1',
  invocation: {
    github_actor: 'test-user',
    github_event: 'push',
    github_ref: 'refs/heads/main',
  },
  materials: [
    {
      uri: 'git+https://github.com/org/repo@main',
      digest: {
        gitCommit: 'abc123def456',
      },
    },
  ],
  metadata: {
    completeness: { parameters: true, materials: true, environment: true },
    reproducibility: true,
  },
  ...overrides,
});

/**
 * Creates a mock signing key
 */
export const createMockSigningKey = (
  overrides: Partial<SigningKey> = {}
): SigningKey => ({
  id: 'key-' + Math.random().toString(36).substr(2, 9),
  name: 'Production Key',
  key_type: 'cosign',
  public_key: '-----BEGIN PUBLIC KEY-----\n...\n-----END PUBLIC KEY-----',
  is_default: true,
  expires_at: new Date(Date.now() + 31536000000).toISOString(),
  created_at: new Date(Date.now() - 31536000000).toISOString(),
  ...overrides,
});

/**
 * Creates a mock attestation detail with provenance
 */
export const createMockAttestationDetail = (
  overrides: Partial<AttestationDetail> = {}
): AttestationDetail => ({
  ...createMockAttestation(),
  build_provenance: createMockBuildProvenance(),
  signing_key: createMockSigningKey(),
  verification_logs: [
    {
      verified_at: new Date().toISOString(),
      status: 'verified' as VerificationStatus,
      message: 'Signature verified successfully',
    },
  ],
  ...overrides,
});

// ============================================================================
// Vendor Factories
// ============================================================================

/**
 * Creates a mock vendor
 */
export const createMockVendor = (overrides: Partial<Vendor> = {}): Vendor => ({
  id: 'vendor-' + Math.random().toString(36).substr(2, 9),
  name: 'Test Vendor Inc',
  vendor_type: 'saas' as VendorType,
  risk_tier: 'medium' as RiskTier,
  risk_score: 35,
  status: 'active' as VendorStatus,
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

/**
 * Creates a mock risk assessment
 */
export const createMockRiskAssessment = (
  overrides: Partial<RiskAssessment> = {}
): RiskAssessment => ({
  id: 'assess-' + Math.random().toString(36).substr(2, 9),
  vendor_id: 'vendor-123',
  assessment_type: 'periodic' as AssessmentType,
  status: 'completed' as AssessmentStatus,
  security_score: 78,
  compliance_score: 82,
  operational_score: 75,
  overall_score: 78,
  finding_count: 3,
  valid_until: new Date(Date.now() + 31536000000).toISOString(),
  completed_at: new Date(Date.now() - 604800000).toISOString(),
  created_at: new Date(Date.now() - 604800000).toISOString(),
  ...overrides,
});

/**
 * Creates a mock questionnaire
 */
export const createMockQuestionnaire = (
  overrides: Partial<Questionnaire> = {}
): Questionnaire => ({
  id: 'quest-' + Math.random().toString(36).substr(2, 9),
  vendor_id: 'vendor-123',
  template_name: 'Security Assessment Q1 2024',
  status: 'completed',
  sent_at: new Date(Date.now() - 1209600000).toISOString(),
  completed_at: new Date(Date.now() - 604800000).toISOString(),
  response_count: 45,
  total_questions: 50,
  created_at: new Date(Date.now() - 1209600000).toISOString(),
  ...overrides,
});

/**
 * Creates a mock vendor detail with assessments
 */
export const createMockVendorDetail = (
  overrides: Partial<VendorDetail> = {}
): VendorDetail => ({
  ...createMockVendor(),
  assessments: [createMockRiskAssessment()],
  questionnaires: [createMockQuestionnaire()],
  monitoring_events: [
    {
      id: 'event-1',
      event_type: 'security_incident',
      severity: 'high',
      message: 'Vendor reported security incident',
      created_at: new Date(Date.now() - 86400000).toISOString(),
    },
  ],
  ...overrides,
});

// ============================================================================
// License Factories
// ============================================================================

/**
 * Creates a mock license
 */
export const createMockLicense = (overrides: Partial<License> = {}): License => ({
  id: 'license-' + Math.random().toString(36).substr(2, 9),
  spdx_id: 'MIT',
  name: 'MIT License',
  category: 'permissive' as LicenseCategory,
  is_osi_approved: true,
  is_fsf_libre: true,
  is_copyleft: false,
  ...overrides,
});

/**
 * Creates a mock license policy
 */
export const createMockLicensePolicy = (
  overrides: Partial<LicensePolicy> = {}
): LicensePolicy => ({
  id: 'lp-' + Math.random().toString(36).substr(2, 9),
  name: 'Production License Policy',
  policy_type: 'allowlist' as LicensePolicyType,
  enforcement_level: 'block' as EnforcementLevel,
  is_active: true,
  block_copyleft: true,
  block_strong_copyleft: true,
  allowed_licenses: ['MIT', 'Apache-2.0', 'BSD-3-Clause'],
  denied_licenses: ['AGPL-3.0', 'GPL-3.0'],
  created_at: new Date(Date.now() - 2592000000).toISOString(),
  updated_at: new Date().toISOString(),
  ...overrides,
});

/**
 * Creates a mock license violation
 */
export const createMockLicenseViolation = (
  overrides: Partial<LicenseViolation> = {}
): LicenseViolation => ({
  id: 'viol-' + Math.random().toString(36).substr(2, 9),
  component_name: 'copyleft-lib',
  component_version: '1.2.3',
  license_name: 'GPL-3.0',
  license_spdx_id: 'GPL-3.0-only',
  violation_type: 'copyleft_contamination' as ViolationType,
  severity: 'high' as LicenseSeverity,
  status: 'open',
  sbom_id: 'sbom-123',
  policy_id: 'policy-456',
  resolution_note: undefined,
  resolved_at: undefined,
  created_at: new Date().toISOString(),
  ...overrides,
});

// ============================================================================
// Dashboard Factories
// ============================================================================

/**
 * Creates a mock alert
 */
export const createMockAlert = (overrides: Partial<Alert> = {}): Alert => ({
  id: 'alert-' + Math.random().toString(36).substr(2, 9),
  type: 'vulnerability',
  severity: 'high' as SbomSeverity,
  title: 'Critical Vulnerability Detected',
  message: 'A critical vulnerability was found in a deployed component',
  entity_id: 'component-123',
  entity_type: 'component',
  created_at: new Date().toISOString(),
  ...overrides,
});

/**
 * Creates a mock activity item
 */
export const createMockActivityItem = (
  overrides: Partial<ActivityItem> = {}
): ActivityItem => ({
  id: 'activity-' + Math.random().toString(36).substr(2, 9),
  action: 'created',
  entity_type: 'sbom',
  entity_name: 'Production App',
  user_name: 'test-user',
  details: 'SBOM generated from Docker image scan',
  created_at: new Date().toISOString(),
  ...overrides,
});

/**
 * Creates a mock pagination object
 */
export const createMockPagination = (
  overrides: Partial<Pagination> = {}
): Pagination => ({
  current_page: 1,
  per_page: 20,
  total_pages: 5,
  total_count: 100,
  ...overrides,
});

/**
 * Creates a mock supply chain dashboard (matches API response structure)
 */
export const createMockDashboardData = (overrides: Partial<any> = {}): any => ({
  sbom_count: 15,
  vulnerability_count: 42,
  critical_vulnerabilities: 2,
  high_vulnerabilities: 8,
  container_image_count: 25,
  quarantined_images: 1,
  verified_images: 20,
  attestation_count: 18,
  verified_attestations: 16,
  vendor_count: 12,
  high_risk_vendors: 2,
  vendors_needing_assessment: 3,
  license_violation_count: 5,
  open_violations: 3,
  ntia_compliant_sboms: 10,
  sboms_with_vulnerabilities: 5,
  open_vulnerabilities: 3,
  active_vendors: 10,
  signed_attestations: 15,
  sboms_this_month: 3,
  scans_this_month: 5,
  attestations_this_month: 2,
  average_risk_score: 45.5,
  alerts: [
    {
      severity: 'critical',
      type: 'vulnerability',
      message: 'Critical vulnerability detected',
      action_url: '/supply-chain/sboms',
    },
    {
      severity: 'high',
      type: 'license',
      message: 'License violation found',
      action_url: '/supply-chain/license-violations',
    },
  ],
  recent_activity: [
    {
      type: 'sbom_created',
      title: 'SBOM generated for app:latest',
      timestamp: new Date().toISOString(),
      details: {},
    },
    {
      type: 'scan_completed',
      title: 'Container scan completed',
      timestamp: new Date(Date.now() - 3600000).toISOString(),
      details: { image: 'app:latest' },
    },
  ],
  ...overrides,
});

// ============================================================================
// API Response Helpers
// ============================================================================

/**
 * Creates a mock API success response
 */
export const createMockApiResponse = <T>(data: T): ApiResponse<T> => ({
  success: true,
  data,
});

/**
 * Creates a mock API error response
 */
export const createMockApiErrorResponse = (error: string): ApiResponse<never> => ({
  success: false,
  error,
});

/**
 * Creates a mock paginated API response
 */
export const createMockPaginatedResponse = <T>(
  items: T[],
  pagination: Partial<Pagination> = {}
): PaginatedResponse<T> => ({
  success: true,
  data: {
    items,
    pagination: createMockPagination(pagination),
  },
});

// ============================================================================
// Batch Factory Helpers
// ============================================================================

/**
 * Creates multiple mock SBOMs
 */
export const createMockSbomList = (
  count: number = 5,
  overrides: Partial<Sbom> = {}
): Sbom[] => Array.from({ length: count }, () => createMockSbom(overrides));

/**
 * Creates multiple mock container images
 */
export const createMockContainerImageList = (
  count: number = 5,
  overrides: Partial<ContainerImage> = {}
): ContainerImage[] =>
  Array.from({ length: count }, () => createMockContainerImage(overrides));

/**
 * Creates multiple mock vendors
 */
export const createMockVendorList = (
  count: number = 5,
  overrides: Partial<Vendor> = {}
): Vendor[] => Array.from({ length: count }, () => createMockVendor(overrides));

/**
 * Creates multiple mock attestations
 */
export const createMockAttestationList = (
  count: number = 5,
  overrides: Partial<Attestation> = {}
): Attestation[] => Array.from({ length: count }, () => createMockAttestation(overrides));

/**
 * Creates multiple mock license violations
 */
export const createMockLicenseViolationList = (
  count: number = 5,
  overrides: Partial<LicenseViolation> = {}
): LicenseViolation[] =>
  Array.from({ length: count }, () => createMockLicenseViolation(overrides));

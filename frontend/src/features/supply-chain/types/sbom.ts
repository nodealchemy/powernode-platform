/**
 * Software Bill of Materials (SBOM) Types
 *
 * Types for managing SBOMs, components, and vulnerabilities
 */

/** SBOM format types */
export type SbomFormat = 'cyclonedx_1_4' | 'cyclonedx_1_5' | 'spdx_2_3';

/** SBOM generation and processing status */
export type SbomStatus = 'draft' | 'generating' | 'completed' | 'failed';

/** Type of dependency relationship */
export type DependencyType = 'direct' | 'transitive' | 'dev';

/** Vulnerability remediation status */
export type RemediationStatus = 'open' | 'in_progress' | 'fixed' | 'wont_fix';

/** Vulnerability severity levels */
export type Severity = 'critical' | 'high' | 'medium' | 'low';

/**
 * Software Bill of Materials
 * Core SBOM metadata and summary information
 */
export interface Sbom {
  id: string;
  sbom_id: string;
  name: string;
  format: SbomFormat;
  version: string;
  status: SbomStatus;
  component_count: number;
  vulnerability_count: number;
  risk_score: number;
  ntia_minimum_compliant: boolean;
  commit_sha?: string;
  branch?: string;
  repository_id?: string;
  created_at: string;
  updated_at: string;
}

/**
 * SBOM Component
 * Represents a single dependency or component in an SBOM
 */
export interface SbomComponent {
  id: string;
  purl: string;
  name: string;
  version: string;
  ecosystem: string;
  dependency_type: DependencyType;
  depth: number;
  risk_score: number;
  has_known_vulnerabilities: boolean;
  license_id?: string;
}

/**
 * SBOM Vulnerability
 * Vulnerability information for a component
 */
export interface SbomVulnerability {
  id: string;
  vulnerability_id: string;
  severity: Severity;
  cvss_score: number;
  cvss_vector?: string;
  remediation_status: RemediationStatus;
  fixed_version?: string;
  component: { name: string; version: string };
}

/**
 * SBOM Detail
 * Extended SBOM information with nested components and vulnerabilities
 */
export interface SbomDetail extends Sbom {
  components?: SbomComponent[];
  vulnerabilities?: SbomVulnerability[];
  repository?: { id: string; name: string; full_name: string };
}

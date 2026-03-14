/**
 * Container Image Security Types
 *
 * Types for container image scanning, policies, and verification
 */

/** Container image verification status */
export type ContainerStatus = 'unverified' | 'verified' | 'quarantined';

/** Type of container security policy */
export type PolicyType = 'registry_allowlist' | 'signature_required' | 'vulnerability_threshold' | 'base_image' | 'custom';

/** Policy enforcement level */
export type EnforcementLevel = 'log' | 'warn' | 'block';

/** Vulnerability severity levels */
export type Severity = 'critical' | 'high' | 'medium' | 'low';

/**
 * Container Image
 * Container image metadata with vulnerability summary
 */
export interface ContainerImage {
  id: string;
  registry: string;
  repository: string;
  tag: string;
  digest: string;
  status: ContainerStatus;
  critical_vuln_count: number;
  high_vuln_count: number;
  medium_vuln_count: number;
  low_vuln_count: number;
  is_deployed: boolean;
  last_scanned_at?: string;
  created_at: string;
  updated_at: string;
}

/**
 * Image Policy
 * Security policy for container images
 */
export interface ImagePolicy {
  id: string;
  name: string;
  policy_type: PolicyType;
  enforcement_level: EnforcementLevel;
  is_active: boolean;
  configuration: Record<string, unknown>;
  created_at: string;
}

/**
 * Vulnerability Scan
 * Container image vulnerability scan results
 */
export interface VulnerabilityScan {
  id: string;
  container_image_id: string;
  scanner: string;
  status: 'pending' | 'running' | 'completed' | 'failed';
  critical_count: number;
  high_count: number;
  medium_count: number;
  low_count: number;
  started_at?: string;
  completed_at?: string;
  created_at: string;
}

/**
 * Container Image Detail
 * Extended container image information with scans and policies
 */
export interface ContainerImageDetail extends ContainerImage {
  scans?: VulnerabilityScan[];
  applicable_policies?: ImagePolicy[];
  sbom?: { id: string; name: string };
}

/**
 * License Compliance Types
 *
 * Types for software license management and compliance
 */

/** License category classification */
export type LicenseCategory = 'permissive' | 'copyleft' | 'weak_copyleft' | 'public_domain' | 'proprietary' | 'unknown';

/** Type of license policy */
export type LicensePolicyType = 'allowlist' | 'denylist' | 'hybrid';

/** Policy enforcement level */
export type EnforcementLevel = 'log' | 'warn' | 'block';

/** Type of license violation */
export type ViolationType = 'denied' | 'copyleft_contamination' | 'incompatible' | 'unknown_license';

/** Violation severity */
export type Severity = 'critical' | 'high' | 'medium' | 'low';

/**
 * License
 * Software license metadata
 */
export interface License {
  id: string;
  spdx_id: string;
  name: string;
  category: LicenseCategory;
  is_osi_approved: boolean;
  is_fsf_libre: boolean;
  is_copyleft: boolean;
}

/**
 * License Policy
 * Organizational license compliance policy
 */
export interface LicensePolicy {
  id: string;
  name: string;
  description?: string;
  policy_type: LicensePolicyType;
  enforcement_level: EnforcementLevel;
  is_active: boolean;
  is_default?: boolean;
  priority?: number;
  block_copyleft: boolean;
  block_strong_copyleft: boolean;
  block_network_copyleft?: boolean;
  block_unknown?: boolean;
  require_osi_approved?: boolean;
  require_attribution?: boolean;
  allowed_licenses?: string[];
  denied_licenses?: string[];
  exception_packages?: Array<{
    package: string;
    license: string;
    reason: string;
    added_at: string;
    expires_at?: string;
  }>;
  metadata?: Record<string, unknown>;
  violation_count?: number;
  created_at: string;
  updated_at: string;
}

/**
 * License Violation
 * Detected license compliance violation
 */
export interface LicenseViolation {
  id: string;
  component_name: string;
  component_version: string;
  license_name: string;
  license_spdx_id?: string;
  violation_type: ViolationType;
  severity: Severity;
  status: 'open' | 'resolved' | 'exception_granted';
  sbom_id?: string;
  policy_id?: string;
  resolution_note?: string;
  resolved_at?: string;
  created_at: string;
}

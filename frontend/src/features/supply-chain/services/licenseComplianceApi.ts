import { apiClient } from '@/shared/services/apiClient';

interface ApiResponse<T> {
  success: boolean;
  data: T;
}

interface Pagination {
  current_page: number;
  per_page: number;
  total_pages: number;
  total_count: number;
}

type LicensePolicyType = 'allowlist' | 'denylist' | 'hybrid';
type EnforcementLevel = 'log' | 'warn' | 'block';
type ViolationType = 'denied' | 'copyleft_contamination' | 'incompatible' | 'unknown_license';
type Severity = 'critical' | 'high' | 'medium' | 'low';

interface LicensePolicy {
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

interface CreateLicensePolicyData {
  name: string;
  description?: string;
  policy_type: LicensePolicyType;
  enforcement_level: EnforcementLevel;
  is_active?: boolean;
  block_copyleft?: boolean;
  block_strong_copyleft?: boolean;
  block_network_copyleft?: boolean;
  block_unknown?: boolean;
  require_osi_approved?: boolean;
  require_attribution?: boolean;
  allowed_licenses?: string[];
  denied_licenses?: string[];
}

interface LicenseViolation {
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

export const licenseComplianceApi = {
  listPolicies: async (params?: {
    page?: number;
    per_page?: number;
    is_active?: boolean;
    policy_type?: LicensePolicyType;
  }): Promise<{ policies: LicensePolicy[]; pagination: Pagination }> => {
    const response = await apiClient.get<ApiResponse<{
      license_policies: LicensePolicy[];
      meta: Pagination;
    }>>('/supply_chain/license_policies', { params });
    return { policies: response.data.data.license_policies, pagination: response.data.data.meta };
  },

  getPolicy: async (id: string): Promise<LicensePolicy> => {
    const response = await apiClient.get<ApiResponse<{
      license_policy: LicensePolicy;
    }>>(`/supply_chain/license_policies/${id}`);
    return response.data.data.license_policy;
  },

  createPolicy: async (data: CreateLicensePolicyData): Promise<LicensePolicy> => {
    const response = await apiClient.post<ApiResponse<{
      license_policy: LicensePolicy;
    }>>('/supply_chain/license_policies', { license_policy: data });
    return response.data.data.license_policy;
  },

  updatePolicy: async (id: string, data: Partial<CreateLicensePolicyData>): Promise<LicensePolicy> => {
    const response = await apiClient.patch<ApiResponse<{
      license_policy: LicensePolicy;
    }>>(`/supply_chain/license_policies/${id}`, { license_policy: data });
    return response.data.data.license_policy;
  },

  deletePolicy: async (id: string): Promise<void> => {
    await apiClient.delete(`/supply_chain/license_policies/${id}`);
  },

  togglePolicyActive: async (id: string, isActive: boolean): Promise<LicensePolicy> => {
    const response = await apiClient.patch<ApiResponse<{
      license_policy: LicensePolicy;
    }>>(`/supply_chain/license_policies/${id}`, { license_policy: { is_active: isActive } });
    return response.data.data.license_policy;
  },

  listViolations: async (params?: {
    page?: number;
    per_page?: number;
    status?: 'open' | 'resolved' | 'exception_granted';
    severity?: Severity;
    violation_type?: ViolationType;
  }): Promise<{ violations: LicenseViolation[]; pagination: Pagination }> => {
    const response = await apiClient.get<ApiResponse<{
      violations: LicenseViolation[];
      pagination: Pagination;
    }>>('/supply_chain/license_violations', { params });
    return response.data.data;
  },

  getViolation: async (id: string): Promise<LicenseViolation> => {
    const response = await apiClient.get<ApiResponse<{
      violation: LicenseViolation;
    }>>(`/supply_chain/license_violations/${id}`);
    return response.data.data.violation;
  },

  resolveViolation: async (id: string, note?: string): Promise<LicenseViolation> => {
    const response = await apiClient.post<ApiResponse<{
      violation: LicenseViolation;
    }>>(`/supply_chain/license_violations/${id}/resolve`, { resolution_note: note });
    return response.data.data.violation;
  },

  grantException: async (id: string, note: string): Promise<LicenseViolation> => {
    const response = await apiClient.post<ApiResponse<{
      violation: LicenseViolation;
    }>>(`/supply_chain/license_violations/${id}/grant_exception`, { note });
    return response.data.data.violation;
  },

  // Exception workflow methods
  requestException: async (
    id: string,
    justification: string,
    expiresAt?: string
  ): Promise<LicenseViolation> => {
    const response = await apiClient.post<ApiResponse<{
      violation: LicenseViolation;
    }>>(`/supply_chain/license_violations/${id}/request_exception`, {
      justification,
      expires_at: expiresAt,
    });
    return response.data.data.violation;
  },

  approveException: async (
    id: string,
    notes?: string,
    expiresAt?: string
  ): Promise<LicenseViolation> => {
    const response = await apiClient.post<ApiResponse<{
      violation: LicenseViolation;
    }>>(`/supply_chain/license_violations/${id}/approve_exception`, {
      notes,
      expires_at: expiresAt,
    });
    return response.data.data.violation;
  },

  rejectException: async (id: string, reason?: string): Promise<LicenseViolation> => {
    const response = await apiClient.post<ApiResponse<{
      violation: LicenseViolation;
    }>>(`/supply_chain/license_violations/${id}/reject_exception`, { reason });
    return response.data.data.violation;
  },
};

export type {
  LicensePolicy,
  LicenseViolation,
  LicensePolicyType,
  EnforcementLevel,
  ViolationType,
  Severity,
  Pagination,
  CreateLicensePolicyData,
};

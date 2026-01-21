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
  policy_type: LicensePolicyType;
  enforcement_level: EnforcementLevel;
  is_active: boolean;
  block_copyleft: boolean;
  block_strong_copyleft: boolean;
  allowed_licenses?: string[];
  denied_licenses?: string[];
  created_at: string;
  updated_at: string;
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
      policies: LicensePolicy[];
      pagination: Pagination;
    }>>('/supply_chain/license_policies', { params });
    return response.data.data;
  },

  getPolicy: async (id: string): Promise<LicensePolicy> => {
    const response = await apiClient.get<ApiResponse<{
      policy: LicensePolicy;
    }>>(`/supply_chain/license_policies/${id}`);
    return response.data.data.policy;
  },

  createPolicy: async (data: {
    name: string;
    policy_type: LicensePolicyType;
    enforcement_level: EnforcementLevel;
    block_copyleft?: boolean;
    block_strong_copyleft?: boolean;
    allowed_licenses?: string[];
    denied_licenses?: string[];
  }): Promise<LicensePolicy> => {
    const response = await apiClient.post<ApiResponse<{
      policy: LicensePolicy;
    }>>('/supply_chain/license_policies', { policy: data });
    return response.data.data.policy;
  },

  updatePolicy: async (id: string, data: Partial<LicensePolicy>): Promise<LicensePolicy> => {
    const response = await apiClient.patch<ApiResponse<{
      policy: LicensePolicy;
    }>>(`/supply_chain/license_policies/${id}`, { policy: data });
    return response.data.data.policy;
  },

  deletePolicy: async (id: string): Promise<void> => {
    await apiClient.delete(`/supply_chain/license_policies/${id}`);
  },

  togglePolicyActive: async (id: string, isActive: boolean): Promise<LicensePolicy> => {
    const response = await apiClient.patch<ApiResponse<{
      policy: LicensePolicy;
    }>>(`/supply_chain/license_policies/${id}`, { policy: { is_active: isActive } });
    return response.data.data.policy;
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
};

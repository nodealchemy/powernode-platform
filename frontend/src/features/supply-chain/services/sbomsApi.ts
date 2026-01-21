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

type SbomFormat = 'cyclonedx_1_4' | 'cyclonedx_1_5' | 'spdx_2_3';
type SbomStatus = 'draft' | 'generating' | 'completed' | 'failed';
type DependencyType = 'direct' | 'transitive' | 'dev';
type RemediationStatus = 'open' | 'in_progress' | 'fixed' | 'wont_fix';
type Severity = 'critical' | 'high' | 'medium' | 'low';

interface Sbom {
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

interface SbomComponent {
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

interface SbomVulnerability {
  id: string;
  vulnerability_id: string;
  severity: Severity;
  cvss_score: number;
  cvss_vector?: string;
  remediation_status: RemediationStatus;
  fixed_version?: string;
  component: { name: string; version: string };
}

interface SbomDetail extends Sbom {
  components?: SbomComponent[];
  vulnerabilities?: SbomVulnerability[];
  repository?: { id: string; name: string; full_name: string };
}

interface CreateSbomRequest {
  name: string;
  format: SbomFormat;
  repository_id?: string;
  commit_sha?: string;
  branch?: string;
}

export const sbomsApi = {
  list: async (params?: {
    page?: number;
    per_page?: number;
    status?: SbomStatus;
    format?: SbomFormat;
    search?: string;
  }): Promise<{ sboms: Sbom[]; pagination: Pagination }> => {
    const response = await apiClient.get<ApiResponse<{
      sboms: Sbom[];
      pagination: Pagination;
    }>>('/supply_chain/sboms', { params });
    return response.data.data;
  },

  get: async (id: string): Promise<SbomDetail> => {
    const response = await apiClient.get<ApiResponse<{
      sbom: SbomDetail;
    }>>(`/supply_chain/sboms/${id}`);
    return response.data.data.sbom;
  },

  create: async (data: CreateSbomRequest): Promise<Sbom> => {
    const response = await apiClient.post<ApiResponse<{
      sbom: Sbom;
    }>>('/supply_chain/sboms', { sbom: data });
    return response.data.data.sbom;
  },

  delete: async (id: string): Promise<void> => {
    await apiClient.delete(`/supply_chain/sboms/${id}`);
  },

  getComponents: async (id: string, params?: {
    page?: number;
    per_page?: number;
    ecosystem?: string;
    dependency_type?: DependencyType;
  }): Promise<{ components: SbomComponent[]; pagination: Pagination }> => {
    const response = await apiClient.get<ApiResponse<{
      components: SbomComponent[];
      pagination: Pagination;
    }>>(`/supply_chain/sboms/${id}/components`, { params });
    return response.data.data;
  },

  getVulnerabilities: async (id: string, params?: {
    page?: number;
    per_page?: number;
    severity?: Severity;
    status?: RemediationStatus;
  }): Promise<{ vulnerabilities: SbomVulnerability[]; pagination: Pagination }> => {
    const response = await apiClient.get<ApiResponse<{
      vulnerabilities: SbomVulnerability[];
      pagination: Pagination;
    }>>(`/supply_chain/sboms/${id}/vulnerabilities`, { params });
    return response.data.data;
  },

  export: async (id: string, format: 'json' | 'xml'): Promise<Blob> => {
    const response = await apiClient.post(`/supply_chain/sboms/${id}/export`, { format }, {
      responseType: 'blob'
    });
    return response.data;
  },

  rescan: async (id: string): Promise<Sbom> => {
    const response = await apiClient.post<ApiResponse<{
      sbom: Sbom;
    }>>(`/supply_chain/sboms/${id}/rescan`);
    return response.data.data.sbom;
  },
};

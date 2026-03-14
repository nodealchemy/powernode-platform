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

type ContainerStatus = 'unverified' | 'verified' | 'quarantined';

interface ContainerImage {
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

interface ContainerImageDetail extends ContainerImage {
  scans?: Array<{
    id: string;
    scanner: string;
    status: string;
    critical_count: number;
    high_count: number;
    medium_count: number;
    low_count: number;
    started_at?: string;
    completed_at?: string;
  }>;
  applicable_policies?: Array<{
    id: string;
    name: string;
    policy_type: string;
    enforcement_level: string;
    is_active: boolean;
  }>;
}

export const containerImagesApi = {
  list: async (params?: {
    page?: number;
    per_page?: number;
    status?: ContainerStatus;
    registry?: string;
    is_deployed?: boolean;
  }): Promise<{ images: ContainerImage[]; pagination: Pagination }> => {
    const response = await apiClient.get<ApiResponse<{
      images: ContainerImage[];
      pagination: Pagination;
    }>>('/supply_chain/container_images', { params });
    return response.data.data;
  },

  get: async (id: string): Promise<ContainerImageDetail> => {
    const response = await apiClient.get<ApiResponse<{
      image: ContainerImageDetail;
    }>>(`/supply_chain/container_images/${id}`);
    return response.data.data.image;
  },

  scan: async (id: string): Promise<ContainerImage> => {
    const response = await apiClient.post<ApiResponse<{
      image: ContainerImage;
    }>>(`/supply_chain/container_images/${id}/scan`);
    return response.data.data.image;
  },

  verify: async (id: string): Promise<ContainerImage> => {
    const response = await apiClient.post<ApiResponse<{
      image: ContainerImage;
    }>>(`/supply_chain/container_images/${id}/verify`);
    return response.data.data.image;
  },

  quarantine: async (id: string, reason: string): Promise<ContainerImage> => {
    const response = await apiClient.post<ApiResponse<{
      image: ContainerImage;
    }>>(`/supply_chain/container_images/${id}/quarantine`, { reason });
    return response.data.data.image;
  },

  delete: async (id: string): Promise<void> => {
    await apiClient.delete(`/supply_chain/container_images/${id}`);
  },

  // Vulnerability methods
  getVulnerabilities: async (imageId: string, params?: {
    page?: number;
    per_page?: number;
    severity?: Severity;
  }): Promise<{ vulnerabilities: ContainerVulnerability[]; pagination: Pagination }> => {
    const response = await apiClient.get<ApiResponse<{
      vulnerabilities: ContainerVulnerability[];
      pagination: Pagination;
    }>>(`/supply_chain/container_images/${imageId}/vulnerabilities`, { params });
    return response.data.data;
  },

  // SBOM methods
  getSbom: async (imageId: string): Promise<ContainerSbom> => {
    const response = await apiClient.get<ApiResponse<{
      sbom: ContainerSbom;
    }>>(`/supply_chain/container_images/${imageId}/sbom`);
    return response.data.data.sbom;
  },

  // Policy evaluation
  evaluatePolicies: async (imageId: string): Promise<PolicyEvaluationResult[]> => {
    const response = await apiClient.post<ApiResponse<{
      evaluations: PolicyEvaluationResult[];
    }>>(`/supply_chain/container_images/${imageId}/evaluate_policies`);
    return response.data.data.evaluations;
  },
};

type Severity = 'critical' | 'high' | 'medium' | 'low';

interface ContainerVulnerability {
  id: string;
  vulnerability_id: string;
  severity: Severity;
  cvss_score: number;
  package_name: string;
  package_version: string;
  fixed_version?: string;
  description?: string;
  published_at?: string;
  exploit_available?: boolean;
}

interface ContainerSbom {
  id: string;
  format: string;
  component_count: number;
  components: Array<{
    name: string;
    version: string;
    type: string;
    licenses: string[];
  }>;
  generated_at: string;
}

interface PolicyEvaluationResult {
  policy_id: string;
  policy_name: string;
  policy_type: string;
  enforcement_level: string;
  passed: boolean;
  violations: Array<{
    rule: string;
    message: string;
    severity: Severity;
  }>;
  evaluated_at: string;
}

export type { ContainerImage, ContainerImageDetail, ContainerStatus, Pagination, ContainerVulnerability, ContainerSbom, PolicyEvaluationResult, Severity };

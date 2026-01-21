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

interface VulnerabilityDetail extends SbomVulnerability {
  description?: string;
  references?: string[];
  published_at?: string;
  cwe_ids?: string[];
  epss_score?: number;
  exploit_available?: boolean;
  suppressed?: boolean;
  false_positive?: boolean;
  false_positive_reason?: string;
}

interface ComplianceStatus {
  ntia_minimum_compliant: boolean;
  ntia_fields: {
    supplier_name: boolean;
    component_name: boolean;
    component_version: boolean;
    unique_identifier: boolean;
    dependency_relationship: boolean;
    author: boolean;
    timestamp: boolean;
  };
  completeness_score: number;
  missing_fields: string[];
}

interface RiskCalculation {
  overall_score: number;
  vulnerability_score: number;
  license_score: number;
  dependency_score: number;
  recommendations: string[];
}

interface CorrelationResult {
  correlated_count: number;
  new_vulnerabilities: number;
  resolved_vulnerabilities: number;
  last_correlated_at: string;
}

interface SbomStatistics {
  total_sboms: number;
  sboms_by_status: Record<SbomStatus, number>;
  sboms_by_format: Record<SbomFormat, number>;
  total_components: number;
  total_vulnerabilities: number;
  critical_vulnerabilities: number;
  avg_risk_score: number;
  compliance_rate: number;
}

interface SbomDiff {
  id: string;
  source_sbom_id: string;
  compare_sbom_id: string;
  added_count: number;
  removed_count: number;
  changed_count: number;
  created_at: string;
}

interface SbomDiffDetail extends SbomDiff {
  added_components: Array<{ name: string; version: string; ecosystem: string }>;
  removed_components: Array<{ name: string; version: string; ecosystem: string }>;
  changed_components: Array<{
    name: string;
    old_version: string;
    new_version: string;
    ecosystem: string;
  }>;
  added_vulnerabilities: Array<{ vulnerability_id: string; severity: Severity }>;
  removed_vulnerabilities: Array<{ vulnerability_id: string; severity: Severity }>;
}

type ExportFormat = 'json' | 'xml' | 'pdf' | 'cyclonedx' | 'spdx';

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

  // Vulnerability management methods
  getVulnerability: async (sbomId: string, vulnId: string): Promise<VulnerabilityDetail> => {
    const response = await apiClient.get<ApiResponse<{
      vulnerability: VulnerabilityDetail;
    }>>(`/supply_chain/sboms/${sbomId}/vulnerabilities/${vulnId}`);
    return response.data.data.vulnerability;
  },

  updateVulnerabilityStatus: async (
    sbomId: string,
    vulnId: string,
    status: RemediationStatus
  ): Promise<SbomVulnerability> => {
    const response = await apiClient.patch<ApiResponse<{
      vulnerability: SbomVulnerability;
    }>>(`/supply_chain/sboms/${sbomId}/vulnerabilities/${vulnId}`, { vulnerability: { remediation_status: status } });
    return response.data.data.vulnerability;
  },

  suppressVulnerability: async (sbomId: string, vulnId: string): Promise<SbomVulnerability> => {
    const response = await apiClient.post<ApiResponse<{
      vulnerability: SbomVulnerability;
    }>>(`/supply_chain/sboms/${sbomId}/vulnerabilities/${vulnId}/suppress`);
    return response.data.data.vulnerability;
  },

  unsuppressVulnerability: async (sbomId: string, vulnId: string): Promise<SbomVulnerability> => {
    const response = await apiClient.post<ApiResponse<{
      vulnerability: SbomVulnerability;
    }>>(`/supply_chain/sboms/${sbomId}/vulnerabilities/${vulnId}/unsuppress`);
    return response.data.data.vulnerability;
  },

  markFalsePositive: async (sbomId: string, vulnId: string, reason: string): Promise<SbomVulnerability> => {
    const response = await apiClient.post<ApiResponse<{
      vulnerability: SbomVulnerability;
    }>>(`/supply_chain/sboms/${sbomId}/vulnerabilities/${vulnId}/false_positive`, { reason });
    return response.data.data.vulnerability;
  },

  getComponentVulnerabilities: async (sbomId: string, componentId: string): Promise<SbomVulnerability[]> => {
    const response = await apiClient.get<ApiResponse<{
      vulnerabilities: SbomVulnerability[];
    }>>(`/supply_chain/sboms/${sbomId}/components/${componentId}/vulnerabilities`);
    return response.data.data.vulnerabilities;
  },

  // Compliance and analysis methods
  getComplianceStatus: async (sbomId: string): Promise<ComplianceStatus> => {
    const response = await apiClient.get<ApiResponse<{
      compliance: ComplianceStatus;
    }>>(`/supply_chain/sboms/${sbomId}/compliance`);
    return response.data.data.compliance;
  },

  calculateRisk: async (sbomId: string): Promise<RiskCalculation> => {
    const response = await apiClient.post<ApiResponse<{
      risk: RiskCalculation;
    }>>(`/supply_chain/sboms/${sbomId}/calculate_risk`);
    return response.data.data.risk;
  },

  correlateVulnerabilities: async (sbomId: string): Promise<CorrelationResult> => {
    const response = await apiClient.post<ApiResponse<{
      correlation: CorrelationResult;
    }>>(`/supply_chain/sboms/${sbomId}/correlate_vulnerabilities`);
    return response.data.data.correlation;
  },

  getStatistics: async (): Promise<SbomStatistics> => {
    const response = await apiClient.get<ApiResponse<{
      statistics: SbomStatistics;
    }>>('/supply_chain/sboms/statistics');
    return response.data.data.statistics;
  },

  // Diff methods
  listDiffs: async (sbomId: string): Promise<SbomDiff[]> => {
    const response = await apiClient.get<ApiResponse<{
      diffs: SbomDiff[];
    }>>(`/supply_chain/sboms/${sbomId}/diffs`);
    return response.data.data.diffs;
  },

  getDiff: async (sbomId: string, diffId: string): Promise<SbomDiffDetail> => {
    const response = await apiClient.get<ApiResponse<{
      diff: SbomDiffDetail;
    }>>(`/supply_chain/sboms/${sbomId}/diffs/${diffId}`);
    return response.data.data.diff;
  },

  createDiff: async (sbomId: string, compareSbomId: string): Promise<SbomDiff> => {
    const response = await apiClient.post<ApiResponse<{
      diff: SbomDiff;
    }>>(`/supply_chain/sboms/${sbomId}/diffs`, { compare_sbom_id: compareSbomId });
    return response.data.data.diff;
  },

  // Enhanced export
  exportSbom: async (id: string, format: ExportFormat): Promise<Blob> => {
    const response = await apiClient.post(`/supply_chain/sboms/${id}/export`, { format }, {
      responseType: 'blob'
    });
    return response.data;
  },
};

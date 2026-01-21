import { apiClient } from '@/shared/services/apiClient';

interface ApiResponse<T> {
  success: boolean;
  data: T;
}

interface SupplyChainDashboardData {
  sbom_count: number;
  vulnerability_count: number;
  critical_vulnerabilities: number;
  high_vulnerabilities: number;
  container_image_count: number;
  quarantined_images: number;
  verified_images: number;
  attestation_count: number;
  verified_attestations: number;
  vendor_count: number;
  high_risk_vendors: number;
  vendors_needing_assessment: number;
  license_violation_count: number;
  open_violations: number;
  recent_alerts: Array<{
    id: string;
    type: string;
    severity: string;
    title: string;
    message: string;
    entity_id: string;
    entity_type: string;
    created_at: string;
  }>;
  recent_activity: Array<{
    id: string;
    action: string;
    entity_type: string;
    entity_name: string;
    user_name?: string;
    details?: string;
    created_at: string;
  }>;
}

export const supplyChainApi = {
  getDashboard: async (): Promise<SupplyChainDashboardData> => {
    const response = await apiClient.get<ApiResponse<{
      dashboard: SupplyChainDashboardData;
    }>>('/supply_chain/dashboard');
    return response.data.data.dashboard;
  },
};

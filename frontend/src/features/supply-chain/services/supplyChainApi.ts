import { apiClient } from '@/shared/services/apiClient';

interface ApiResponse<T> {
  success: boolean;
  data: T;
}

// Backend response structure for overview
interface OverviewData {
  sboms: {
    total: number;
    with_vulnerabilities: number;
    ntia_compliant: number;
  };
  vulnerabilities: {
    total: number;
    critical: number;
    high: number;
    open: number;
  };
  attestations: {
    total: number;
    signed: number;
    verified: number;
  };
  container_images: {
    total: number;
    verified: number;
    quarantined: number;
  };
  vendors: {
    total: number;
    active: number;
    high_risk: number;
  };
}

interface Alert {
  severity: string;
  type: string;
  message: string;
  action_url: string;
}

interface ActivityItem {
  type: string;
  title: string;
  timestamp: string;
  details: Record<string, unknown>;
}

interface QuickStats {
  sboms_this_month: number;
  scans_this_month: number;
  attestations_this_month: number;
  average_risk_score: number | null;
}

// Raw backend response
interface DashboardApiResponse {
  overview: OverviewData;
  recent_activity: ActivityItem[];
  alerts: Alert[];
  quick_stats: QuickStats;
}

// Transformed data for frontend consumption
export interface SupplyChainDashboardData {
  sbom_count: number;
  sboms_with_vulnerabilities: number;
  vulnerability_count: number;
  critical_vulnerabilities: number;
  high_vulnerabilities: number;
  open_vulnerabilities: number;
  container_image_count: number;
  quarantined_images: number;
  verified_images: number;
  attestation_count: number;
  verified_attestations: number;
  signed_attestations: number;
  vendor_count: number;
  active_vendors: number;
  high_risk_vendors: number;
  ntia_compliant_sboms: number;
  sboms_this_month: number;
  scans_this_month: number;
  attestations_this_month: number;
  average_risk_score: number | null;
  alerts: Alert[];
  recent_activity: ActivityItem[];
}

export const supplyChainApi = {
  getDashboard: async (): Promise<SupplyChainDashboardData> => {
    const response = await apiClient.get<ApiResponse<DashboardApiResponse>>('/supply_chain/dashboard');
    const data = response.data.data;

    // Transform backend response to frontend format
    return {
      sbom_count: data.overview.sboms.total,
      sboms_with_vulnerabilities: data.overview.sboms.with_vulnerabilities,
      vulnerability_count: data.overview.vulnerabilities.total,
      critical_vulnerabilities: data.overview.vulnerabilities.critical,
      high_vulnerabilities: data.overview.vulnerabilities.high,
      open_vulnerabilities: data.overview.vulnerabilities.open,
      container_image_count: data.overview.container_images.total,
      quarantined_images: data.overview.container_images.quarantined,
      verified_images: data.overview.container_images.verified,
      attestation_count: data.overview.attestations.total,
      verified_attestations: data.overview.attestations.verified,
      signed_attestations: data.overview.attestations.signed,
      vendor_count: data.overview.vendors.total,
      active_vendors: data.overview.vendors.active,
      high_risk_vendors: data.overview.vendors.high_risk,
      ntia_compliant_sboms: data.overview.sboms.ntia_compliant,
      sboms_this_month: data.quick_stats.sboms_this_month,
      scans_this_month: data.quick_stats.scans_this_month,
      attestations_this_month: data.quick_stats.attestations_this_month,
      average_risk_score: data.quick_stats.average_risk_score,
      alerts: data.alerts,
      recent_activity: data.recent_activity,
    };
  },
};

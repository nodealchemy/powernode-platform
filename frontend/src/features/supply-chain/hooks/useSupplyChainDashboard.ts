import { useState, useEffect, useCallback } from 'react';
import { supplyChainApi } from '../services/supplyChainApi';

interface DashboardData {
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

export function useSupplyChainDashboard() {
  const [data, setData] = useState<DashboardData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchDashboard = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const dashboard = await supplyChainApi.getDashboard();
      setData(dashboard);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch dashboard');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchDashboard();
  }, [fetchDashboard]);

  return {
    data,
    loading,
    error,
    refresh: fetchDashboard,
  };
}

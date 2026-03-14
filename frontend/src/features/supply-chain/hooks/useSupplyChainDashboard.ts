import { useState, useEffect, useCallback } from 'react';
import { supplyChainApi, SupplyChainDashboardData } from '../services/supplyChainApi';

export function useSupplyChainDashboard() {
  const [data, setData] = useState<SupplyChainDashboardData | null>(null);
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

import { useState, useCallback } from 'react';
import { useSelector } from 'react-redux';
import { RootState } from '@/shared/services';
import { codeFactoryApi } from '../api/codeFactoryApi';
import type {
  RiskContract,
  ReviewState,
  HarnessGap,
  HarnessGapMetrics,
  SlaCompliance,
} from '../types/codeFactory';

export function useCodeFactory() {
  const { user } = useSelector((state: RootState) => state.auth);
  const [contracts, setContracts] = useState<RiskContract[]>([]);
  const [reviewStates, setReviewStates] = useState<ReviewState[]>([]);
  const [harnessGaps, setHarnessGaps] = useState<HarnessGap[]>([]);
  const [gapMetrics, setGapMetrics] = useState<HarnessGapMetrics | null>(null);
  const [slaCompliance, setSlaCompliance] = useState<SlaCompliance | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const hasReadPermission = user?.permissions?.includes('ai.code_factory.read') ?? false;
  const hasManagePermission = user?.permissions?.includes('ai.code_factory.manage') ?? false;

  const fetchContracts = useCallback(async (params?: { status?: string }) => {
    setLoading(true);
    setError(null);
    try {
      const response = await codeFactoryApi.getContracts(params);
      setContracts(response.data?.contracts || []);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch contracts');
    } finally {
      setLoading(false);
    }
  }, []);

  const fetchReviewStates = useCallback(async (params?: { status?: string }) => {
    setLoading(true);
    try {
      const response = await codeFactoryApi.getReviewStates(params);
      setReviewStates(response.data?.review_states || []);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch review states');
    } finally {
      setLoading(false);
    }
  }, []);

  const fetchHarnessGaps = useCallback(async (params?: { status?: string; severity?: string }) => {
    setLoading(true);
    try {
      const response = await codeFactoryApi.getHarnessGaps(params);
      setHarnessGaps(response.data?.harness_gaps || []);
      setGapMetrics(response.data?.metrics || null);
      setSlaCompliance(response.data?.sla || null);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch harness gaps');
    } finally {
      setLoading(false);
    }
  }, []);

  const createContract = useCallback(async (data: Partial<RiskContract>) => {
    const response = await codeFactoryApi.createContract(data);
    if (response.data?.contract) {
      setContracts(prev => [response.data.contract, ...prev]);
    }
    return response.data?.contract;
  }, []);

  const updateContract = useCallback(async (id: string, data: Partial<RiskContract>) => {
    const response = await codeFactoryApi.updateContract(id, data);
    if (response.data?.contract) {
      setContracts(prev => prev.map(c => c.id === id ? response.data.contract : c));
    }
    return response.data?.contract;
  }, []);

  const activateContract = useCallback(async (id: string) => {
    const response = await codeFactoryApi.activateContract(id);
    if (response.data?.contract) {
      setContracts(prev => prev.map(c => c.id === id ? response.data.contract : c));
    }
    return response.data?.contract;
  }, []);

  const addTestCase = useCallback(async (gapId: string, testReference: string) => {
    const response = await codeFactoryApi.addTestCase(gapId, testReference);
    if (response.data?.harness_gap) {
      setHarnessGaps(prev => prev.map(g => g.id === gapId ? response.data.harness_gap : g));
    }
  }, []);

  const closeHarnessGap = useCallback(async (gapId: string, notes?: string) => {
    const response = await codeFactoryApi.closeHarnessGap(gapId, notes);
    if (response.data?.harness_gap) {
      setHarnessGaps(prev => prev.map(g => g.id === gapId ? response.data.harness_gap : g));
    }
  }, []);

  return {
    contracts,
    reviewStates,
    harnessGaps,
    gapMetrics,
    slaCompliance,
    loading,
    error,
    hasReadPermission,
    hasManagePermission,
    fetchContracts,
    fetchReviewStates,
    fetchHarnessGaps,
    createContract,
    updateContract,
    activateContract,
    addTestCase,
    closeHarnessGap,
  };
}

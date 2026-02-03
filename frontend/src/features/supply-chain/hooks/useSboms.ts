import { useState, useEffect, useCallback } from 'react';
import { sbomsApi } from '../services/sbomsApi';

type RemediationStatus = 'open' | 'in_progress' | 'fixed' | 'wont_fix';
type Severity = 'critical' | 'high' | 'medium' | 'low';

type SbomFormat = 'cyclonedx_1_4' | 'cyclonedx_1_5' | 'spdx_2_3';
type SbomStatus = 'draft' | 'generating' | 'completed' | 'failed';

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

interface Pagination {
  current_page: number;
  per_page: number;
  total_pages: number;
  total_count: number;
}

interface UseSbomsOptions {
  page?: number;
  perPage?: number;
  status?: SbomStatus;
  format?: SbomFormat;
  search?: string;
}

export function useSboms(options: UseSbomsOptions = {}) {
  const [sboms, setSboms] = useState<Sbom[]>([]);
  const [pagination, setPagination] = useState<Pagination | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchSboms = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const result = await sbomsApi.list({
        page: options.page,
        per_page: options.perPage,
        status: options.status,
        format: options.format,
        search: options.search,
      });
      setSboms(result.sboms);
      setPagination(result.pagination);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch SBOMs');
    } finally {
      setLoading(false);
    }
  }, [options.page, options.perPage, options.status, options.format, options.search]);

  useEffect(() => {
    fetchSboms();
  }, [fetchSboms]);

  return {
    sboms,
    pagination,
    loading,
    error,
    refresh: fetchSboms,
  };
}

export function useSbom(id: string | null) {
  const [sbom, setSbom] = useState<Sbom | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fetchSbom = useCallback(async () => {
    if (!id) return;
    try {
      setLoading(true);
      setError(null);
      const result = await sbomsApi.get(id);
      setSbom(result);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch SBOM');
    } finally {
      setLoading(false);
    }
  }, [id]);

  useEffect(() => {
    fetchSbom();
  }, [fetchSbom]);

  const deleteSbom = useCallback(async () => {
    if (!id) return;
    await sbomsApi.delete(id);
  }, [id]);

  const rescan = useCallback(async () => {
    if (!id) return;
    const result = await sbomsApi.rescan(id);
    setSbom(result);
    return result;
  }, [id]);

  return {
    sbom,
    loading,
    error,
    refresh: fetchSbom,
    deleteSbom,
    rescan,
  };
}

// Vulnerability action hooks
export function useUpdateVulnerabilityStatus() {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const mutateAsync = useCallback(async ({
    sbomId,
    vulnId,
    status,
  }: {
    sbomId: string;
    vulnId: string;
    status: RemediationStatus;
  }) => {
    try {
      setLoading(true);
      setError(null);
      const result = await sbomsApi.updateVulnerabilityStatus(sbomId, vulnId, status);
      return result;
    } catch (err) {
      const errorMsg = err instanceof Error ? err.message : 'Failed to update status';
      setError(errorMsg);
      throw err;
    } finally {
      setLoading(false);
    }
  }, []);

  return { mutateAsync, isLoading: loading, error };
}

export function useSuppressVulnerability() {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const mutateAsync = useCallback(async ({ sbomId, vulnId }: { sbomId: string; vulnId: string }) => {
    try {
      setLoading(true);
      setError(null);
      const result = await sbomsApi.suppressVulnerability(sbomId, vulnId);
      return result;
    } catch (err) {
      const errorMsg = err instanceof Error ? err.message : 'Failed to suppress vulnerability';
      setError(errorMsg);
      throw err;
    } finally {
      setLoading(false);
    }
  }, []);

  return { mutateAsync, isLoading: loading, error };
}

export function useUnsuppressVulnerability() {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const mutateAsync = useCallback(async ({ sbomId, vulnId }: { sbomId: string; vulnId: string }) => {
    try {
      setLoading(true);
      setError(null);
      const result = await sbomsApi.unsuppressVulnerability(sbomId, vulnId);
      return result;
    } catch (err) {
      const errorMsg = err instanceof Error ? err.message : 'Failed to unsuppress vulnerability';
      setError(errorMsg);
      throw err;
    } finally {
      setLoading(false);
    }
  }, []);

  return { mutateAsync, isLoading: loading, error };
}

export function useMarkFalsePositive() {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const mutateAsync = useCallback(async ({
    sbomId,
    vulnId,
    reason,
  }: {
    sbomId: string;
    vulnId: string;
    reason: string;
  }) => {
    try {
      setLoading(true);
      setError(null);
      const result = await sbomsApi.markFalsePositive(sbomId, vulnId, reason);
      return result;
    } catch (err) {
      const errorMsg = err instanceof Error ? err.message : 'Failed to mark false positive';
      setError(errorMsg);
      throw err;
    } finally {
      setLoading(false);
    }
  }, []);

  return { mutateAsync, isLoading: loading, error };
}

// Compliance hooks
export function useSbomCompliance(sbomId: string | null) {
  const [compliance, setCompliance] = useState<{
    ntia_minimum_compliant: boolean;
    ntia_fields: Record<string, boolean>;
    completeness_score: number;
    missing_fields: string[];
  } | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fetchCompliance = useCallback(async () => {
    if (!sbomId) return;
    try {
      setLoading(true);
      setError(null);
      const result = await sbomsApi.getComplianceStatus(sbomId);
      setCompliance(result);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch compliance');
    } finally {
      setLoading(false);
    }
  }, [sbomId]);

  useEffect(() => {
    fetchCompliance();
  }, [fetchCompliance]);

  return { compliance, loading, error, refresh: fetchCompliance };
}

export function useCalculateRisk() {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const mutateAsync = useCallback(async (sbomId: string) => {
    try {
      setLoading(true);
      setError(null);
      const result = await sbomsApi.calculateRisk(sbomId);
      return result;
    } catch (err) {
      const errorMsg = err instanceof Error ? err.message : 'Failed to calculate risk';
      setError(errorMsg);
      throw err;
    } finally {
      setLoading(false);
    }
  }, []);

  return { mutateAsync, isLoading: loading, error };
}

export function useCorrelateVulnerabilities() {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const mutateAsync = useCallback(async (sbomId: string) => {
    try {
      setLoading(true);
      setError(null);
      const result = await sbomsApi.correlateVulnerabilities(sbomId);
      return result;
    } catch (err) {
      const errorMsg = err instanceof Error ? err.message : 'Failed to correlate vulnerabilities';
      setError(errorMsg);
      throw err;
    } finally {
      setLoading(false);
    }
  }, []);

  return { mutateAsync, isLoading: loading, error };
}

export function useSbomStatistics() {
  const [statistics, setStatistics] = useState<{
    total_sboms: number;
    sboms_by_status: Record<string, number>;
    sboms_by_format: Record<string, number>;
    total_components: number;
    total_vulnerabilities: number;
    critical_vulnerabilities: number;
    avg_risk_score: number;
    compliance_rate: number;
  } | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchStatistics = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const result = await sbomsApi.getStatistics();
      setStatistics(result);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch statistics');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchStatistics();
  }, [fetchStatistics]);

  return { statistics, loading, error, refresh: fetchStatistics };
}

// Diff hooks
export function useSbomDiffs(sbomId: string | null) {
  const [diffs, setDiffs] = useState<Array<{
    id: string;
    source_sbom_id: string;
    compare_sbom_id: string;
    added_count: number;
    removed_count: number;
    changed_count: number;
    created_at: string;
  }>>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fetchDiffs = useCallback(async () => {
    if (!sbomId) return;
    try {
      setLoading(true);
      setError(null);
      const result = await sbomsApi.listDiffs(sbomId);
      setDiffs(result);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch diffs');
    } finally {
      setLoading(false);
    }
  }, [sbomId]);

  useEffect(() => {
    fetchDiffs();
  }, [fetchDiffs]);

  return { diffs, loading, error, refresh: fetchDiffs };
}

export function useSbomDiff(sbomId: string | null, diffId: string | null) {
  const [diff, setDiff] = useState<{
    id: string;
    source_sbom_id: string;
    compare_sbom_id: string;
    added_count: number;
    removed_count: number;
    changed_count: number;
    created_at: string;
    added_components: Array<{ name: string; version: string; ecosystem: string }>;
    removed_components: Array<{ name: string; version: string; ecosystem: string }>;
    changed_components: Array<{ name: string; old_version: string; new_version: string; ecosystem: string }>;
    added_vulnerabilities: Array<{ vulnerability_id: string; severity: Severity }>;
    removed_vulnerabilities: Array<{ vulnerability_id: string; severity: Severity }>;
  } | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fetchDiff = useCallback(async () => {
    if (!sbomId || !diffId) return;
    try {
      setLoading(true);
      setError(null);
      const result = await sbomsApi.getDiff(sbomId, diffId);
      setDiff(result);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch diff');
    } finally {
      setLoading(false);
    }
  }, [sbomId, diffId]);

  useEffect(() => {
    fetchDiff();
  }, [fetchDiff]);

  return { diff, loading, error, refresh: fetchDiff };
}

export function useCreateSbomDiff() {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const mutateAsync = useCallback(async ({
    sbomId,
    compareSbomId,
  }: {
    sbomId: string;
    compareSbomId: string;
  }) => {
    try {
      setLoading(true);
      setError(null);
      const result = await sbomsApi.createDiff(sbomId, compareSbomId);
      return result;
    } catch (err) {
      const errorMsg = err instanceof Error ? err.message : 'Failed to create diff';
      setError(errorMsg);
      throw err;
    } finally {
      setLoading(false);
    }
  }, []);

  return { mutateAsync, isLoading: loading, error };
}

import { useState, useEffect, useCallback } from 'react';
import { sbomsApi } from '../services/sbomsApi';

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

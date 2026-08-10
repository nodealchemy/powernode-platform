// BLESSED CROSS-BOUNDARY SEAM (same ruling as storageAssignmentsApi.ts):
// core DevOps UI fronting a system-extension endpoint
// (/api/v1/system/module_build_batches*, extensions/system). Deliberate, not
// drift — no CODE crosses the boundary, only a URL and permission strings
// (system.module_builds.read / system.module_builds.cancel), which the
// extension registers (powernode_system/engine.rb). A core-only assembly can
// never grant those permissions, so this surface fails closed without the
// extension installed. See types.ts for the full field-by-field mapping.
import { apiClient } from '@/shared/services/apiClient';
import type {
  ModuleBuildBatchDetail,
  ModuleBuildBatchListParams,
  ModuleBuildBatchListResponse,
} from '../types';

interface Envelope<T> {
  success: boolean;
  data?: T;
  error?: string;
}

function unwrap<T>(response: { data: Envelope<T> | T }): T {
  const body = response.data as Envelope<T>;
  if (body && typeof body === 'object' && 'data' in body && body.data !== undefined) {
    return body.data;
  }
  return response.data as T;
}

export const moduleBuildBatchesApi = {
  list: async (params: ModuleBuildBatchListParams = {}): Promise<ModuleBuildBatchListResponse> => {
    const response = await apiClient.get<Envelope<ModuleBuildBatchListResponse>>(
      '/system/module_build_batches',
      { params }
    );
    return unwrap<ModuleBuildBatchListResponse>(response);
  },

  get: async (id: string): Promise<ModuleBuildBatchDetail> => {
    const response = await apiClient.get<Envelope<{ module_build_batch: ModuleBuildBatchDetail }>>(
      `/system/module_build_batches/${id}`
    );
    return unwrap<{ module_build_batch: ModuleBuildBatchDetail }>(response).module_build_batch;
  },

  cancel: async (id: string, reason?: string): Promise<ModuleBuildBatchDetail> => {
    const response = await apiClient.post<Envelope<{ module_build_batch: ModuleBuildBatchDetail }>>(
      `/system/module_build_batches/${id}/cancel`,
      reason ? { reason } : {}
    );
    return unwrap<{ module_build_batch: ModuleBuildBatchDetail }>(response).module_build_batch;
  },
};

import { apiClient } from '@/shared/services/apiClient';
import { StorageCredential, StorageCredentialsListResponse } from '../types';

// BLESSED CROSS-BOUNDARY SEAM (IMP-ca6b51d65114) — see the header of
// storageAssignmentsApi.ts for the ruling; the same fail-closed permission
// mechanics apply (system.storage.assignments.* are extension-registered).
//
// Storage credential METADATA surface (IMP-b2c32f1e3038). Backend:
//   extensions/system/server/app/controllers/api/v1/system/storage_credentials_controller.rb
// index/show are read-only metadata (kind/status/rotation cadence); rotate
// issues a replacement credential and returns ITS metadata row. Credential
// material never transits this API — it lives in Vault and is fetched only
// by the node agent at mount time.

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

export const storageCredentialsApi = {
  list: async (params: { storage_assignment_id?: string; per_page?: number } = {}) => {
    const response = await apiClient.get<Envelope<StorageCredentialsListResponse>>(
      '/system/storage_credentials',
      { params },
    );
    const data = unwrap<StorageCredentialsListResponse>(response);
    return { ...data, credentials: data.credentials ?? [] };
  },

  get: async (id: string) => {
    const response = await apiClient.get<Envelope<{ credential: StorageCredential }>>(
      `/system/storage_credentials/${id}`,
    );
    return unwrap<{ credential: StorageCredential }>(response).credential;
  },

  rotate: async (id: string) => {
    const response = await apiClient.post<Envelope<{ credential: StorageCredential }>>(
      `/system/storage_credentials/${id}/rotate`,
      {},
    );
    return unwrap<{ credential: StorageCredential }>(response).credential;
  },
};

import { apiClient } from '@/shared/services/apiClient';
import {
  StorageProvider,
  StorageProviderFormData,
  StorageConnectionTestResult,
} from '@/shared/types/storage';

// Response envelopes — the backend wraps payloads as { data: { storage(s) } }
// but some endpoints return the payload flattened at the body root, so each
// shape allows both. Replaces the previous `<any>` generics.
interface StorageListResponse {
  data?: { storages?: StorageProvider[] };
  storages?: StorageProvider[];
}
interface StorageItemResponse {
  data?: { storage?: StorageProvider };
  storage?: StorageProvider;
  error?: string;
}
interface StorageTestPayload {
  connected?: boolean;
  success?: boolean;
  message?: string;
  details?: StorageConnectionTestResult['details'];
}
type StorageTestResponse = StorageTestPayload & { data?: StorageTestPayload };

export const storageApi = {
  /**
   * Get all storage providers
   */
  getProviders: async (): Promise<StorageProvider[]> => {
    const response = await apiClient.get<StorageListResponse>(
      '/storage'
    );
    // Backend returns storages array in data.storages
    const storages = response.data.data?.storages || response.data.storages || [];
    return storages;
  },

  /**
   * Get a single storage provider by ID
   */
  getProvider: async (id: string): Promise<StorageProvider> => {
    const response = await apiClient.get<StorageItemResponse>(
      `/storage/${id}`
    );
    const storage = response.data.data?.storage || response.data.storage;
    if (!storage) {
      throw new Error('Storage provider not found');
    }
    return storage;
  },

  /**
   * Create a new storage provider
   */
  createProvider: async (data: StorageProviderFormData): Promise<StorageProvider> => {
    const response = await apiClient.post<StorageItemResponse>(
      '/storage',
      {
        name: data.name,
        provider_type: data.provider_type,
        is_default: data.is_default,
        quota_bytes: data.max_file_size_mb ? data.max_file_size_mb * 1024 * 1024 : null,
        configuration: data.configuration,
        blocked_extensions: data.allowed_file_types?.map((type) => `.${type}`) || []
      }
    );
    const storage = response.data.data?.storage || response.data.storage;
    if (!storage) {
      throw new Error(response.data.error || 'Failed to create storage provider');
    }
    return storage;
  },

  /**
   * Update an existing storage provider
   */
  updateProvider: async (
    id: string,
    data: Partial<StorageProviderFormData>
  ): Promise<StorageProvider> => {
    const response = await apiClient.put<StorageItemResponse>(
      `/storage/${id}`,
      {
        name: data.name,
        is_default: data.is_default,
        quota_bytes: data.max_file_size_mb ? data.max_file_size_mb * 1024 * 1024 : null,
        configuration: data.configuration,
        blocked_extensions: data.allowed_file_types?.map((type) => `.${type}`) || []
      }
    );
    const storage = response.data.data?.storage || response.data.storage;
    if (!storage) {
      throw new Error(response.data.error || 'Failed to update storage provider');
    }
    return storage;
  },

  /**
   * Delete a storage provider
   */
  deleteProvider: async (id: string): Promise<void> => {
    await apiClient.delete(`/storage/${id}`);
  },

  /**
   * Test connection to a storage provider
   */
  testConnection: async (id: string): Promise<StorageConnectionTestResult> => {
    const response = await apiClient.post<StorageTestResponse>(
      `/storage/${id}/test`
    );
    const result = response.data.data || response.data;
    return {
      success: result.connected || result.success || false,
      message: result.message || 'Connection test completed',
      details: result.details
    };
  },

  /**
   * Set a storage provider as default
   */
  setDefault: async (id: string): Promise<StorageProvider> => {
    const response = await apiClient.post<StorageItemResponse>(
      `/storage/${id}/set_default`
    );
    const storage = response.data.data?.storage || response.data.storage;
    if (!storage) {
      throw new Error(response.data.error || 'Failed to set default provider');
    }
    return storage;
  },
};

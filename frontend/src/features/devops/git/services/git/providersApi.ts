import { apiClient } from '@/shared/services/apiClient';
import {
  GitProvider,
  GitProviderDetail,
  AvailableProvider,
  CreateProviderData,
  UpdateProviderData,
} from '../../types';

// Helper type for API responses
interface ApiResponse<T> {
  success: boolean;
  data: T;
}

/**
 * Git Providers API
 * Manages Git provider configurations (GitHub, GitLab, Gitea, etc.)
 */
export const providersApi = {
  /**
   * Get all available Git providers
   */
  getProviders: async (): Promise<GitProvider[]> => {
    const response = await apiClient.get<ApiResponse<{
      providers: GitProvider[];
      count: number;
    }>>('/git/providers');
    return response.data.data?.providers || [];
  },

  /**
   * Get available providers with configuration status
   */
  getAvailableProviders: async (): Promise<AvailableProvider[]> => {
    const response = await apiClient.get<ApiResponse<{
      providers: AvailableProvider[];
    }>>('/git/providers/available');
    return response.data.data?.providers || [];
  },

  /**
   * Get a specific provider by ID
   */
  getProvider: async (id: string): Promise<GitProviderDetail> => {
    const response = await apiClient.get<ApiResponse<{
      provider: GitProviderDetail;
    }>>(`/git/providers/${id}`);
    return response.data.data.provider;
  },

  /**
   * Create a new Git provider
   */
  createProvider: async (data: CreateProviderData): Promise<GitProviderDetail> => {
    const response = await apiClient.post<ApiResponse<{
      provider: GitProviderDetail;
    }>>('/git/providers', { provider: data });
    return response.data.data.provider;
  },

  /**
   * Update an existing Git provider
   */
  updateProvider: async (
    id: string,
    data: UpdateProviderData
  ): Promise<GitProviderDetail> => {
    const response = await apiClient.patch<ApiResponse<{
      provider: GitProviderDetail;
    }>>(`/git/providers/${id}`, { provider: data });
    return response.data.data.provider;
  },

  /**
   * Delete a Git provider
   */
  deleteProvider: async (id: string): Promise<void> => {
    await apiClient.delete(`/git/providers/${id}`);
  },
};

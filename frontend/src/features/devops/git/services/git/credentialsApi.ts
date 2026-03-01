import { apiClient } from '@/shared/services/apiClient';
import {
  GitCredential,
  GitCredentialDetail,
  CreateCredentialData,
  ConnectionTestResult,
  SyncRepositoriesResult,
  AvailableRepositoriesResponse,
  ImportRepositoriesResult,
} from '../../types';

// Helper type for API responses
interface ApiResponse<T> {
  success: boolean;
  data: T;
}

/**
 * Git Credentials API
 * Manages authentication credentials for Git providers
 */
export const credentialsApi = {
  /**
   * Get credentials for a provider
   */
  getCredentials: async (providerId: string): Promise<GitCredential[]> => {
    const response = await apiClient.get<ApiResponse<{
      credentials: GitCredential[];
      count: number;
    }>>(`/git/providers/${providerId}/credentials`);
    return response.data.data?.credentials || [];
  },

  /**
   * Get a specific credential
   */
  getCredential: async (
    providerId: string,
    credentialId: string
  ): Promise<GitCredentialDetail> => {
    const response = await apiClient.get<ApiResponse<{
      credential: GitCredentialDetail;
    }>>(`/git/providers/${providerId}/credentials/${credentialId}`);
    return response.data.data.credential;
  },

  /**
   * Create a new credential
   */
  createCredential: async (
    providerId: string,
    data: CreateCredentialData
  ): Promise<GitCredentialDetail> => {
    const response = await apiClient.post<ApiResponse<{
      credential: GitCredentialDetail;
    }>>(`/git/providers/${providerId}/credentials`, {
      credential: data,
    });
    return response.data.data.credential;
  },

  /**
   * Update a credential
   */
  updateCredential: async (
    providerId: string,
    credentialId: string,
    data: Partial<{
      name: string;
      is_active: boolean;
      is_default: boolean;
      credentials?: { access_token?: string };
    }>
  ): Promise<GitCredentialDetail> => {
    const response = await apiClient.patch<ApiResponse<{
      credential: GitCredentialDetail;
    }>>(`/git/providers/${providerId}/credentials/${credentialId}`, {
      credential: data,
    });
    return response.data.data.credential;
  },

  /**
   * Delete a credential
   */
  deleteCredential: async (
    providerId: string,
    credentialId: string
  ): Promise<void> => {
    await apiClient.delete(
      `/git/providers/${providerId}/credentials/${credentialId}`
    );
  },

  /**
   * Test a credential connection
   */
  testCredential: async (
    providerId: string,
    credentialId: string
  ): Promise<ConnectionTestResult> => {
    const response = await apiClient.post<ApiResponse<ConnectionTestResult>>(
      `/git/providers/${providerId}/credentials/${credentialId}/test`
    );
    return response.data.data;
  },

  /**
   * Make a credential the default
   */
  makeDefaultCredential: async (
    providerId: string,
    credentialId: string
  ): Promise<GitCredential> => {
    const response = await apiClient.post<ApiResponse<{
      credential: GitCredential;
    }>>(`/git/providers/${providerId}/credentials/${credentialId}/make_default`);
    return response.data.data.credential;
  },

  /**
   * Sync repositories for a credential
   * @deprecated Use getAvailableRepositories + importRepositories instead
   */
  syncRepositories: async (
    providerId: string,
    credentialId: string,
    options?: { include_archived?: boolean; include_forks?: boolean }
  ): Promise<SyncRepositoriesResult> => {
    const response = await apiClient.post<ApiResponse<SyncRepositoriesResult>>(
      `/git/providers/${providerId}/credentials/${credentialId}/sync_repositories`,
      options
    );
    return response.data.data;
  },

  /**
   * Get available repositories from a provider credential without importing
   * Returns repositories with their import status and plan usage info
   */
  getAvailableRepositories: async (
    providerId: string,
    credentialId: string,
    options?: {
      page?: number;
      per_page?: number;
      search?: string;
      include_archived?: boolean;
      include_forks?: boolean;
    }
  ): Promise<AvailableRepositoriesResponse> => {
    const params = new URLSearchParams();
    if (options?.page) params.append('page', options.page.toString());
    if (options?.per_page) params.append('per_page', options.per_page.toString());
    if (options?.search) params.append('search', options.search);
    if (options?.include_archived) params.append('include_archived', 'true');
    if (options?.include_forks) params.append('include_forks', 'true');

    const response = await apiClient.get<ApiResponse<AvailableRepositoriesResponse>>(
      `/git/providers/${providerId}/credentials/${credentialId}/available_repositories`,
      { params }
    );
    return response.data.data;
  },

  /**
   * Import specific repositories by their external IDs
   * Checks plan limits before importing
   */
  importRepositories: async (
    providerId: string,
    credentialId: string,
    externalIds: string[],
    options?: { include_archived?: boolean; include_forks?: boolean }
  ): Promise<ImportRepositoriesResult> => {
    const response = await apiClient.post<ApiResponse<ImportRepositoriesResult>>(
      `/git/providers/${providerId}/credentials/${credentialId}/import_repositories`,
      {
        external_ids: externalIds,
        include_archived: options?.include_archived,
        include_forks: options?.include_forks,
      }
    );
    return response.data.data;
  },
};

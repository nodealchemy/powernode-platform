import { apiClient } from '@/shared/services/apiClient';
import {
  GitRunner,
  GitRunnerDetail,
  RunnerStats,
  RunnerRegistrationToken,
  RunnerRemovalToken,
  SyncRunnersResult,
  PaginationInfo,
} from '../../types';

// Helper type for API responses
interface ApiResponse<T> {
  success: boolean;
  data: T;
}

/**
 * Git Runners API
 * Manages CI/CD self-hosted runners
 */
export const runnersApi = {
  /**
   * Get all runners
   */
  getRunners: async (params?: {
    page?: number;
    per_page?: number;
    status?: string;
    scope?: string;
    credential_id?: string;
    repository_id?: string;
    search?: string;
    sort?: string;
    direction?: 'asc' | 'desc';
  }): Promise<{
    runners: GitRunner[];
    stats: RunnerStats;
    pagination: PaginationInfo;
  }> => {
    const response = await apiClient.get<ApiResponse<{
      runners: GitRunner[];
      stats: RunnerStats;
      pagination: PaginationInfo;
    }>>('/git/runners', { params });
    return response.data.data;
  },

  /**
   * Get a specific runner
   */
  getRunner: async (id: string): Promise<GitRunnerDetail> => {
    const response = await apiClient.get<ApiResponse<{
      runner: GitRunnerDetail;
    }>>(`/git/runners/${id}`);
    return response.data.data.runner;
  },

  /**
   * Delete a runner
   */
  deleteRunner: async (id: string): Promise<{ message: string }> => {
    const response = await apiClient.delete<ApiResponse<{
      message: string;
    }>>(`/git/runners/${id}`);
    return response.data.data;
  },

  /**
   * Sync runners from providers
   */
  syncRunners: async (params?: {
    credential_id?: string;
    repository_id?: string;
  }): Promise<SyncRunnersResult> => {
    const response = await apiClient.post<ApiResponse<SyncRunnersResult>>(
      '/git/runners/sync',
      params
    );
    return response.data.data;
  },

  /**
   * Get registration token for a runner
   */
  getRunnerRegistrationToken: async (
    id: string
  ): Promise<RunnerRegistrationToken> => {
    const response = await apiClient.post<ApiResponse<RunnerRegistrationToken>>(
      `/git/runners/${id}/registration_token`
    );
    return response.data.data;
  },

  /**
   * Get removal token for a runner
   */
  getRunnerRemovalToken: async (id: string): Promise<RunnerRemovalToken> => {
    const response = await apiClient.post<ApiResponse<RunnerRemovalToken>>(
      `/git/runners/${id}/removal_token`
    );
    return response.data.data;
  },

  /**
   * Update runner labels
   */
  updateRunnerLabels: async (
    id: string,
    labels: string[]
  ): Promise<GitRunnerDetail> => {
    const response = await apiClient.put<ApiResponse<{
      runner: GitRunnerDetail;
    }>>(`/git/runners/${id}/labels`, { labels });
    return response.data.data.runner;
  },
};

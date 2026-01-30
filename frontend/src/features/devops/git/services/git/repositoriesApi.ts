import { apiClient } from '@/shared/services/apiClient';
import {
  GitRepository,
  GitRepositoryDetail,
  GitPipeline,
  PaginationInfo,
  GitCommitDetail,
  GitDiff,
  GitCommitComparison,
  GitFileContent,
  GitTree,
  GitTag,
  GitBranch,
} from '../../types';

// Helper type for API responses
interface ApiResponse<T> {
  success: boolean;
  data: T;
}

/**
 * Git Repositories API
 * Manages repository data, branches, commits, and related resources
 */
export const repositoriesApi = {
  /**
   * Get all repositories
   */
  getRepositories: async (params?: {
    page?: number;
    per_page?: number;
    search?: string;
    provider_id?: string;
    credential_id?: string;
    is_private?: boolean;
    webhook_configured?: boolean;
    language?: string;
    sort_by?: string;
    sort_order?: 'asc' | 'desc';
  }): Promise<{
    repositories: GitRepository[];
    pagination: PaginationInfo;
  }> => {
    const response = await apiClient.get<ApiResponse<{
      repositories: GitRepository[];
      pagination: PaginationInfo;
    }>>('/git/repositories', { params });
    return response.data.data;
  },

  /**
   * Get a specific repository
   */
  getRepository: async (id: string): Promise<GitRepositoryDetail> => {
    const response = await apiClient.get<ApiResponse<{
      repository: GitRepositoryDetail;
    }>>(`/git/repositories/${id}`);
    return response.data.data.repository;
  },

  /**
   * Delete a repository
   */
  deleteRepository: async (id: string): Promise<void> => {
    await apiClient.delete(`/git/repositories/${id}`);
  },

  /**
   * Configure webhook for a repository
   */
  configureWebhook: async (
    id: string,
    config?: {
      branch_filter?: string;
      branch_filter_type?: 'none' | 'exact' | 'wildcard' | 'regex';
    }
  ): Promise<{ repository: GitRepository; message: string }> => {
    const response = await apiClient.post<ApiResponse<{
      repository: GitRepository;
      message: string;
    }>>(`/git/repositories/${id}/configure_webhook`, config);
    return response.data.data;
  },

  /**
   * Update webhook configuration for a repository
   */
  updateWebhookConfig: async (
    id: string,
    config: {
      branch_filter?: string;
      branch_filter_type?: 'none' | 'exact' | 'wildcard' | 'regex';
    }
  ): Promise<{ repository: GitRepository; message: string }> => {
    const response = await apiClient.patch<ApiResponse<{
      repository: GitRepository;
      message: string;
    }>>(`/git/repositories/${id}/update_webhook_config`, config);
    return response.data.data;
  },

  /**
   * Remove webhook from a repository
   */
  removeWebhook: async (
    id: string
  ): Promise<{ repository: GitRepository; message: string }> => {
    const response = await apiClient.delete<ApiResponse<{
      repository: GitRepository;
      message: string;
    }>>(`/git/repositories/${id}/remove_webhook`);
    return response.data.data;
  },

  /**
   * Get branches for a repository
   */
  getBranches: async (
    id: string,
    params?: { page?: number; per_page?: number }
  ): Promise<unknown[]> => {
    const response = await apiClient.get<ApiResponse<{
      branches: unknown[];
    }>>(`/git/repositories/${id}/branches`, { params });
    return response.data.data?.branches || [];
  },

  /**
   * Get commits for a repository
   */
  getCommits: async (
    id: string,
    params?: {
      page?: number;
      per_page?: number;
      sha?: string;
      since?: string;
      until?: string;
    }
  ): Promise<unknown[]> => {
    const response = await apiClient.get<ApiResponse<{
      commits: unknown[];
    }>>(`/git/repositories/${id}/commits`, { params });
    return response.data.data?.commits || [];
  },

  /**
   * Get pull requests for a repository
   */
  getPullRequests: async (
    id: string,
    params?: { page?: number; per_page?: number; state?: string }
  ): Promise<unknown[]> => {
    const response = await apiClient.get<ApiResponse<{
      pull_requests: unknown[];
    }>>(`/git/repositories/${id}/pull_requests`, { params });
    return response.data.data?.pull_requests || [];
  },

  /**
   * Get issues for a repository
   */
  getIssues: async (
    id: string,
    params?: { page?: number; per_page?: number; state?: string }
  ): Promise<unknown[]> => {
    const response = await apiClient.get<ApiResponse<{
      issues: unknown[];
    }>>(`/git/repositories/${id}/issues`, { params });
    return response.data.data?.issues || [];
  },

  /**
   * Get tags for a repository
   */
  getTags: async (
    id: string,
    params?: { page?: number; per_page?: number }
  ): Promise<GitTag[]> => {
    const response = await apiClient.get<ApiResponse<{
      tags: GitTag[];
    }>>(`/git/repositories/${id}/tags`, { params });
    return response.data.data?.tags || [];
  },

  /**
   * Get a specific commit with full details
   */
  getCommit: async (repositoryId: string, sha: string): Promise<GitCommitDetail> => {
    const response = await apiClient.get<ApiResponse<{
      commit: GitCommitDetail;
    }>>(`/git/repositories/${repositoryId}/commits/${sha}`);
    return response.data.data.commit;
  },

  /**
   * Get diff for a specific commit
   */
  getCommitDiff: async (repositoryId: string, sha: string): Promise<GitDiff> => {
    const response = await apiClient.get<ApiResponse<{
      diff: GitDiff;
    }>>(`/git/repositories/${repositoryId}/commits/${sha}/diff`);
    return response.data.data.diff;
  },

  /**
   * Compare two commits (diff between base and head)
   */
  compareCommits: async (
    repositoryId: string,
    base: string,
    head: string
  ): Promise<GitCommitComparison> => {
    const response = await apiClient.get<ApiResponse<{
      comparison: GitCommitComparison;
    }>>(`/git/repositories/${repositoryId}/compare/${base}...${head}`);
    return response.data.data.comparison;
  },

  /**
   * Get file content at a specific ref
   */
  getFileContent: async (
    repositoryId: string,
    path: string,
    ref?: string
  ): Promise<GitFileContent> => {
    const params = ref ? { ref } : {};
    const response = await apiClient.get<ApiResponse<{
      content: GitFileContent;
    }>>(`/git/repositories/${repositoryId}/contents/${path}`, { params });
    return response.data.data.content;
  },

  /**
   * Get repository tree (directory listing) at a specific ref
   */
  getTree: async (
    repositoryId: string,
    sha?: string,
    recursive?: boolean
  ): Promise<GitTree> => {
    const params: { recursive?: string } = {};
    if (recursive) params.recursive = 'true';
    const endpoint = sha
      ? `/git/repositories/${repositoryId}/tree/${sha}`
      : `/git/repositories/${repositoryId}/tree`;
    const response = await apiClient.get<ApiResponse<{
      tree: GitTree;
      commit_sha: string;
      path: string;
    }>>(endpoint, { params });
    return response.data.data.tree;
  },

  /**
   * Get branches with typed response
   */
  getBranchesTyped: async (
    id: string,
    params?: { page?: number; per_page?: number }
  ): Promise<GitBranch[]> => {
    const response = await apiClient.get<ApiResponse<{
      branches: GitBranch[];
    }>>(`/git/repositories/${id}/branches`, { params });
    return response.data.data?.branches || [];
  },

  /**
   * Sync pipelines for a repository
   */
  syncPipelines: async (
    id: string
  ): Promise<{ synced_count: number; pipelines: GitPipeline[] }> => {
    const response = await apiClient.post<ApiResponse<{
      synced_count: number;
      pipelines: GitPipeline[];
    }>>(`/git/repositories/${id}/sync_pipelines`);
    return response.data.data;
  },
};

import { apiClient } from '@/shared/services/apiClient';
import {
  GitPipelineApproval,
  GitPipelineApprovalDetail,
  ApprovalStats,
  PaginationInfo,
} from '../../types';

// Helper type for API responses
interface ApiResponse<T> {
  success: boolean;
  data: T;
}

/**
 * Git Pipeline Approvals API
 * Manages pipeline approval workflows
 */
export const approvalsApi = {
  /**
   * Get all approvals
   */
  getApprovals: async (params?: {
    page?: number;
    per_page?: number;
    status?: string;
    environment?: string;
    pipeline_id?: string;
    sort?: string;
    direction?: 'asc' | 'desc';
  }): Promise<{
    approvals: GitPipelineApproval[];
    stats: ApprovalStats;
    pagination: PaginationInfo;
  }> => {
    const response = await apiClient.get<ApiResponse<{
      approvals: GitPipelineApproval[];
      stats: ApprovalStats;
      pagination: PaginationInfo;
    }>>('/git/pipeline_approvals', { params });
    return response.data.data;
  },

  /**
   * Get pending approvals
   */
  getPendingApprovals: async (): Promise<{
    approvals: GitPipelineApproval[];
    count: number;
  }> => {
    const response = await apiClient.get<ApiResponse<{
      approvals: GitPipelineApproval[];
      count: number;
    }>>('/git/pipeline_approvals/pending');
    return response.data.data;
  },

  /**
   * Get a specific approval
   */
  getApproval: async (id: string): Promise<GitPipelineApprovalDetail> => {
    const response = await apiClient.get<ApiResponse<{
      approval: GitPipelineApprovalDetail;
    }>>(`/git/pipeline_approvals/${id}`);
    return response.data.data.approval;
  },

  /**
   * Approve a pipeline request
   */
  approveRequest: async (
    id: string,
    comment?: string
  ): Promise<{ approval: GitPipelineApprovalDetail; message: string }> => {
    const response = await apiClient.post<ApiResponse<{
      approval: GitPipelineApprovalDetail;
      message: string;
    }>>(`/git/pipeline_approvals/${id}/approve`, { comment });
    return response.data.data;
  },

  /**
   * Reject a pipeline request
   */
  rejectRequest: async (
    id: string,
    comment?: string
  ): Promise<{ approval: GitPipelineApprovalDetail; message: string }> => {
    const response = await apiClient.post<ApiResponse<{
      approval: GitPipelineApprovalDetail;
      message: string;
    }>>(`/git/pipeline_approvals/${id}/reject`, { comment });
    return response.data.data;
  },

  /**
   * Cancel an approval request
   */
  cancelApprovalRequest: async (
    id: string
  ): Promise<{ approval: GitPipelineApprovalDetail; message: string }> => {
    const response = await apiClient.post<ApiResponse<{
      approval: GitPipelineApprovalDetail;
      message: string;
    }>>(`/git/pipeline_approvals/${id}/cancel`);
    return response.data.data;
  },
};

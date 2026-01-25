import { apiClient } from '@/shared/services/apiClient';
import {
  GitPipelineSchedule,
  GitPipelineScheduleDetail,
  CreateScheduleData,
  PaginationInfo,
} from '../../types';

// Helper type for API responses
interface ApiResponse<T> {
  success: boolean;
  data: T;
}

/**
 * Git Pipeline Schedules API
 * Manages scheduled pipeline executions
 */
export const schedulesApi = {
  /**
   * Get schedules for a repository
   */
  getSchedules: async (
    repositoryId: string,
    params?: {
      page?: number;
      per_page?: number;
      active?: boolean;
      status?: string;
      sort?: string;
      direction?: 'asc' | 'desc';
    }
  ): Promise<{
    schedules: GitPipelineSchedule[];
    pagination: PaginationInfo;
  }> => {
    const response = await apiClient.get<ApiResponse<{
      schedules: GitPipelineSchedule[];
      pagination: PaginationInfo;
    }>>(`/git/repositories/${repositoryId}/schedules`, { params });
    return response.data.data;
  },

  /**
   * Get a specific schedule
   */
  getSchedule: async (id: string): Promise<GitPipelineScheduleDetail> => {
    const response = await apiClient.get<ApiResponse<{
      schedule: GitPipelineScheduleDetail;
    }>>(`/git/pipeline_schedules/${id}`);
    return response.data.data.schedule;
  },

  /**
   * Create a new schedule
   */
  createSchedule: async (
    repositoryId: string,
    data: CreateScheduleData
  ): Promise<GitPipelineScheduleDetail> => {
    const response = await apiClient.post<ApiResponse<{
      schedule: GitPipelineScheduleDetail;
    }>>(`/git/repositories/${repositoryId}/schedules`, { schedule: data });
    return response.data.data.schedule;
  },

  /**
   * Update a schedule
   */
  updateSchedule: async (
    id: string,
    data: Partial<CreateScheduleData>
  ): Promise<GitPipelineScheduleDetail> => {
    const response = await apiClient.put<ApiResponse<{
      schedule: GitPipelineScheduleDetail;
    }>>(`/git/pipeline_schedules/${id}`, { schedule: data });
    return response.data.data.schedule;
  },

  /**
   * Delete a schedule
   */
  deleteSchedule: async (id: string): Promise<{ message: string }> => {
    const response = await apiClient.delete<ApiResponse<{
      message: string;
    }>>(`/git/pipeline_schedules/${id}`);
    return response.data.data;
  },

  /**
   * Trigger a schedule manually
   */
  triggerSchedule: async (id: string): Promise<{ message: string; pipeline_id?: string }> => {
    const response = await apiClient.post<ApiResponse<{
      message: string;
      pipeline_id?: string;
    }>>(`/git/pipeline_schedules/${id}/trigger`);
    return response.data.data;
  },

  /**
   * Pause a schedule
   */
  pauseSchedule: async (id: string): Promise<GitPipelineScheduleDetail> => {
    const response = await apiClient.post<ApiResponse<{
      schedule: GitPipelineScheduleDetail;
    }>>(`/git/pipeline_schedules/${id}/pause`);
    return response.data.data.schedule;
  },

  /**
   * Resume a schedule
   */
  resumeSchedule: async (id: string): Promise<GitPipelineScheduleDetail> => {
    const response = await apiClient.post<ApiResponse<{
      schedule: GitPipelineScheduleDetail;
    }>>(`/git/pipeline_schedules/${id}/resume`);
    return response.data.data.schedule;
  },
};

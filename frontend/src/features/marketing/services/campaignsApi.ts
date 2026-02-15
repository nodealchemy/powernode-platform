import { apiClient } from '@/shared/services/apiClient';
import type {
  Campaign,
  CampaignFormData,
  CampaignStatistics,
  CampaignStatus,
  CampaignType,
  ApiResponse,
  Pagination,
} from '../types';

export const campaignsApi = {
  list: async (params?: {
    page?: number;
    per_page?: number;
    status?: CampaignStatus;
    campaign_type?: CampaignType;
    search?: string;
  }): Promise<{ campaigns: Campaign[]; pagination: Pagination }> => {
    const response = await apiClient.get<ApiResponse<{
      campaigns: Campaign[];
      pagination: Pagination;
    }>>('/marketing/campaigns', { params });
    return response.data.data;
  },

  get: async (id: string): Promise<Campaign> => {
    const response = await apiClient.get<ApiResponse<{
      campaign: Campaign;
    }>>(`/marketing/campaigns/${id}`);
    return response.data.data.campaign;
  },

  create: async (data: CampaignFormData): Promise<Campaign> => {
    const response = await apiClient.post<ApiResponse<{
      campaign: Campaign;
    }>>('/marketing/campaigns', { campaign: data });
    return response.data.data.campaign;
  },

  update: async (id: string, data: Partial<CampaignFormData>): Promise<Campaign> => {
    const response = await apiClient.patch<ApiResponse<{
      campaign: Campaign;
    }>>(`/marketing/campaigns/${id}`, { campaign: data });
    return response.data.data.campaign;
  },

  delete: async (id: string): Promise<void> => {
    await apiClient.delete(`/marketing/campaigns/${id}`);
  },

  execute: async (id: string): Promise<Campaign> => {
    const response = await apiClient.post<ApiResponse<{
      campaign: Campaign;
    }>>(`/marketing/campaigns/${id}/execute`);
    return response.data.data.campaign;
  },

  pause: async (id: string): Promise<Campaign> => {
    const response = await apiClient.post<ApiResponse<{
      campaign: Campaign;
    }>>(`/marketing/campaigns/${id}/pause`);
    return response.data.data.campaign;
  },

  resume: async (id: string): Promise<Campaign> => {
    const response = await apiClient.post<ApiResponse<{
      campaign: Campaign;
    }>>(`/marketing/campaigns/${id}/resume`);
    return response.data.data.campaign;
  },

  archive: async (id: string): Promise<Campaign> => {
    const response = await apiClient.post<ApiResponse<{
      campaign: Campaign;
    }>>(`/marketing/campaigns/${id}/archive`);
    return response.data.data.campaign;
  },

  clone: async (id: string): Promise<Campaign> => {
    const response = await apiClient.post<ApiResponse<{
      campaign: Campaign;
    }>>(`/marketing/campaigns/${id}/clone`);
    return response.data.data.campaign;
  },

  statistics: async (): Promise<CampaignStatistics> => {
    const response = await apiClient.get<ApiResponse<{
      statistics: CampaignStatistics;
    }>>('/marketing/campaigns/statistics');
    return response.data.data.statistics;
  },
};

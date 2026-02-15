import { apiClient } from '@/shared/services/apiClient';
import type {
  AnalyticsOverview,
  CampaignStatistics,
  ChannelAnalytics,
  TopPerformer,
  CampaignMetric,
  ApiResponse,
  Pagination,
} from '../types';

export const analyticsApi = {
  overview: async (params?: {
    period_start?: string;
    period_end?: string;
  }): Promise<AnalyticsOverview> => {
    const response = await apiClient.get<ApiResponse<{
      overview: AnalyticsOverview;
    }>>('/marketing/analytics/overview', { params });
    return response.data.data.overview;
  },

  campaignDetail: async (campaignId: string, params?: {
    period_start?: string;
    period_end?: string;
  }): Promise<{ metrics: CampaignMetric[]; pagination: Pagination }> => {
    const response = await apiClient.get<ApiResponse<{
      metrics: CampaignMetric[];
      pagination: Pagination;
    }>>(`/marketing/analytics/campaigns/${campaignId}`, { params });
    return response.data.data;
  },

  channels: async (params?: {
    period_start?: string;
    period_end?: string;
  }): Promise<ChannelAnalytics[]> => {
    const response = await apiClient.get<ApiResponse<{
      channels: ChannelAnalytics[];
    }>>('/marketing/analytics/channels', { params });
    return response.data.data.channels;
  },

  roi: async (params?: {
    period_start?: string;
    period_end?: string;
  }): Promise<CampaignStatistics> => {
    const response = await apiClient.get<ApiResponse<{
      statistics: CampaignStatistics;
    }>>('/marketing/analytics/roi', { params });
    return response.data.data.statistics;
  },

  topPerformers: async (params?: {
    period_start?: string;
    period_end?: string;
    limit?: number;
  }): Promise<TopPerformer[]> => {
    const response = await apiClient.get<ApiResponse<{
      top_performers: TopPerformer[];
    }>>('/marketing/analytics/top_performers', { params });
    return response.data.data.top_performers;
  },
};

import { apiClient } from '@/shared/services/apiClient';
import type {
  SocialMediaAccount,
  SocialPlatform,
  ApiResponse,
  Pagination,
} from '../types';

export const socialAccountsApi = {
  list: async (params?: {
    page?: number;
    per_page?: number;
    platform?: SocialPlatform;
  }): Promise<{ accounts: SocialMediaAccount[]; pagination: Pagination }> => {
    const response = await apiClient.get<ApiResponse<{
      accounts: SocialMediaAccount[];
      pagination: Pagination;
    }>>('/marketing/social_accounts', { params });
    return response.data.data;
  },

  get: async (id: string): Promise<SocialMediaAccount> => {
    const response = await apiClient.get<ApiResponse<{
      account: SocialMediaAccount;
    }>>(`/marketing/social_accounts/${id}`);
    return response.data.data.account;
  },

  create: async (data: {
    platform: SocialPlatform;
    auth_code: string;
    redirect_uri: string;
  }): Promise<SocialMediaAccount> => {
    const response = await apiClient.post<ApiResponse<{
      account: SocialMediaAccount;
    }>>('/marketing/social_accounts', { social_account: data });
    return response.data.data.account;
  },

  delete: async (id: string): Promise<void> => {
    await apiClient.delete(`/marketing/social_accounts/${id}`);
  },

  test: async (id: string): Promise<{ connected: boolean; message: string }> => {
    const response = await apiClient.post<ApiResponse<{
      connected: boolean;
      message: string;
    }>>(`/marketing/social_accounts/${id}/test`);
    return response.data.data;
  },

  refreshToken: async (id: string): Promise<SocialMediaAccount> => {
    const response = await apiClient.post<ApiResponse<{
      account: SocialMediaAccount;
    }>>(`/marketing/social_accounts/${id}/refresh_token`);
    return response.data.data.account;
  },
};

import { api } from '@/shared/services/api';
import { getErrorMessage } from '@/shared/utils/errorHandling';
import type {
  Reseller,
  ResellerApplicationData,
  ResellerDashboardStats,
  ResellerCommission,
  ResellerPayout,
  ResellerReferral,
  TierInfo,
} from '../types';

interface ApiResponse<T> {
  success: boolean;
  data?: T;
  error?: string;
  meta?: {
    pagination?: {
      current_page: number;
      per_page: number;
      total_pages: number;
      total_count: number;
    };
  };
}

export const resellerApi = {
  // Get current user's reseller profile
  async getMyReseller(): Promise<ApiResponse<Reseller>> {
    try {
      const response = await api.get('/api/v1/resellers/me');
      return response.data;
    } catch (error) {
      return { success: false, error: getErrorMessage(error) };
    }
  },

  // Apply for reseller program
  async apply(data: ResellerApplicationData): Promise<ApiResponse<Reseller>> {
    try {
      const response = await api.post('/api/v1/resellers', data);
      return response.data;
    } catch (error) {
      return { success: false, error: getErrorMessage(error) };
    }
  },

  // Get reseller dashboard stats
  async getDashboard(resellerId: string): Promise<ApiResponse<ResellerDashboardStats>> {
    try {
      const response = await api.get(`/api/v1/resellers/${resellerId}/dashboard`);
      return response.data;
    } catch (error) {
      return { success: false, error: getErrorMessage(error) };
    }
  },

  // Get commissions list
  async getCommissions(
    resellerId: string,
    params?: {
      status?: string;
      start_date?: string;
      end_date?: string;
      page?: number;
      per_page?: number;
    }
  ): Promise<ApiResponse<ResellerCommission[]>> {
    try {
      const response = await api.get(`/api/v1/resellers/${resellerId}/commissions`, { params });
      return response.data;
    } catch (error) {
      return { success: false, error: getErrorMessage(error) };
    }
  },

  // Get referrals list
  async getReferrals(
    resellerId: string,
    params?: {
      status?: string;
      page?: number;
      per_page?: number;
    }
  ): Promise<ApiResponse<ResellerReferral[]>> {
    try {
      const response = await api.get(`/api/v1/resellers/${resellerId}/referrals`, { params });
      return response.data;
    } catch (error) {
      return { success: false, error: getErrorMessage(error) };
    }
  },

  // Get payouts list
  async getPayouts(
    resellerId: string,
    params?: {
      status?: string;
      page?: number;
      per_page?: number;
    }
  ): Promise<ApiResponse<ResellerPayout[]>> {
    try {
      const response = await api.get(`/api/v1/resellers/${resellerId}/payouts`, { params });
      return response.data;
    } catch (error) {
      return { success: false, error: getErrorMessage(error) };
    }
  },

  // Request a payout
  async requestPayout(resellerId: string, amount: number): Promise<ApiResponse<ResellerPayout>> {
    try {
      const response = await api.post(`/api/v1/resellers/${resellerId}/request_payout`, { amount });
      return response.data;
    } catch (error) {
      return { success: false, error: getErrorMessage(error) };
    }
  },

  // Get tier information
  async getTiers(): Promise<ApiResponse<TierInfo[]>> {
    try {
      const response = await api.get('/api/v1/resellers/tiers');
      return response.data;
    } catch (error) {
      return { success: false, error: getErrorMessage(error) };
    }
  },

  // Update reseller profile
  async updateProfile(
    resellerId: string,
    data: Partial<ResellerApplicationData>
  ): Promise<ApiResponse<Reseller>> {
    try {
      const response = await api.patch(`/api/v1/resellers/${resellerId}`, data);
      return response.data;
    } catch (error) {
      return { success: false, error: getErrorMessage(error) };
    }
  },

  // Admin: List all resellers
  async listResellers(params?: {
    status?: string;
    tier?: string;
    page?: number;
    per_page?: number;
  }): Promise<ApiResponse<Reseller[]>> {
    try {
      const response = await api.get('/api/v1/resellers', { params });
      return response.data;
    } catch (error) {
      return { success: false, error: getErrorMessage(error) };
    }
  },

  // Admin: Approve reseller
  async approveReseller(resellerId: string): Promise<ApiResponse<Reseller>> {
    try {
      const response = await api.post(`/api/v1/resellers/${resellerId}/approve`);
      return response.data;
    } catch (error) {
      return { success: false, error: getErrorMessage(error) };
    }
  },

  // Admin: Activate reseller
  async activateReseller(resellerId: string): Promise<ApiResponse<Reseller>> {
    try {
      const response = await api.post(`/api/v1/resellers/${resellerId}/activate`);
      return response.data;
    } catch (error) {
      return { success: false, error: getErrorMessage(error) };
    }
  },

  // Admin: Suspend reseller
  async suspendReseller(resellerId: string, reason?: string): Promise<ApiResponse<Reseller>> {
    try {
      const response = await api.post(`/api/v1/resellers/${resellerId}/suspend`, { reason });
      return response.data;
    } catch (error) {
      return { success: false, error: getErrorMessage(error) };
    }
  },

  // Admin: Process payout
  async processPayout(payoutId: string): Promise<ApiResponse<ResellerPayout>> {
    try {
      const response = await api.post(`/api/v1/resellers/payouts/${payoutId}/process`);
      return response.data;
    } catch (error) {
      return { success: false, error: getErrorMessage(error) };
    }
  },
};

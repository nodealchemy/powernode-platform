import { apiClient } from '@/shared/services/apiClient';
import type {
  EmailList,
  EmailListFormData,
  EmailSubscriber,
  SubscriberStatus,
  ApiResponse,
  Pagination,
} from '../types';

export const emailListsApi = {
  list: async (params?: {
    page?: number;
    per_page?: number;
    search?: string;
  }): Promise<{ email_lists: EmailList[]; pagination: Pagination }> => {
    const response = await apiClient.get<ApiResponse<{
      email_lists: EmailList[];
      pagination: Pagination;
    }>>('/marketing/email_lists', { params });
    return response.data.data;
  },

  get: async (id: string): Promise<EmailList> => {
    const response = await apiClient.get<ApiResponse<{
      email_list: EmailList;
    }>>(`/marketing/email_lists/${id}`);
    return response.data.data.email_list;
  },

  create: async (data: EmailListFormData): Promise<EmailList> => {
    const response = await apiClient.post<ApiResponse<{
      email_list: EmailList;
    }>>('/marketing/email_lists', { email_list: data });
    return response.data.data.email_list;
  },

  update: async (id: string, data: Partial<EmailListFormData>): Promise<EmailList> => {
    const response = await apiClient.patch<ApiResponse<{
      email_list: EmailList;
    }>>(`/marketing/email_lists/${id}`, { email_list: data });
    return response.data.data.email_list;
  },

  delete: async (id: string): Promise<void> => {
    await apiClient.delete(`/marketing/email_lists/${id}`);
  },

  importSubscribers: async (id: string, file: File): Promise<{ imported: number; skipped: number; errors: number }> => {
    const formData = new FormData();
    formData.append('file', file);
    const response = await apiClient.post<ApiResponse<{
      imported: number;
      skipped: number;
      errors: number;
    }>>(`/marketing/email_lists/${id}/import`, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
    return response.data.data;
  },

  // Subscriber management
  listSubscribers: async (listId: string, params?: {
    page?: number;
    per_page?: number;
    status?: SubscriberStatus;
    search?: string;
  }): Promise<{ subscribers: EmailSubscriber[]; pagination: Pagination }> => {
    const response = await apiClient.get<ApiResponse<{
      subscribers: EmailSubscriber[];
      pagination: Pagination;
    }>>(`/marketing/email_lists/${listId}/subscribers`, { params });
    return response.data.data;
  },

  addSubscriber: async (listId: string, data: {
    email: string;
    first_name?: string;
    last_name?: string;
    metadata?: Record<string, string>;
  }): Promise<EmailSubscriber> => {
    const response = await apiClient.post<ApiResponse<{
      subscriber: EmailSubscriber;
    }>>(`/marketing/email_lists/${listId}/subscribers`, { subscriber: data });
    return response.data.data.subscriber;
  },

  removeSubscriber: async (listId: string, subscriberId: string): Promise<void> => {
    await apiClient.delete(`/marketing/email_lists/${listId}/subscribers/${subscriberId}`);
  },

  updateSubscriber: async (listId: string, subscriberId: string, data: {
    status?: SubscriberStatus;
    first_name?: string;
    last_name?: string;
    metadata?: Record<string, string>;
  }): Promise<EmailSubscriber> => {
    const response = await apiClient.patch<ApiResponse<{
      subscriber: EmailSubscriber;
    }>>(`/marketing/email_lists/${listId}/subscribers/${subscriberId}`, { subscriber: data });
    return response.data.data.subscriber;
  },
};

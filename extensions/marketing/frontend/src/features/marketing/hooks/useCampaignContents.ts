import { useState, useEffect, useCallback } from 'react';
import { apiClient } from '@/shared/services/apiClient';
import type { CampaignContent, ContentFormData, ApiResponse, Pagination } from '../types';

const contentsApi = {
  list: async (campaignId: string, params?: {
    page?: number;
    per_page?: number;
  }): Promise<{ contents: CampaignContent[]; pagination: Pagination }> => {
    const response = await apiClient.get<ApiResponse<{
      contents: CampaignContent[];
      pagination: Pagination;
    }>>(`/marketing/campaigns/${campaignId}/contents`, { params });
    return response.data.data;
  },

  get: async (campaignId: string, contentId: string): Promise<CampaignContent> => {
    const response = await apiClient.get<ApiResponse<{
      content: CampaignContent;
    }>>(`/marketing/campaigns/${campaignId}/contents/${contentId}`);
    return response.data.data.content;
  },

  create: async (campaignId: string, data: ContentFormData): Promise<CampaignContent> => {
    const response = await apiClient.post<ApiResponse<{
      content: CampaignContent;
    }>>(`/marketing/campaigns/${campaignId}/contents`, { content: data });
    return response.data.data.content;
  },

  update: async (campaignId: string, contentId: string, data: Partial<ContentFormData>): Promise<CampaignContent> => {
    const response = await apiClient.patch<ApiResponse<{
      content: CampaignContent;
    }>>(`/marketing/campaigns/${campaignId}/contents/${contentId}`, { content: data });
    return response.data.data.content;
  },

  delete: async (campaignId: string, contentId: string): Promise<void> => {
    await apiClient.delete(`/marketing/campaigns/${campaignId}/contents/${contentId}`);
  },
};

interface UseCampaignContentsOptions {
  campaignId: string | null;
  page?: number;
  perPage?: number;
}

export function useCampaignContents(options: UseCampaignContentsOptions) {
  const [contents, setContents] = useState<CampaignContent[]>([]);
  const [pagination, setPagination] = useState<Pagination | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fetchContents = useCallback(async () => {
    if (!options.campaignId) return;
    try {
      setLoading(true);
      setError(null);
      const result = await contentsApi.list(options.campaignId, {
        page: options.page,
        per_page: options.perPage,
      });
      setContents(result.contents);
      setPagination(result.pagination);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch campaign contents');
    } finally {
      setLoading(false);
    }
  }, [options.campaignId, options.page, options.perPage]);

  useEffect(() => {
    fetchContents();
  }, [fetchContents]);

  const createContent = useCallback(async (data: ContentFormData) => {
    if (!options.campaignId) return;
    const result = await contentsApi.create(options.campaignId, data);
    await fetchContents();
    return result;
  }, [options.campaignId, fetchContents]);

  const updateContent = useCallback(async (contentId: string, data: Partial<ContentFormData>) => {
    if (!options.campaignId) return;
    const result = await contentsApi.update(options.campaignId, contentId, data);
    await fetchContents();
    return result;
  }, [options.campaignId, fetchContents]);

  const deleteContent = useCallback(async (contentId: string) => {
    if (!options.campaignId) return;
    await contentsApi.delete(options.campaignId, contentId);
    await fetchContents();
  }, [options.campaignId, fetchContents]);

  return {
    contents,
    pagination,
    loading,
    error,
    refresh: fetchContents,
    createContent,
    updateContent,
    deleteContent,
  };
}

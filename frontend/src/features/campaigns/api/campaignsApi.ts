import { apiClient } from '@/shared/services/apiClient';
import type {
  CampaignSummary,
  CampaignDetail,
  CreateCampaignParams,
  ParkedQuestion,
} from '../types/campaign';

const BASE_PATH = '/ai/campaigns';

interface ApiEnvelope<T> {
  success: boolean;
  data: T;
  meta?: Record<string, unknown>;
  message?: string;
}

async function unwrap<T>(request: Promise<{ data: ApiEnvelope<T> }>): Promise<ApiEnvelope<T>> {
  const response = await request;
  return response.data;
}

export const campaignsApi = {
  getCampaigns: (params?: { status?: string; limit?: number }) =>
    unwrap<{ campaigns: CampaignSummary[]; total_count: number }>(
      apiClient.get(BASE_PATH, { params }),
    ),

  getCampaign: (id: string) =>
    unwrap<CampaignDetail>(apiClient.get(`${BASE_PATH}/${id}`)),

  createCampaign: (data: CreateCampaignParams) =>
    unwrap<CampaignDetail>(apiClient.post(BASE_PATH, data)),

  answerQuestion: (id: string, questionId: string, answer: string) =>
    unwrap<{ question: ParkedQuestion }>(
      apiClient.post(`${BASE_PATH}/${id}/answer_question`, { question_id: questionId, answer }),
    ),

  stopCampaign: (id: string, summary?: string) =>
    unwrap<{ campaign: CampaignSummary }>(
      apiClient.post(`${BASE_PATH}/${id}/stop`, { summary }),
    ),
};

import { apiClient } from '@/shared/services/apiClient';
import type {
  CampaignSummary,
  CampaignDetail,
  CreateCampaignParams,
  ParkedQuestion,
  CampaignProposal,
  CreateProposalParams,
  DelegateParams,
  DelegateResult,
} from '../types/campaign';

const BASE_PATH = '/ai/campaigns';
const PROPOSALS_PATH = '/ai/campaign_proposals';

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

  // Route a spawned campaign's loop to a driver (claude_code | platform_*).
  delegateCampaign: (id: string, data: DelegateParams) =>
    unwrap<DelegateResult>(apiClient.post(`${BASE_PATH}/${id}/delegate`, data)),

  // ----- Discovery/delegation control plane: the proposal queue -----
  getProposals: (params?: { status?: string; limit?: number }) =>
    unwrap<{ proposals: CampaignProposal[]; total_count: number }>(
      apiClient.get(PROPOSALS_PATH, { params }),
    ),

  createProposal: (data: CreateProposalParams) =>
    unwrap<CampaignProposal>(apiClient.post(PROPOSALS_PATH, data)),

  queueProposal: (id: string) =>
    unwrap<CampaignProposal>(apiClient.post(`${PROPOSALS_PATH}/${id}/queue`)),

  approveProposal: (id: string) =>
    unwrap<CampaignProposal>(apiClient.post(`${PROPOSALS_PATH}/${id}/approve`)),

  rejectProposal: (id: string, reason?: string) =>
    unwrap<CampaignProposal>(apiClient.post(`${PROPOSALS_PATH}/${id}/reject`, { reason })),

  // Approve already happened; spawn creates the campaign + dev-loop. Returns the proposal
  // (now `spawned`) plus the spawned campaign summary.
  spawnProposal: (id: string) =>
    unwrap<CampaignProposal & { spawned_campaign?: CampaignSummary }>(
      apiClient.post(`${PROPOSALS_PATH}/${id}/spawn`),
    ),
};

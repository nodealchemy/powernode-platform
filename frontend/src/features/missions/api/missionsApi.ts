import { apiClient } from '@/shared/services/apiClient';
import type { Mission, CreateMissionParams } from '../types/mission';

const BASE_PATH = '/ai/missions';

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

export const missionsApi = {
  getMissions: (params?: { status?: string; mission_type?: string }) =>
    unwrap<{ missions: Mission[] }>(apiClient.get(BASE_PATH, { params })),

  getMission: (id: string) =>
    unwrap<{ mission: Mission }>(apiClient.get(`${BASE_PATH}/${id}`)),

  createMission: (data: CreateMissionParams) =>
    unwrap<{ mission: Mission }>(apiClient.post(BASE_PATH, data)),

  updateMission: (id: string, data: Partial<Mission>) =>
    unwrap<{ mission: Mission }>(apiClient.patch(`${BASE_PATH}/${id}`, data)),

  deleteMission: (id: string) =>
    unwrap<Record<string, unknown>>(apiClient.delete(`${BASE_PATH}/${id}`)),

  startMission: (id: string) =>
    unwrap<{ mission: Mission }>(apiClient.post(`${BASE_PATH}/${id}/start`)),

  approveMission: (id: string, data: { comment?: string; selected_feature?: Record<string, unknown>; prd_modifications?: Record<string, unknown> }) =>
    unwrap<{ mission: Mission }>(apiClient.post(`${BASE_PATH}/${id}/approve`, data)),

  rejectMission: (id: string, data: { comment?: string }) =>
    unwrap<{ mission: Mission }>(apiClient.post(`${BASE_PATH}/${id}/reject`, data)),

  pauseMission: (id: string) =>
    unwrap<{ mission: Mission }>(apiClient.post(`${BASE_PATH}/${id}/pause`)),

  resumeMission: (id: string) =>
    unwrap<{ mission: Mission }>(apiClient.post(`${BASE_PATH}/${id}/resume`)),

  cancelMission: (id: string, data?: { reason?: string }) =>
    unwrap<{ mission: Mission }>(apiClient.post(`${BASE_PATH}/${id}/cancel`, data)),

  retryPhase: (id: string) =>
    unwrap<{ mission: Mission }>(apiClient.post(`${BASE_PATH}/${id}/retry`)),

  analyzeRepo: (data: { repository_id: string }) =>
    unwrap<{ analysis: Record<string, unknown> }>(apiClient.post(`${BASE_PATH}/analyze_repo`, data)),
};

import apiClient from '@/shared/services/apiClient';
import type { ProjectBrief, ProvisioningPlan } from '../types';

/**
 * Co-located HTTP service for the AI provisioning feature. Consolidates the
 * inline `apiClient` calls previously scattered across MissionStatusBar,
 * ProjectProvisioningChat, PlatformDeploymentWizardCard, and
 * ChatProvisioningCardSlot.
 *
 * Behavior-preserving: uses the same default `apiClient` import the
 * components used, the same endpoint paths, request bodies, and response
 * unwrapping. Each method returns exactly the value its caller previously
 * derived from the axios response.
 */

/** Minimal mission shape surfaced by MissionStatusBar. */
export interface MissionState {
  current_phase: string | null;
  status: string | null;
}

/** Raw mission object as returned under `data.mission`. */
interface RawMission {
  current_phase?: string | null;
  status?: string | null;
}

/** Envelope returned by the compose_plan endpoint. */
export interface ComposePlanEnvelope {
  plan?: ProvisioningPlan;
  brief?: ProjectBrief;
}

/**
 * Raw `response.data` body from the messages endpoint. Returned verbatim so the
 * caller keeps owning its `data?.data ?? data ?? {}` unwrapping (and the exact
 * undefined-handling that implies).
 */
export type ConversationMessagesResponse = Record<string, unknown> | unknown[] | undefined;

/** Volume registered via the platform deployment wizard's inline create form. */
export interface CreatedVolume {
  id: string;
  name: string;
  size_gb: number;
  provider_region_id?: string | null;
  created_at?: string;
  transport?: string;
}

/** Request body for creating a platform volume. */
export interface CreateVolumeRequest {
  name: string;
  size_gb: number;
  transport: 'nfs' | 'block';
  nfs_server?: string;
  nfs_export_path?: string;
}

/**
 * Raw `response.data` body from the platform deployment endpoint. Returned
 * verbatim so the caller keeps owning its `data?.data || data` unwrapping
 * (and the exact undefined-handling that implies).
 */
export type PlatformDeploymentResponse = Record<string, unknown> | undefined;

export const provisioningApi = {
  /**
   * Fetch the current mission state. Returns the normalized MissionState
   * (or null when the response carries no mission), matching MissionStatusBar's
   * prior inline derivation of `r.data?.data?.mission`.
   */
  getMission: async (missionId: string): Promise<MissionState | null> => {
    const r = await apiClient.get<{ data?: { mission?: RawMission } }>(
      `/ai/missions/${missionId}`
    );
    const m = r.data?.data?.mission;
    if (!m) return null;
    return { current_phase: m.current_phase ?? null, status: m.status ?? null };
  },

  /**
   * Compose (or re-fetch) the provisioning plan for a mission. Returns the
   * `data` envelope (`{ plan?, brief? }`), exactly as the components read
   * `r.data?.data`.
   */
  composePlan: async (missionId: string): Promise<ComposePlanEnvelope | undefined> => {
    const r = await apiClient.post<{ data?: ComposePlanEnvelope }>(
      `/ai/missions/${missionId}/compose_plan`
    );
    return r.data?.data;
  },

  /** Approve a mission's plan. No body, no return value (matches prior usage). */
  approveMission: async (missionId: string): Promise<void> => {
    await apiClient.post(`/ai/missions/${missionId}/approve`);
  },

  /** Reject a mission's plan with an optional reason. */
  rejectMission: async (missionId: string, reason?: string): Promise<void> => {
    await apiClient.post(`/ai/missions/${missionId}/reject`, { reason });
  },

  /**
   * Load conversation messages. Returns the raw `response.data` so the caller
   * keeps its existing `data?.data ?? data ?? {}` unwrapping untouched.
   */
  getConversationMessages: async (
    conversationId: string
  ): Promise<ConversationMessagesResponse> => {
    const response = await apiClient.get(`/ai/conversations/${conversationId}/messages`);
    return response.data as ConversationMessagesResponse;
  },

  /** Send a chat message to a conversation. No return value (matches prior usage). */
  sendConversationMessage: async (
    conversationId: string,
    content: string
  ): Promise<void> => {
    await apiClient.post(`/ai/conversations/${conversationId}/messages`, {
      message: { content },
    });
  },

  /**
   * Create a platform volume from the deployment wizard's inline form. Returns
   * the created volume (or null), matching the prior `response.data?.data?.volume`
   * derivation.
   */
  createPlatformVolume: async (
    body: CreateVolumeRequest
  ): Promise<CreatedVolume | null> => {
    const response = await apiClient.post<{ data?: { volume?: CreatedVolume } }>(
      '/system/platform/volumes',
      body
    );
    return (response.data?.data?.volume ?? null) as CreatedVolume | null;
  },

  /**
   * Queue a platform deployment. Returns the raw `response.data` so the caller
   * keeps its existing `data?.data || data` unwrapping untouched.
   */
  createPlatformDeployment: async (
    body: Record<string, unknown>
  ): Promise<PlatformDeploymentResponse> => {
    const response = await apiClient.post('/system/platform/deployments', body);
    return response.data as PlatformDeploymentResponse;
  },
};

export default provisioningApi;

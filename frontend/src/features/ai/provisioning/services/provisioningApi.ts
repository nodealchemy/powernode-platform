import { apiClient } from '@/shared/services/apiClient';
import type { ProjectBrief, ProvisioningPlan } from '../types';

/**
 * Co-located HTTP service for the AI provisioning feature. Consolidates the
 * inline `apiClient` calls previously scattered across MissionStatusBar,
 * ProjectProvisioningChat and ChatProvisioningCardSlot.
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
};

export default provisioningApi;

import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { apiClient } from '@/shared/services/apiClient';
import type {
  AguiSession,
  AguiEvent,
  AguiSessionFilterParams,
  CreateSessionParams,
  AguiEventsParams,
  PushStateParams,
  StatePushResult,
} from '../types/agui';

const AGUI_KEYS = {
  all: ['agui'] as const,
  sessions: (params?: AguiSessionFilterParams) => [...AGUI_KEYS.all, 'sessions', params] as const,
  session: (id: string) => [...AGUI_KEYS.all, 'session', id] as const,
  events: (sessionId: string, params?: AguiEventsParams) => [...AGUI_KEYS.all, 'events', sessionId, params] as const,
};

export function useListAguiSessions(params?: AguiSessionFilterParams) {
  return useQuery({
    queryKey: AGUI_KEYS.sessions(params),
    queryFn: async () => {
      const response = await apiClient.get('/ai/agui/sessions', { params });
      return response.data?.data?.sessions as AguiSession[];
    },
  });
}

export function useGetAguiSession(id: string) {
  return useQuery({
    queryKey: AGUI_KEYS.session(id),
    queryFn: async () => {
      const response = await apiClient.get(`/ai/agui/sessions/${id}`);
      return response.data?.data?.session as AguiSession;
    },
    enabled: !!id,
  });
}

export function useListAguiEvents(sessionId: string, params?: AguiEventsParams) {
  return useQuery({
    queryKey: AGUI_KEYS.events(sessionId, params),
    queryFn: async () => {
      const response = await apiClient.get(`/ai/agui/sessions/${sessionId}/events`, { params });
      return response.data?.data?.events as AguiEvent[];
    },
    enabled: !!sessionId,
  });
}

export function useCreateAguiSession() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (params: CreateSessionParams) => {
      const response = await apiClient.post('/ai/agui/sessions', params);
      return response.data?.data?.session as AguiSession;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: AGUI_KEYS.sessions() });
    },
  });
}

export function useDestroyAguiSession() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (id: string) => {
      const response = await apiClient.delete(`/ai/agui/sessions/${id}`);
      return response.data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: AGUI_KEYS.sessions() });
    },
  });
}

export function usePushStateDelta() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async ({ session_id, state_delta }: PushStateParams) => {
      const response = await apiClient.post(`/ai/agui/sessions/${session_id}/state`, {
        state_delta,
      });
      return response.data?.data as StatePushResult;
    },
    onSuccess: (_data, variables) => {
      queryClient.invalidateQueries({ queryKey: AGUI_KEYS.session(variables.session_id) });
    },
  });
}

export { AGUI_KEYS };

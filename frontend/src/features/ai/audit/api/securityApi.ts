import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { apiClient } from '@/shared/services/apiClient';

const SECURITY_KEYS = {
  all: ['security'] as const,
  anomalyReport: () => [...SECURITY_KEYS.all, 'anomaly-report'] as const,
  piiScan: (params?: Record<string, unknown>) => [...SECURITY_KEYS.all, 'pii-scan', params] as const,
};

// === Anomaly Detection ===

export function useAnomalyReport() {
  return useQuery({
    queryKey: SECURITY_KEYS.anomalyReport(),
    queryFn: async () => {
      const response = await apiClient.get('/ai/security/anomaly_detection/report');
      return response.data?.data;
    },
  });
}

export function useAnalyzeAgent() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (params: { agent_id: string; window_minutes?: number }) => {
      const response = await apiClient.post('/ai/security/anomaly_detection/analyze', params);
      return response.data?.data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: SECURITY_KEYS.anomalyReport() });
    },
  });
}

export function useCheckAction() {
  return useMutation({
    mutationFn: async (params: { agent_id: string; action_type: string; action_context?: Record<string, unknown> }) => {
      const response = await apiClient.post('/ai/security/anomaly_detection/check_action', params);
      return response.data?.data;
    },
  });
}

export function useDetectInjection() {
  return useMutation({
    mutationFn: async (params: { content: string; context?: Record<string, unknown> }) => {
      const response = await apiClient.post('/ai/security/anomaly_detection/detect_injection', params);
      return response.data?.data;
    },
  });
}

export function useDetectRogue() {
  return useMutation({
    mutationFn: async (params: { agent_id: string }) => {
      const response = await apiClient.post('/ai/security/anomaly_detection/detect_rogue', params);
      return response.data?.data;
    },
  });
}

// === PII Redaction ===

export function usePiiScan() {
  return useMutation({
    mutationFn: async (params: { content: string; classifications?: string[] }) => {
      const response = await apiClient.post('/ai/security/pii_redaction/scan', params);
      return response.data?.data;
    },
  });
}

export function usePiiRedact() {
  return useMutation({
    mutationFn: async (params: { content: string; classifications?: string[] }) => {
      const response = await apiClient.post('/ai/security/pii_redaction/redact', params);
      return response.data?.data;
    },
  });
}

export function useApplyPiiPolicy() {
  return useMutation({
    mutationFn: async (params: { content: string; policy_id: string }) => {
      const response = await apiClient.post('/ai/security/pii_redaction/apply_policy', params);
      return response.data?.data;
    },
  });
}

export function useCheckOutput() {
  return useMutation({
    mutationFn: async (params: { content: string; confidence_threshold?: number }) => {
      const response = await apiClient.post('/ai/security/pii_redaction/check_output', params);
      return response.data?.data;
    },
  });
}

export function useBatchScan() {
  return useMutation({
    mutationFn: async (params: { contents: string[] }) => {
      const response = await apiClient.post('/ai/security/pii_redaction/batch_scan', params);
      return response.data?.data;
    },
  });
}

import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { apiClient } from '@/shared/services/apiClient';
import type {
  AgentIdentity,
  QuarantineRecord,
  SecurityReport,
  ComplianceMatrix,
  VerifySignatureParams,
  VerifySignatureResult,
  IdentityFilterParams,
  QuarantineFilterParams,
  SecurityReportParams,
  PaginatedSecurityResponse,
} from '../types/security';

const SECURITY_EXT_KEYS = {
  all: ['security-ext'] as const,
  identities: (params?: IdentityFilterParams) => [...SECURITY_EXT_KEYS.all, 'identities', params] as const,
  identity: (id: string) => [...SECURITY_EXT_KEYS.all, 'identity', id] as const,
  quarantine: (params?: QuarantineFilterParams) => [...SECURITY_EXT_KEYS.all, 'quarantine', params] as const,
  quarantineRecord: (id: string) => [...SECURITY_EXT_KEYS.all, 'quarantine-record', id] as const,
  securityReport: (params?: SecurityReportParams) => [...SECURITY_EXT_KEYS.all, 'security-report', params] as const,
  complianceMatrix: () => [...SECURITY_EXT_KEYS.all, 'compliance-matrix'] as const,
};

// === Agent Identity Hooks ===

export function useAgentIdentities(params?: IdentityFilterParams) {
  return useQuery({
    queryKey: SECURITY_EXT_KEYS.identities(params),
    queryFn: async () => {
      const response = await apiClient.get('/ai/security/identities', { params });
      return response.data?.data as PaginatedSecurityResponse<AgentIdentity>;
    },
  });
}

export function useAgentIdentity(id: string) {
  return useQuery({
    queryKey: SECURITY_EXT_KEYS.identity(id),
    queryFn: async () => {
      const response = await apiClient.get(`/ai/security/identities/${id}`);
      return response.data?.data as AgentIdentity;
    },
    enabled: !!id,
  });
}

export function useProvisionIdentity() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (params: { agent_id: string }) => {
      const response = await apiClient.post('/ai/security/identities', params);
      return response.data?.data as AgentIdentity;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: SECURITY_EXT_KEYS.identities() });
    },
  });
}

export function useRotateIdentity() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (id: string) => {
      const response = await apiClient.post(`/ai/security/identities/${id}/rotate`);
      return response.data?.data as AgentIdentity;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: SECURITY_EXT_KEYS.identities() });
    },
  });
}

export function useRevokeIdentity() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (params: { id: string; reason: string }) => {
      const response = await apiClient.post(`/ai/security/identities/${params.id}/revoke`, {
        reason: params.reason,
      });
      return response.data?.data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: SECURITY_EXT_KEYS.identities() });
    },
  });
}

export function useVerifySignature() {
  return useMutation({
    mutationFn: async (params: VerifySignatureParams) => {
      const response = await apiClient.post('/ai/security/identities/verify', params);
      return response.data?.data as VerifySignatureResult;
    },
  });
}

// === Quarantine Hooks ===

export function useQuarantineRecords(params?: QuarantineFilterParams) {
  return useQuery({
    queryKey: SECURITY_EXT_KEYS.quarantine(params),
    queryFn: async () => {
      const response = await apiClient.get('/ai/security/quarantine', { params });
      return response.data?.data as PaginatedSecurityResponse<QuarantineRecord>;
    },
  });
}

export function useQuarantineRecord(id: string) {
  return useQuery({
    queryKey: SECURITY_EXT_KEYS.quarantineRecord(id),
    queryFn: async () => {
      const response = await apiClient.get(`/ai/security/quarantine/${id}`);
      return response.data?.data as QuarantineRecord;
    },
    enabled: !!id,
  });
}

export function useQuarantineAgent() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (params: { agent_id: string; severity: string; reason: string }) => {
      const response = await apiClient.post('/ai/security/quarantine', params);
      return response.data?.data as QuarantineRecord;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: SECURITY_EXT_KEYS.quarantine() });
      queryClient.invalidateQueries({ queryKey: SECURITY_EXT_KEYS.securityReport() });
    },
  });
}

export function useEscalateQuarantine() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (params: { id: string; new_severity: string }) => {
      const response = await apiClient.post(`/ai/security/quarantine/${params.id}/escalate`, {
        new_severity: params.new_severity,
      });
      return response.data?.data as QuarantineRecord;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: SECURITY_EXT_KEYS.quarantine() });
      queryClient.invalidateQueries({ queryKey: SECURITY_EXT_KEYS.securityReport() });
    },
  });
}

export function useRestoreQuarantine() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (id: string) => {
      const response = await apiClient.post(`/ai/security/quarantine/${id}/restore`);
      return response.data?.data as QuarantineRecord;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: SECURITY_EXT_KEYS.quarantine() });
      queryClient.invalidateQueries({ queryKey: SECURITY_EXT_KEYS.securityReport() });
    },
  });
}

// === Report & Compliance Hooks ===

export function useSecurityReport(params?: SecurityReportParams) {
  return useQuery({
    queryKey: SECURITY_EXT_KEYS.securityReport(params),
    queryFn: async () => {
      const response = await apiClient.get('/ai/security/quarantine/report', { params });
      return response.data?.data as SecurityReport;
    },
  });
}

export function useComplianceMatrix() {
  return useQuery({
    queryKey: SECURITY_EXT_KEYS.complianceMatrix(),
    queryFn: async () => {
      const response = await apiClient.get('/ai/security/quarantine/compliance');
      return response.data?.data as ComplianceMatrix;
    },
  });
}

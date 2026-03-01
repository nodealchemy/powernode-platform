import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { apiClient } from '@/shared/services/apiClient';
import type {
  AuditStats,
  PolicyViolation,
  CompliancePolicy,
  AuditEntry,
  SecurityEvent,
  ViolationFilterParams,
  PolicyFilterParams,
  AuditEntryFilterParams,
  SecurityEventFilterParams,
  PaginatedResponse,
} from '../types/audit';

const AUDIT_KEYS = {
  all: ['audit'] as const,
  stats: () => [...AUDIT_KEYS.all, 'stats'] as const,
  violations: (params?: ViolationFilterParams) => [...AUDIT_KEYS.all, 'violations', params] as const,
  policies: (params?: PolicyFilterParams) => [...AUDIT_KEYS.all, 'policies', params] as const,
  auditEntries: (params?: AuditEntryFilterParams) => [...AUDIT_KEYS.all, 'audit-entries', params] as const,
  securityEvents: (params?: SecurityEventFilterParams) => [...AUDIT_KEYS.all, 'security-events', params] as const,
};

export function useAuditStats() {
  return useQuery({
    queryKey: AUDIT_KEYS.stats(),
    queryFn: async () => {
      const response = await apiClient.get('/ai/compliance/stats');
      return response.data?.data as AuditStats;
    },
  });
}

export function useViolations(params?: ViolationFilterParams) {
  return useQuery({
    queryKey: AUDIT_KEYS.violations(params),
    queryFn: async () => {
      const response = await apiClient.get('/ai/compliance/violations', { params });
      return response.data as PaginatedResponse<PolicyViolation>;
    },
  });
}

export function usePolicies(params?: PolicyFilterParams) {
  return useQuery({
    queryKey: AUDIT_KEYS.policies(params),
    queryFn: async () => {
      const response = await apiClient.get('/ai/compliance/policies', { params });
      return response.data as PaginatedResponse<CompliancePolicy>;
    },
  });
}

export function useAuditEntries(params?: AuditEntryFilterParams) {
  return useQuery({
    queryKey: AUDIT_KEYS.auditEntries(params),
    queryFn: async () => {
      const response = await apiClient.get('/ai/compliance/audit_entries', { params });
      return response.data as PaginatedResponse<AuditEntry>;
    },
  });
}

export function useSecurityEvents(params?: SecurityEventFilterParams) {
  return useQuery({
    queryKey: AUDIT_KEYS.securityEvents(params),
    queryFn: async () => {
      const response = await apiClient.get('/ai/compliance/security_events', { params });
      return response.data as PaginatedResponse<SecurityEvent>;
    },
  });
}

export function useResolveViolation() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (violationId: string) => {
      const response = await apiClient.post(`/ai/compliance/violations/${violationId}/resolve`);
      return response.data?.data as PolicyViolation;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: AUDIT_KEYS.violations() });
      queryClient.invalidateQueries({ queryKey: AUDIT_KEYS.stats() });
    },
  });
}

export function useTogglePolicy() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (policyId: string) => {
      const response = await apiClient.post(`/ai/compliance/policies/${policyId}/toggle`);
      return response.data?.data as CompliancePolicy;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: AUDIT_KEYS.policies() });
      queryClient.invalidateQueries({ queryKey: AUDIT_KEYS.stats() });
    },
  });
}

import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { apiClient } from '@/shared/services/apiClient';
import type {
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
  violations: (params?: ViolationFilterParams) => [...AUDIT_KEYS.all, 'violations', params] as const,
  policies: (params?: PolicyFilterParams) => [...AUDIT_KEYS.all, 'policies', params] as const,
  auditEntries: (params?: AuditEntryFilterParams) => [...AUDIT_KEYS.all, 'audit-entries', params] as const,
  securityEvents: (params?: SecurityEventFilterParams) => [...AUDIT_KEYS.all, 'security-events', params] as const,
};

/**
 * GovernanceController renders each list as `{ <name>: [...], pagination }`
 * inside the success envelope; the lists read `{ data: [...], pagination }`.
 */
async function fetchList<T>(url: string, listKey: string, params?: object): Promise<PaginatedResponse<T>> {
  const response = await apiClient.get(url, { params });
  const body = (response.data?.data ?? {}) as Record<string, unknown>;
  return {
    data: (body[listKey] ?? []) as T[],
    pagination: body.pagination as PaginatedResponse<T>['pagination'],
  };
}

type ServerViolation = Omit<PolicyViolation, 'policy_name'> & { policy?: { id: string; name: string } };

export function useViolations(params?: ViolationFilterParams) {
  return useQuery({
    queryKey: AUDIT_KEYS.violations(params),
    queryFn: async () => {
      const page = await fetchList<ServerViolation>('/ai/governance/violations', 'violations', params);
      return {
        ...page,
        data: page.data.map(({ policy, ...violation }) => ({ ...violation, policy_id: policy?.id, policy_name: policy?.name })),
      } as PaginatedResponse<PolicyViolation>;
    },
  });
}

export function usePolicies(params?: PolicyFilterParams) {
  return useQuery({
    queryKey: AUDIT_KEYS.policies(params),
    queryFn: () => {
      // The server filters on `type`, not `policy_type`.
      const { policy_type, ...rest } = params ?? {};
      return fetchList<CompliancePolicy>('/ai/governance/policies', 'policies', { ...rest, type: policy_type });
    },
  });
}

export function useAuditEntries(params?: AuditEntryFilterParams) {
  return useQuery({
    queryKey: AUDIT_KEYS.auditEntries(params),
    queryFn: () => fetchList<AuditEntry>('/ai/governance/audit_log', 'entries', params),
  });
}

export function useSecurityEvents(params?: SecurityEventFilterParams) {
  return useQuery({
    queryKey: AUDIT_KEYS.securityEvents(params),
    queryFn: () => fetchList<SecurityEvent>('/ai/governance/security_events', 'events', params),
  });
}

export function useResolveViolation() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (violationId: string) => {
      const response = await apiClient.put(`/ai/governance/violations/${violationId}/resolve`);
      return response.data?.data?.violation as PolicyViolation;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: [...AUDIT_KEYS.all, 'violations'] });
    },
  });
}

export function useTogglePolicy() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (policyId: string) => {
      const response = await apiClient.put(`/ai/governance/policies/${policyId}/toggle`);
      return response.data?.data?.policy as CompliancePolicy;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: [...AUDIT_KEYS.all, 'policies'] });
    },
  });
}

/** Invalidate every compliance-policy list, e.g. after a policy is created. */
export function useInvalidateCompliancePolicies() {
  const queryClient = useQueryClient();
  return () => queryClient.invalidateQueries({ queryKey: [...AUDIT_KEYS.all, 'policies'] });
}

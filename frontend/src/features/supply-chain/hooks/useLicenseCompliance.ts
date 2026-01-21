import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { licenseComplianceApi } from '../services/licenseComplianceApi';

export const useLicensePolicies = (params?: {
  page?: number;
  per_page?: number;
  is_active?: boolean;
  policy_type?: 'allowlist' | 'denylist' | 'hybrid';
}) => {
  return useQuery({
    queryKey: ['license-policies', params],
    queryFn: () => licenseComplianceApi.listPolicies(params),
  });
};

export const useLicensePolicy = (id: string) => {
  return useQuery({
    queryKey: ['license-policy', id],
    queryFn: () => licenseComplianceApi.getPolicy(id),
    enabled: !!id,
  });
};

export const useCreateLicensePolicy = () => {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: licenseComplianceApi.createPolicy,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['license-policies'] });
    },
  });
};

export const useUpdateLicensePolicy = () => {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({ id, data }: { id: string; data: Parameters<typeof licenseComplianceApi.updatePolicy>[1] }) =>
      licenseComplianceApi.updatePolicy(id, data),
    onSuccess: (_data, variables) => {
      queryClient.invalidateQueries({ queryKey: ['license-policies'] });
      queryClient.invalidateQueries({ queryKey: ['license-policy', variables.id] });
    },
  });
};

export const useDeleteLicensePolicy = () => {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: licenseComplianceApi.deletePolicy,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['license-policies'] });
    },
  });
};

export const useToggleLicensePolicyActive = () => {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({ id, isActive }: { id: string; isActive: boolean }) =>
      licenseComplianceApi.togglePolicyActive(id, isActive),
    onSuccess: (_data, variables) => {
      queryClient.invalidateQueries({ queryKey: ['license-policies'] });
      queryClient.invalidateQueries({ queryKey: ['license-policy', variables.id] });
    },
  });
};

export const useLicenseViolations = (params?: {
  page?: number;
  per_page?: number;
  status?: 'open' | 'resolved' | 'exception_granted';
  severity?: 'critical' | 'high' | 'medium' | 'low';
  violation_type?: 'denied' | 'copyleft_contamination' | 'incompatible' | 'unknown_license';
}) => {
  return useQuery({
    queryKey: ['license-violations', params],
    queryFn: () => licenseComplianceApi.listViolations(params),
  });
};

export const useLicenseViolation = (id: string) => {
  return useQuery({
    queryKey: ['license-violation', id],
    queryFn: () => licenseComplianceApi.getViolation(id),
    enabled: !!id,
  });
};

export const useResolveViolation = () => {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({ id, note }: { id: string; note?: string }) =>
      licenseComplianceApi.resolveViolation(id, note),
    onSuccess: (_data, variables) => {
      queryClient.invalidateQueries({ queryKey: ['license-violations'] });
      queryClient.invalidateQueries({ queryKey: ['license-violation', variables.id] });
    },
  });
};

export const useGrantViolationException = () => {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({ id, note }: { id: string; note: string }) =>
      licenseComplianceApi.grantException(id, note),
    onSuccess: (_data, variables) => {
      queryClient.invalidateQueries({ queryKey: ['license-violations'] });
      queryClient.invalidateQueries({ queryKey: ['license-violation', variables.id] });
    },
  });
};

import { useState, useEffect, useCallback } from 'react';
import { licenseComplianceApi } from '../services/licenseComplianceApi';
import type {
  LicensePolicy,
  LicenseViolation,
  LicensePolicyType,
  ViolationType,
  Severity,
  Pagination,
  CreateLicensePolicyData,
} from '../services/licenseComplianceApi';

interface UseLicensePoliciesOptions {
  page?: number;
  per_page?: number;
  is_active?: boolean;
  policy_type?: LicensePolicyType;
}

export function useLicensePolicies(options: UseLicensePoliciesOptions = {}) {
  const [policies, setPolicies] = useState<LicensePolicy[]>([]);
  const [pagination, setPagination] = useState<Pagination | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchPolicies = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const result = await licenseComplianceApi.listPolicies(options);
      setPolicies(result.policies);
      setPagination(result.pagination);
    } catch {
      setError(err instanceof Error ? err.message : 'Failed to fetch license policies');
    } finally {
      setLoading(false);
    }
  }, [options.page, options.per_page, options.is_active, options.policy_type]);

  useEffect(() => {
    fetchPolicies();
  }, [fetchPolicies]);

  return {
    data: { policies, pagination },
    isLoading: loading,
    error,
    refetch: fetchPolicies,
  };
}

export function useLicensePolicy(id: string) {
  const [policy, setPolicy] = useState<LicensePolicy | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fetchPolicy = useCallback(async () => {
    if (!id) return;
    try {
      setLoading(true);
      setError(null);
      const result = await licenseComplianceApi.getPolicy(id);
      setPolicy(result);
    } catch {
      setError(err instanceof Error ? err.message : 'Failed to fetch license policy');
    } finally {
      setLoading(false);
    }
  }, [id]);

  useEffect(() => {
    fetchPolicy();
  }, [fetchPolicy]);

  return {
    data: policy,
    isLoading: loading,
    error,
    refetch: fetchPolicy,
  };
}

export function useCreateLicensePolicy() {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const mutateAsync = useCallback(async (data: CreateLicensePolicyData) => {
    try {
      setLoading(true);
      setError(null);
      const result = await licenseComplianceApi.createPolicy(data);
      return result;
    } catch {
      const errorMsg = err instanceof Error ? err.message : 'Failed to create license policy';
      setError(errorMsg);
      throw err;
    } finally {
      setLoading(false);
    }
  }, []);

  return {
    mutateAsync,
    isLoading: loading,
    error,
  };
}

export function useUpdateLicensePolicy() {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const mutateAsync = useCallback(async ({ id, data }: { id: string; data: Partial<CreateLicensePolicyData> }) => {
    try {
      setLoading(true);
      setError(null);
      const result = await licenseComplianceApi.updatePolicy(id, data);
      return result;
    } catch {
      const errorMsg = err instanceof Error ? err.message : 'Failed to update license policy';
      setError(errorMsg);
      throw err;
    } finally {
      setLoading(false);
    }
  }, []);

  return {
    mutateAsync,
    isLoading: loading,
    error,
  };
}

export function useDeleteLicensePolicy() {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const mutateAsync = useCallback(async (id: string) => {
    try {
      setLoading(true);
      setError(null);
      await licenseComplianceApi.deletePolicy(id);
    } catch {
      const errorMsg = err instanceof Error ? err.message : 'Failed to delete license policy';
      setError(errorMsg);
      throw err;
    } finally {
      setLoading(false);
    }
  }, []);

  return {
    mutateAsync,
    isLoading: loading,
    error,
  };
}

export function useToggleLicensePolicyActive() {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const mutateAsync = useCallback(async ({ id, isActive }: { id: string; isActive: boolean }) => {
    try {
      setLoading(true);
      setError(null);
      const result = await licenseComplianceApi.togglePolicyActive(id, isActive);
      return result;
    } catch {
      const errorMsg = err instanceof Error ? err.message : 'Failed to toggle policy active state';
      setError(errorMsg);
      throw err;
    } finally {
      setLoading(false);
    }
  }, []);

  return {
    mutateAsync,
    isLoading: loading,
    error,
  };
}

interface UseLicenseViolationsOptions {
  page?: number;
  per_page?: number;
  status?: 'open' | 'resolved' | 'exception_granted';
  severity?: Severity;
  violation_type?: ViolationType;
}

export function useLicenseViolations(options: UseLicenseViolationsOptions = {}) {
  const [violations, setViolations] = useState<LicenseViolation[]>([]);
  const [pagination, setPagination] = useState<Pagination | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchViolations = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const result = await licenseComplianceApi.listViolations(options);
      setViolations(result.violations);
      setPagination(result.pagination);
    } catch {
      setError(err instanceof Error ? err.message : 'Failed to fetch license violations');
    } finally {
      setLoading(false);
    }
  }, [options.page, options.per_page, options.status, options.severity, options.violation_type]);

  useEffect(() => {
    fetchViolations();
  }, [fetchViolations]);

  return {
    data: { violations, pagination },
    isLoading: loading,
    error,
    refetch: fetchViolations,
  };
}

export function useLicenseViolation(id: string) {
  const [violation, setViolation] = useState<LicenseViolation | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fetchViolation = useCallback(async () => {
    if (!id) return;
    try {
      setLoading(true);
      setError(null);
      const result = await licenseComplianceApi.getViolation(id);
      setViolation(result);
    } catch {
      setError(err instanceof Error ? err.message : 'Failed to fetch license violation');
    } finally {
      setLoading(false);
    }
  }, [id]);

  useEffect(() => {
    fetchViolation();
  }, [fetchViolation]);

  return {
    data: violation,
    isLoading: loading,
    error,
    refetch: fetchViolation,
  };
}

export function useResolveViolation() {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const mutateAsync = useCallback(async ({ id, note }: { id: string; note?: string }) => {
    try {
      setLoading(true);
      setError(null);
      const result = await licenseComplianceApi.resolveViolation(id, note);
      return result;
    } catch {
      const errorMsg = err instanceof Error ? err.message : 'Failed to resolve violation';
      setError(errorMsg);
      throw err;
    } finally {
      setLoading(false);
    }
  }, []);

  return {
    mutateAsync,
    isLoading: loading,
    error,
  };
}

export function useGrantViolationException() {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const mutateAsync = useCallback(async ({ id, note }: { id: string; note: string }) => {
    try {
      setLoading(true);
      setError(null);
      const result = await licenseComplianceApi.grantException(id, note);
      return result;
    } catch {
      const errorMsg = err instanceof Error ? err.message : 'Failed to grant exception';
      setError(errorMsg);
      throw err;
    } finally {
      setLoading(false);
    }
  }, []);

  return {
    mutateAsync,
    isLoading: loading,
    error,
  };
}

// Exception workflow hooks
export function useRequestException() {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const mutateAsync = useCallback(async ({
    id,
    justification,
    expiresAt,
  }: {
    id: string;
    justification: string;
    expiresAt?: string;
  }) => {
    try {
      setLoading(true);
      setError(null);
      const result = await licenseComplianceApi.requestException(id, justification, expiresAt);
      return result;
    } catch {
      const errorMsg = err instanceof Error ? err.message : 'Failed to request exception';
      setError(errorMsg);
      throw err;
    } finally {
      setLoading(false);
    }
  }, []);

  return { mutateAsync, isLoading: loading, error };
}

export function useApproveException() {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const mutateAsync = useCallback(async ({
    id,
    notes,
    expiresAt,
  }: {
    id: string;
    notes?: string;
    expiresAt?: string;
  }) => {
    try {
      setLoading(true);
      setError(null);
      const result = await licenseComplianceApi.approveException(id, notes, expiresAt);
      return result;
    } catch {
      const errorMsg = err instanceof Error ? err.message : 'Failed to approve exception';
      setError(errorMsg);
      throw err;
    } finally {
      setLoading(false);
    }
  }, []);

  return { mutateAsync, isLoading: loading, error };
}

export function useRejectException() {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const mutateAsync = useCallback(async ({
    id,
    reason,
  }: {
    id: string;
    reason?: string;
  }) => {
    try {
      setLoading(true);
      setError(null);
      const result = await licenseComplianceApi.rejectException(id, reason);
      return result;
    } catch {
      const errorMsg = err instanceof Error ? err.message : 'Failed to reject exception';
      setError(errorMsg);
      throw err;
    } finally {
      setLoading(false);
    }
  }, []);

  return { mutateAsync, isLoading: loading, error };
}

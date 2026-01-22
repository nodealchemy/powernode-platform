import { renderHook, waitFor, act } from '@testing-library/react';
import {
  useLicensePolicies,
  useLicensePolicy,
  useCreateLicensePolicy,
  useUpdateLicensePolicy,
  useDeleteLicensePolicy,
  useToggleLicensePolicyActive,
  useLicenseViolations,
  useLicenseViolation,
  useResolveViolation,
  useGrantViolationException,
  useRequestException,
  useApproveException,
  useRejectException,
} from '../useLicenseCompliance';
import { licenseComplianceApi } from '../../services/licenseComplianceApi';
import {
  createMockLicensePolicy,
  createMockLicenseViolation,
  createMockPagination,
} from '../../testing/mockFactories';
import type {
  LicensePolicy,
  LicenseViolation,
  CreateLicensePolicyData,
  Pagination,
} from '../../services/licenseComplianceApi';

jest.mock('../../services/licenseComplianceApi');
const mockApi = licenseComplianceApi as jest.Mocked<typeof licenseComplianceApi>;

describe('License Compliance Hooks', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  // ============================================================================
  // Policy List Hook - useLicensePolicies
  // ============================================================================

  describe('useLicensePolicies', () => {
    const mockPolicies = [
      createMockLicensePolicy({ name: 'Policy 1' }),
      createMockLicensePolicy({ name: 'Policy 2', is_active: false }),
    ];
    const mockPagination = createMockPagination();

    it('initializes with loading state', () => {
      mockApi.listPolicies.mockResolvedValue({
        policies: mockPolicies,
        pagination: mockPagination,
      });

      const { result } = renderHook(() => useLicensePolicies());

      expect(result.current.isLoading).toBe(true);
    });

    it('loads policies on mount', async () => {
      mockApi.listPolicies.mockResolvedValue({
        policies: mockPolicies,
        pagination: mockPagination,
      });

      const { result } = renderHook(() => useLicensePolicies());

      await waitFor(() => {
        expect(result.current.isLoading).toBe(false);
      });

      expect(result.current.data.policies).toEqual(mockPolicies);
      expect(result.current.data.pagination).toEqual(mockPagination);
      expect(mockApi.listPolicies).toHaveBeenCalledWith({});
    });

    it('returns data in correct shape with policies and pagination', async () => {
      mockApi.listPolicies.mockResolvedValue({
        policies: mockPolicies,
        pagination: mockPagination,
      });

      const { result } = renderHook(() => useLicensePolicies());

      await waitFor(() => {
        expect(result.current.isLoading).toBe(false);
      });

      expect(result.current.data).toHaveProperty('policies');
      expect(result.current.data).toHaveProperty('pagination');
      expect(Array.isArray(result.current.data.policies)).toBe(true);
      expect(result.current.data.pagination.current_page).toBe(1);
    });

    it('passes pagination options to API', async () => {
      mockApi.listPolicies.mockResolvedValue({
        policies: [mockPolicies[0]],
        pagination: { ...mockPagination, current_page: 2 },
      });

      renderHook(() =>
        useLicensePolicies({
          page: 2,
          per_page: 50,
        })
      );

      await waitFor(() => {
        expect(mockApi.listPolicies).toHaveBeenCalledWith({
          page: 2,
          per_page: 50,
        });
      });
    });

    it('passes filter options to API', async () => {
      mockApi.listPolicies.mockResolvedValue({
        policies: [mockPolicies[0]],
        pagination: mockPagination,
      });

      renderHook(() =>
        useLicensePolicies({
          is_active: true,
          policy_type: 'allowlist',
        })
      );

      await waitFor(() => {
        expect(mockApi.listPolicies).toHaveBeenCalledWith({
          is_active: true,
          policy_type: 'allowlist',
        });
      });
    });

    it('handles API errors', async () => {
      const error = new Error('Failed to fetch policies');
      mockApi.listPolicies.mockRejectedValue(error);

      const { result } = renderHook(() => useLicensePolicies());

      await waitFor(() => {
        expect(result.current.isLoading).toBe(false);
      });

      expect(result.current.error).toBe('Failed to fetch policies');
      expect(result.current.data.policies).toEqual([]);
    });

    it('provides refetch function', async () => {
      mockApi.listPolicies.mockResolvedValue({
        policies: mockPolicies,
        pagination: mockPagination,
      });

      const { result } = renderHook(() => useLicensePolicies());

      await waitFor(() => {
        expect(result.current.isLoading).toBe(false);
      });

      jest.clearAllMocks();
      mockApi.listPolicies.mockResolvedValue({
        policies: [mockPolicies[0]],
        pagination: mockPagination,
      });

      await act(async () => {
        await result.current.refetch();
      });

      await waitFor(() => {
        expect(result.current.data.policies).toHaveLength(1);
      });
    });

    it('clears error when refetch succeeds after error', async () => {
      mockApi.listPolicies.mockRejectedValue(
        new Error('Failed to fetch policies')
      );

      const { result } = renderHook(() => useLicensePolicies());

      await waitFor(() => {
        expect(result.current.error).toBe('Failed to fetch policies');
      });

      mockApi.listPolicies.mockResolvedValue({
        policies: mockPolicies,
        pagination: mockPagination,
      });

      await act(async () => {
        await result.current.refetch();
      });

      await waitFor(() => {
        expect(result.current.error).toBeNull();
        expect(result.current.data.policies).toEqual(mockPolicies);
      });
    });
  });

  // ============================================================================
  // Policy Detail Hook - useLicensePolicy
  // ============================================================================

  describe('useLicensePolicy', () => {
    const mockPolicy = createMockLicensePolicy();

    it('sets loading state during fetch', async () => {
      mockApi.getPolicy.mockResolvedValue(mockPolicy);

      const { result } = renderHook(() => useLicensePolicy(mockPolicy.id));

      expect(result.current.isLoading).toBe(true);

      await waitFor(() => {
        expect(result.current.isLoading).toBe(false);
      });
    });

    it('loads policy when id is provided', async () => {
      mockApi.getPolicy.mockResolvedValue(mockPolicy);

      const { result } = renderHook(() => useLicensePolicy(mockPolicy.id));

      await waitFor(() => {
        expect(result.current.data).toEqual(mockPolicy);
      });

      expect(mockApi.getPolicy).toHaveBeenCalledWith(mockPolicy.id);
    });

    it('returns policy as data property', async () => {
      mockApi.getPolicy.mockResolvedValue(mockPolicy);

      const { result } = renderHook(() => useLicensePolicy(mockPolicy.id));

      await waitFor(() => {
        expect(result.current.data).not.toBeNull();
      });

      expect(result.current.data).toEqual(mockPolicy);
      expect(result.current.data?.id).toBe(mockPolicy.id);
    });

    it('does not fetch when id is empty string', () => {
      const { result } = renderHook(() => useLicensePolicy(''));

      expect(result.current.data).toBeNull();
      expect(mockApi.getPolicy).not.toHaveBeenCalled();
    });

    it('handles API errors', async () => {
      const error = new Error('Policy not found');
      mockApi.getPolicy.mockRejectedValue(error);

      const { result } = renderHook(() => useLicensePolicy('invalid-id'));

      await waitFor(() => {
        expect(result.current.error).toBe('Policy not found');
      });

      expect(result.current.data).toBeNull();
    });

    it('provides refetch function', async () => {
      mockApi.getPolicy.mockResolvedValue(mockPolicy);

      const { result } = renderHook(() => useLicensePolicy(mockPolicy.id));

      await waitFor(() => {
        expect(result.current.data).toEqual(mockPolicy);
      });

      jest.clearAllMocks();
      mockApi.getPolicy.mockResolvedValue(mockPolicy);

      await act(async () => {
        await result.current.refetch();
      });

      expect(mockApi.getPolicy).toHaveBeenCalledWith(mockPolicy.id);
    });

    it('fetches new policy when id changes', async () => {
      const policy1 = createMockLicensePolicy({ id: 'policy-1' });
      const policy2 = createMockLicensePolicy({ id: 'policy-2' });

      mockApi.getPolicy.mockResolvedValue(policy1);

      const { result, rerender } = renderHook(
        ({ id }: { id: string }) => useLicensePolicy(id),
        { initialProps: { id: 'policy-1' } }
      );

      await waitFor(() => {
        expect(result.current.data?.id).toBe('policy-1');
      });

      mockApi.getPolicy.mockResolvedValue(policy2);

      rerender({ id: 'policy-2' });

      await waitFor(() => {
        expect(mockApi.getPolicy).toHaveBeenCalledWith('policy-2');
        expect(result.current.data?.id).toBe('policy-2');
      });
    });
  });

  // ============================================================================
  // Create Policy Mutation - useCreateLicensePolicy
  // ============================================================================

  describe('useCreateLicensePolicy', () => {
    const policyData: CreateLicensePolicyData = {
      name: 'New Policy',
      description: 'Test policy',
      policy_type: 'allowlist',
      enforcement_level: 'warn',
      is_active: true,
      allowed_licenses: ['MIT', 'Apache-2.0'],
    };
    const createdPolicy = createMockLicensePolicy(policyData);

    it('initializes with not loading state', () => {
      const { result } = renderHook(() => useCreateLicensePolicy());

      expect(result.current.isLoading).toBe(false);
    });

    it('creates policy and returns created data', async () => {
      mockApi.createPolicy.mockResolvedValue(createdPolicy);

      const { result } = renderHook(() => useCreateLicensePolicy());

      await act(async () => {
        const response = await result.current.mutateAsync(policyData);
        expect(response).toEqual(createdPolicy);
      });

      expect(mockApi.createPolicy).toHaveBeenCalledWith(policyData);
    });

    it('clears error on successful mutation', async () => {
      mockApi.createPolicy.mockRejectedValueOnce(
        new Error('Initial error')
      );

      const { result } = renderHook(() => useCreateLicensePolicy());

      let thrownError: Error | null = null;
      await act(async () => {
        try {
          await result.current.mutateAsync(policyData);
        } catch (err) {
          thrownError = err as Error;
        }
      });

      expect(result.current.error).toBe('Initial error');

      mockApi.createPolicy.mockResolvedValueOnce(createdPolicy);

      await act(async () => {
        await result.current.mutateAsync(policyData);
      });

      expect(result.current.error).toBeNull();
      expect(result.current.isLoading).toBe(false);
    });

    it('handles mutation errors', async () => {
      const error = new Error('Invalid policy data');
      mockApi.createPolicy.mockRejectedValue(error);

      const { result } = renderHook(() => useCreateLicensePolicy());

      let thrownError: Error | null = null;
      await act(async () => {
        try {
          await result.current.mutateAsync(policyData);
        } catch (err) {
          thrownError = err as Error;
        }
      });

      expect(result.current.error).toBe('Invalid policy data');
      expect(thrownError).toEqual(error);
    });

    it('throws error instead of suppressing it', async () => {
      const error = new Error('Creation failed');
      mockApi.createPolicy.mockRejectedValue(error);

      const { result } = renderHook(() => useCreateLicensePolicy());

      await expect(
        act(async () => {
          await result.current.mutateAsync(policyData);
        })
      ).rejects.toThrow('Creation failed');
    });
  });

  // ============================================================================
  // Update Policy Mutation - useUpdateLicensePolicy
  // ============================================================================

  describe('useUpdateLicensePolicy', () => {
    const policyId = 'policy-123';
    const updateData: Partial<CreateLicensePolicyData> = {
      name: 'Updated Policy',
      enforcement_level: 'block',
    };
    const updatedPolicy = createMockLicensePolicy({
      ...updateData,
      id: policyId,
    });

    it('initializes with not loading state', () => {
      const { result } = renderHook(() => useUpdateLicensePolicy());

      expect(result.current.isLoading).toBe(false);
    });

    it('updates policy with id and data', async () => {
      mockApi.updatePolicy.mockResolvedValue(updatedPolicy);

      const { result } = renderHook(() => useUpdateLicensePolicy());

      await act(async () => {
        const response = await result.current.mutateAsync({
          id: policyId,
          data: updateData,
        });
        expect(response).toEqual(updatedPolicy);
      });

      expect(mockApi.updatePolicy).toHaveBeenCalledWith(policyId, updateData);
    });

    it('clears error on successful update', async () => {
      mockApi.updatePolicy.mockRejectedValueOnce(
        new Error('Update failed')
      );

      const { result } = renderHook(() => useUpdateLicensePolicy());

      let thrownError: Error | null = null;
      await act(async () => {
        try {
          await result.current.mutateAsync({
            id: policyId,
            data: updateData,
          });
        } catch (err) {
          thrownError = err as Error;
        }
      });

      expect(result.current.error).toBe('Update failed');

      mockApi.updatePolicy.mockResolvedValueOnce(updatedPolicy);

      await act(async () => {
        await result.current.mutateAsync({
          id: policyId,
          data: updateData,
        });
      });

      expect(result.current.error).toBeNull();
      expect(result.current.isLoading).toBe(false);
    });

    it('handles update errors', async () => {
      const error = new Error('Policy not found');
      mockApi.updatePolicy.mockRejectedValue(error);

      const { result } = renderHook(() => useUpdateLicensePolicy());

      let thrownError: Error | null = null;
      await act(async () => {
        try {
          await result.current.mutateAsync({
            id: policyId,
            data: updateData,
          });
        } catch (err) {
          thrownError = err as Error;
        }
      });

      expect(result.current.error).toBe('Policy not found');
      expect(thrownError).toEqual(error);
    });

    it('updates partial fields', async () => {
      const partialUpdate = { enforcement_level: 'log' as const };
      mockApi.updatePolicy.mockResolvedValue(updatedPolicy);

      const { result } = renderHook(() => useUpdateLicensePolicy());

      await act(async () => {
        await result.current.mutateAsync({
          id: policyId,
          data: partialUpdate,
        });
      });

      expect(mockApi.updatePolicy).toHaveBeenCalledWith(policyId, partialUpdate);
    });
  });

  // ============================================================================
  // Delete Policy Mutation - useDeleteLicensePolicy
  // ============================================================================

  describe('useDeleteLicensePolicy', () => {
    const policyId = 'policy-123';

    it('initializes with not loading state', () => {
      const { result } = renderHook(() => useDeleteLicensePolicy());

      expect(result.current.isLoading).toBe(false);
    });

    it('deletes policy with provided id', async () => {
      mockApi.deletePolicy.mockResolvedValue(undefined);

      const { result } = renderHook(() => useDeleteLicensePolicy());

      await act(async () => {
        await result.current.mutateAsync(policyId);
      });

      expect(mockApi.deletePolicy).toHaveBeenCalledWith(policyId);
    });

    it('clears error on successful deletion', async () => {
      mockApi.deletePolicy.mockRejectedValueOnce(
        new Error('Delete failed')
      );

      const { result } = renderHook(() => useDeleteLicensePolicy());

      let thrownError: Error | null = null;
      await act(async () => {
        try {
          await result.current.mutateAsync(policyId);
        } catch (err) {
          thrownError = err as Error;
        }
      });

      expect(result.current.error).toBe('Delete failed');

      mockApi.deletePolicy.mockResolvedValueOnce(undefined);

      await act(async () => {
        await result.current.mutateAsync(policyId);
      });

      expect(result.current.error).toBeNull();
      expect(result.current.isLoading).toBe(false);
    });

    it('handles deletion errors', async () => {
      const error = new Error('Cannot delete active policy');
      mockApi.deletePolicy.mockRejectedValue(error);

      const { result } = renderHook(() => useDeleteLicensePolicy());

      let thrownError: Error | null = null;
      await act(async () => {
        try {
          await result.current.mutateAsync(policyId);
        } catch (err) {
          thrownError = err as Error;
        }
      });

      expect(result.current.error).toBe('Cannot delete active policy');
      expect(thrownError).toEqual(error);
    });
  });

  // ============================================================================
  // Toggle Policy Active Mutation - useToggleLicensePolicyActive
  // ============================================================================

  describe('useToggleLicensePolicyActive', () => {
    const policyId = 'policy-123';
    const activePolicy = createMockLicensePolicy({ id: policyId, is_active: true });
    const inactivePolicy = createMockLicensePolicy({
      id: policyId,
      is_active: false,
    });

    it('initializes with not loading state', () => {
      const { result } = renderHook(() => useToggleLicensePolicyActive());

      expect(result.current.isLoading).toBe(false);
    });

    it('activates policy', async () => {
      mockApi.togglePolicyActive.mockResolvedValue(activePolicy);

      const { result } = renderHook(() => useToggleLicensePolicyActive());

      await act(async () => {
        const response = await result.current.mutateAsync({
          id: policyId,
          isActive: true,
        });
        expect(response.is_active).toBe(true);
      });

      expect(mockApi.togglePolicyActive).toHaveBeenCalledWith(policyId, true);
    });

    it('deactivates policy', async () => {
      mockApi.togglePolicyActive.mockResolvedValue(inactivePolicy);

      const { result } = renderHook(() => useToggleLicensePolicyActive());

      await act(async () => {
        const response = await result.current.mutateAsync({
          id: policyId,
          isActive: false,
        });
        expect(response.is_active).toBe(false);
      });

      expect(mockApi.togglePolicyActive).toHaveBeenCalledWith(policyId, false);
    });

    it('clears error on successful toggle', async () => {
      mockApi.togglePolicyActive.mockRejectedValueOnce(
        new Error('Toggle failed')
      );

      const { result } = renderHook(() => useToggleLicensePolicyActive());

      let thrownError: Error | null = null;
      await act(async () => {
        try {
          await result.current.mutateAsync({
            id: policyId,
            isActive: true,
          });
        } catch (err) {
          thrownError = err as Error;
        }
      });

      expect(result.current.error).toBe('Toggle failed');

      mockApi.togglePolicyActive.mockResolvedValueOnce(activePolicy);

      await act(async () => {
        await result.current.mutateAsync({
          id: policyId,
          isActive: false,
        });
      });

      expect(result.current.error).toBeNull();
      expect(result.current.isLoading).toBe(false);
    });

    it('handles toggle errors', async () => {
      const error = new Error('Policy is locked');
      mockApi.togglePolicyActive.mockRejectedValue(error);

      const { result } = renderHook(() => useToggleLicensePolicyActive());

      let thrownError: Error | null = null;
      await act(async () => {
        try {
          await result.current.mutateAsync({
            id: policyId,
            isActive: true,
          });
        } catch (err) {
          thrownError = err as Error;
        }
      });

      expect(result.current.error).toBe('Policy is locked');
      expect(thrownError).toEqual(error);
    });
  });

  // ============================================================================
  // Violation List Hook - useLicenseViolations
  // ============================================================================

  describe('useLicenseViolations', () => {
    const mockViolations = [
      createMockLicenseViolation({ status: 'open' }),
      createMockLicenseViolation({ status: 'resolved' }),
    ];
    const mockPagination = createMockPagination();

    it('initializes with loading state', () => {
      mockApi.listViolations.mockResolvedValue({
        violations: mockViolations,
        pagination: mockPagination,
      });

      const { result } = renderHook(() => useLicenseViolations());

      expect(result.current.isLoading).toBe(true);
    });

    it('loads violations on mount', async () => {
      mockApi.listViolations.mockResolvedValue({
        violations: mockViolations,
        pagination: mockPagination,
      });

      const { result } = renderHook(() => useLicenseViolations());

      await waitFor(() => {
        expect(result.current.isLoading).toBe(false);
      });

      expect(result.current.data.violations).toEqual(mockViolations);
      expect(result.current.data.pagination).toEqual(mockPagination);
    });

    it('returns data in correct shape with violations and pagination', async () => {
      mockApi.listViolations.mockResolvedValue({
        violations: mockViolations,
        pagination: mockPagination,
      });

      const { result } = renderHook(() => useLicenseViolations());

      await waitFor(() => {
        expect(result.current.isLoading).toBe(false);
      });

      expect(result.current.data).toHaveProperty('violations');
      expect(result.current.data).toHaveProperty('pagination');
      expect(Array.isArray(result.current.data.violations)).toBe(true);
    });

    it('passes filter options to API', async () => {
      mockApi.listViolations.mockResolvedValue({
        violations: [mockViolations[0]],
        pagination: mockPagination,
      });

      renderHook(() =>
        useLicenseViolations({
          status: 'open',
          severity: 'high',
          violation_type: 'copyleft_contamination',
        })
      );

      await waitFor(() => {
        expect(mockApi.listViolations).toHaveBeenCalledWith({
          status: 'open',
          severity: 'high',
          violation_type: 'copyleft_contamination',
        });
      });
    });

    it('passes pagination options to API', async () => {
      mockApi.listViolations.mockResolvedValue({
        violations: [mockViolations[0]],
        pagination: { ...mockPagination, current_page: 2 },
      });

      renderHook(() =>
        useLicenseViolations({
          page: 2,
          per_page: 50,
        })
      );

      await waitFor(() => {
        expect(mockApi.listViolations).toHaveBeenCalledWith({
          page: 2,
          per_page: 50,
        });
      });
    });

    it('handles API errors', async () => {
      const error = new Error('Failed to fetch violations');
      mockApi.listViolations.mockRejectedValue(error);

      const { result } = renderHook(() => useLicenseViolations());

      await waitFor(() => {
        expect(result.current.isLoading).toBe(false);
      });

      expect(result.current.error).toBe('Failed to fetch violations');
      expect(result.current.data.violations).toEqual([]);
    });

    it('provides refetch function', async () => {
      mockApi.listViolations.mockResolvedValue({
        violations: mockViolations,
        pagination: mockPagination,
      });

      const { result } = renderHook(() => useLicenseViolations());

      await waitFor(() => {
        expect(result.current.isLoading).toBe(false);
      });

      jest.clearAllMocks();
      mockApi.listViolations.mockResolvedValue({
        violations: [mockViolations[0]],
        pagination: mockPagination,
      });

      await act(async () => {
        await result.current.refetch();
      });

      await waitFor(() => {
        expect(result.current.data.violations).toHaveLength(1);
      });
    });
  });

  // ============================================================================
  // Violation Detail Hook - useLicenseViolation
  // ============================================================================

  describe('useLicenseViolation', () => {
    const mockViolation = createMockLicenseViolation();

    it('sets loading state during fetch', async () => {
      mockApi.getViolation.mockResolvedValue(mockViolation);

      const { result } = renderHook(() => useLicenseViolation(mockViolation.id));

      expect(result.current.isLoading).toBe(true);

      await waitFor(() => {
        expect(result.current.isLoading).toBe(false);
      });
    });

    it('loads violation when id is provided', async () => {
      mockApi.getViolation.mockResolvedValue(mockViolation);

      const { result } = renderHook(() => useLicenseViolation(mockViolation.id));

      await waitFor(() => {
        expect(result.current.data).toEqual(mockViolation);
      });

      expect(mockApi.getViolation).toHaveBeenCalledWith(mockViolation.id);
    });

    it('returns violation as data property', async () => {
      mockApi.getViolation.mockResolvedValue(mockViolation);

      const { result } = renderHook(() => useLicenseViolation(mockViolation.id));

      await waitFor(() => {
        expect(result.current.data).not.toBeNull();
      });

      expect(result.current.data).toEqual(mockViolation);
      expect(result.current.data?.id).toBe(mockViolation.id);
    });

    it('does not fetch when id is empty string', () => {
      const { result } = renderHook(() => useLicenseViolation(''));

      expect(result.current.data).toBeNull();
      expect(mockApi.getViolation).not.toHaveBeenCalled();
    });

    it('handles API errors', async () => {
      const error = new Error('Violation not found');
      mockApi.getViolation.mockRejectedValue(error);

      const { result } = renderHook(() => useLicenseViolation('invalid-id'));

      await waitFor(() => {
        expect(result.current.error).toBe('Violation not found');
      });

      expect(result.current.data).toBeNull();
    });

    it('provides refetch function', async () => {
      mockApi.getViolation.mockResolvedValue(mockViolation);

      const { result } = renderHook(() => useLicenseViolation(mockViolation.id));

      await waitFor(() => {
        expect(result.current.data).toEqual(mockViolation);
      });

      jest.clearAllMocks();
      mockApi.getViolation.mockResolvedValue(mockViolation);

      await act(async () => {
        await result.current.refetch();
      });

      expect(mockApi.getViolation).toHaveBeenCalledWith(mockViolation.id);
    });
  });

  // ============================================================================
  // Resolve Violation Mutation - useResolveViolation
  // ============================================================================

  describe('useResolveViolation', () => {
    const violationId = 'violation-123';
    const note = 'Dependency updated to MIT-licensed version';
    const resolvedViolation = createMockLicenseViolation({
      id: violationId,
      status: 'resolved',
      resolution_note: note,
    });

    it('initializes with not loading state', () => {
      const { result } = renderHook(() => useResolveViolation());

      expect(result.current.isLoading).toBe(false);
    });

    it('resolves violation with note', async () => {
      mockApi.resolveViolation.mockResolvedValue(resolvedViolation);

      const { result } = renderHook(() => useResolveViolation());

      await act(async () => {
        const response = await result.current.mutateAsync({
          id: violationId,
          note,
        });
        expect(response.status).toBe('resolved');
      });

      expect(mockApi.resolveViolation).toHaveBeenCalledWith(violationId, note);
    });

    it('resolves violation without note', async () => {
      mockApi.resolveViolation.mockResolvedValue(resolvedViolation);

      const { result } = renderHook(() => useResolveViolation());

      await act(async () => {
        await result.current.mutateAsync({
          id: violationId,
        });
      });

      expect(mockApi.resolveViolation).toHaveBeenCalledWith(violationId, undefined);
    });

    it('clears error on successful resolution', async () => {
      mockApi.resolveViolation.mockRejectedValueOnce(
        new Error('Resolution failed')
      );

      const { result } = renderHook(() => useResolveViolation());

      let thrownError: Error | null = null;
      await act(async () => {
        try {
          await result.current.mutateAsync({
            id: violationId,
            note,
          });
        } catch (err) {
          thrownError = err as Error;
        }
      });

      expect(result.current.error).toBe('Resolution failed');

      mockApi.resolveViolation.mockResolvedValueOnce(resolvedViolation);

      await act(async () => {
        await result.current.mutateAsync({
          id: violationId,
          note,
        });
      });

      expect(result.current.error).toBeNull();
      expect(result.current.isLoading).toBe(false);
    });

    it('handles resolution errors', async () => {
      const error = new Error('Cannot resolve approved exception');
      mockApi.resolveViolation.mockRejectedValue(error);

      const { result } = renderHook(() => useResolveViolation());

      let thrownError: Error | null = null;
      await act(async () => {
        try {
          await result.current.mutateAsync({
            id: violationId,
            note,
          });
        } catch (err) {
          thrownError = err as Error;
        }
      });

      expect(result.current.error).toBe('Cannot resolve approved exception');
      expect(thrownError).toEqual(error);
    });
  });

  // ============================================================================
  // Grant Violation Exception Mutation - useGrantViolationException
  // ============================================================================

  describe('useGrantViolationException', () => {
    const violationId = 'violation-123';
    const note = 'Internal corporate dependency';
    const exceptionViolation = createMockLicenseViolation({
      id: violationId,
      status: 'exception_granted',
    });

    it('initializes with not loading state', () => {
      const { result } = renderHook(() => useGrantViolationException());

      expect(result.current.isLoading).toBe(false);
    });

    it('grants exception with note', async () => {
      mockApi.grantException.mockResolvedValue(exceptionViolation);

      const { result } = renderHook(() => useGrantViolationException());

      await act(async () => {
        const response = await result.current.mutateAsync({
          id: violationId,
          note,
        });
        expect(response.status).toBe('exception_granted');
      });

      expect(mockApi.grantException).toHaveBeenCalledWith(violationId, note);
    });

    it('clears error on successful grant', async () => {
      mockApi.grantException.mockRejectedValueOnce(
        new Error('Grant failed')
      );

      const { result } = renderHook(() => useGrantViolationException());

      let thrownError: Error | null = null;
      await act(async () => {
        try {
          await result.current.mutateAsync({
            id: violationId,
            note,
          });
        } catch (err) {
          thrownError = err as Error;
        }
      });

      expect(result.current.error).toBe('Grant failed');

      mockApi.grantException.mockResolvedValueOnce(exceptionViolation);

      await act(async () => {
        await result.current.mutateAsync({
          id: violationId,
          note,
        });
      });

      expect(result.current.error).toBeNull();
      expect(result.current.isLoading).toBe(false);
    });

    it('handles grant errors', async () => {
      const error = new Error('Exception already granted');
      mockApi.grantException.mockRejectedValue(error);

      const { result } = renderHook(() => useGrantViolationException());

      let thrownError: Error | null = null;
      await act(async () => {
        try {
          await result.current.mutateAsync({
            id: violationId,
            note,
          });
        } catch (err) {
          thrownError = err as Error;
        }
      });

      expect(result.current.error).toBe('Exception already granted');
      expect(thrownError).toEqual(error);
    });
  });

  // ============================================================================
  // Exception Workflow Mutations
  // ============================================================================

  describe('useRequestException', () => {
    const violationId = 'violation-123';
    const justification = 'This is a critical business dependency';
    const expiresAt = '2024-06-15T00:00:00Z';
    const requestedViolation = createMockLicenseViolation({
      id: violationId,
      status: 'open',
    });

    it('initializes with not loading state', () => {
      const { result } = renderHook(() => useRequestException());

      expect(result.current.isLoading).toBe(false);
    });

    it('requests exception with justification', async () => {
      mockApi.requestException.mockResolvedValue(requestedViolation);

      const { result } = renderHook(() => useRequestException());

      await act(async () => {
        const response = await result.current.mutateAsync({
          id: violationId,
          justification,
        });
        expect(response).toEqual(requestedViolation);
      });

      expect(mockApi.requestException).toHaveBeenCalledWith(
        violationId,
        justification,
        undefined
      );
    });

    it('requests exception with expiration date', async () => {
      mockApi.requestException.mockResolvedValue(requestedViolation);

      const { result } = renderHook(() => useRequestException());

      await act(async () => {
        await result.current.mutateAsync({
          id: violationId,
          justification,
          expiresAt,
        });
      });

      expect(mockApi.requestException).toHaveBeenCalledWith(
        violationId,
        justification,
        expiresAt
      );
    });

    it('handles request errors', async () => {
      const error = new Error('Justification too short');
      mockApi.requestException.mockRejectedValue(error);

      const { result } = renderHook(() => useRequestException());

      let thrownError: Error | null = null;
      await act(async () => {
        try {
          await result.current.mutateAsync({
            id: violationId,
            justification: '',
          });
        } catch (err) {
          thrownError = err as Error;
        }
      });

      expect(result.current.error).toBe('Justification too short');
      expect(thrownError).toEqual(error);
    });
  });

  describe('useApproveException', () => {
    const violationId = 'violation-123';
    const approvedViolation = createMockLicenseViolation({
      id: violationId,
      status: 'exception_granted',
    });

    it('initializes with not loading state', () => {
      const { result } = renderHook(() => useApproveException());

      expect(result.current.isLoading).toBe(false);
    });

    it('approves exception with notes', async () => {
      const notes = 'Approved by compliance team';
      mockApi.approveException.mockResolvedValue(approvedViolation);

      const { result } = renderHook(() => useApproveException());

      await act(async () => {
        const response = await result.current.mutateAsync({
          id: violationId,
          notes,
        });
        expect(response.status).toBe('exception_granted');
      });

      expect(mockApi.approveException).toHaveBeenCalledWith(
        violationId,
        notes,
        undefined
      );
    });

    it('approves exception with expiration date', async () => {
      const expiresAt = '2024-12-31T00:00:00Z';
      mockApi.approveException.mockResolvedValue(approvedViolation);

      const { result } = renderHook(() => useApproveException());

      await act(async () => {
        await result.current.mutateAsync({
          id: violationId,
          expiresAt,
        });
      });

      expect(mockApi.approveException).toHaveBeenCalledWith(
        violationId,
        undefined,
        expiresAt
      );
    });

    it('approves exception without notes or expiration', async () => {
      mockApi.approveException.mockResolvedValue(approvedViolation);

      const { result } = renderHook(() => useApproveException());

      await act(async () => {
        await result.current.mutateAsync({
          id: violationId,
        });
      });

      expect(mockApi.approveException).toHaveBeenCalledWith(
        violationId,
        undefined,
        undefined
      );
    });

    it('handles approve errors', async () => {
      const error = new Error('No pending exception request');
      mockApi.approveException.mockRejectedValue(error);

      const { result } = renderHook(() => useApproveException());

      let thrownError: Error | null = null;
      await act(async () => {
        try {
          await result.current.mutateAsync({
            id: violationId,
          });
        } catch (err) {
          thrownError = err as Error;
        }
      });

      expect(result.current.error).toBe('No pending exception request');
      expect(thrownError).toEqual(error);
    });
  });

  describe('useRejectException', () => {
    const violationId = 'violation-123';
    const reason = 'GPL license not permitted in enterprise deployments';
    const rejectedViolation = createMockLicenseViolation({
      id: violationId,
      status: 'open',
    });

    it('initializes with not loading state', () => {
      const { result } = renderHook(() => useRejectException());

      expect(result.current.isLoading).toBe(false);
    });

    it('rejects exception with reason', async () => {
      mockApi.rejectException.mockResolvedValue(rejectedViolation);

      const { result } = renderHook(() => useRejectException());

      await act(async () => {
        const response = await result.current.mutateAsync({
          id: violationId,
          reason,
        });
        expect(response.status).toBe('open');
      });

      expect(mockApi.rejectException).toHaveBeenCalledWith(violationId, reason);
    });

    it('rejects exception without reason', async () => {
      mockApi.rejectException.mockResolvedValue(rejectedViolation);

      const { result } = renderHook(() => useRejectException());

      await act(async () => {
        await result.current.mutateAsync({
          id: violationId,
        });
      });

      expect(mockApi.rejectException).toHaveBeenCalledWith(violationId, undefined);
    });

    it('clears error on successful rejection', async () => {
      mockApi.rejectException.mockRejectedValueOnce(
        new Error('Rejection failed')
      );

      const { result } = renderHook(() => useRejectException());

      let thrownError: Error | null = null;
      await act(async () => {
        try {
          await result.current.mutateAsync({
            id: violationId,
            reason,
          });
        } catch (err) {
          thrownError = err as Error;
        }
      });

      expect(result.current.error).toBe('Rejection failed');

      mockApi.rejectException.mockResolvedValueOnce(rejectedViolation);

      await act(async () => {
        await result.current.mutateAsync({
          id: violationId,
          reason,
        });
      });

      expect(result.current.error).toBeNull();
      expect(result.current.isLoading).toBe(false);
    });

    it('handles reject errors', async () => {
      const error = new Error('Exception already approved');
      mockApi.rejectException.mockRejectedValue(error);

      const { result } = renderHook(() => useRejectException());

      let thrownError: Error | null = null;
      await act(async () => {
        try {
          await result.current.mutateAsync({
            id: violationId,
            reason,
          });
        } catch (err) {
          thrownError = err as Error;
        }
      });

      expect(result.current.error).toBe('Exception already approved');
      expect(thrownError).toEqual(error);
    });
  });

  // ============================================================================
  // Error Handling Edge Cases
  // ============================================================================

  describe('error handling for generic errors', () => {
    it('handles non-Error exceptions in list hooks', async () => {
      mockApi.listPolicies.mockRejectedValue('String error');

      const { result } = renderHook(() => useLicensePolicies());

      await waitFor(() => {
        expect(result.current.isLoading).toBe(false);
      });

      expect(result.current.error).toBe('Failed to fetch license policies');
    });

    it('handles non-Error exceptions in detail hooks', async () => {
      mockApi.getPolicy.mockRejectedValue(null);

      const { result } = renderHook(() => useLicensePolicy('test-id'));

      await waitFor(() => {
        expect(result.current.isLoading).toBe(false);
      });

      expect(result.current.error).toBe('Failed to fetch license policy');
    });

    it('handles non-Error exceptions in mutations', async () => {
      mockApi.createPolicy.mockRejectedValue(null);

      const { result } = renderHook(() => useCreateLicensePolicy());
      const policyData: CreateLicensePolicyData = {
        name: 'Test',
        policy_type: 'allowlist',
        enforcement_level: 'warn',
      };

      let thrownError: Error | null = null;
      await act(async () => {
        try {
          await result.current.mutateAsync(policyData);
        } catch (err) {
          thrownError = err;
        }
      });

      expect(result.current.error).toBe('Failed to create license policy');
      expect(thrownError).toBeNull();
    });
  });
});

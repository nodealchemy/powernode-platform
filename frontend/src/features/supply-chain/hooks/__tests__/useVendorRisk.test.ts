/**
 * Comprehensive test suite for vendor risk hooks
 *
 * Tests all 8 vendor risk hooks:
 * - useVendors: List vendors with filters
 * - useVendor: Get single vendor detail
 * - useVendorRiskDashboard: Get risk dashboard data
 * - useCreateVendor: Create vendor mutation
 * - useUpdateVendor: Update vendor mutation
 * - useDeleteVendor: Delete vendor mutation
 * - useStartAssessment: Start risk assessment mutation
 * - useSendQuestionnaire: Send questionnaire mutation
 */

import { renderHook, waitFor, act } from '@testing-library/react';
import {
  useVendors,
  useVendor,
  useVendorRiskDashboard,
  useCreateVendor,
  useUpdateVendor,
  useDeleteVendor,
  useStartAssessment,
  useSendQuestionnaire,
} from '../useVendorRisk';
import { vendorRiskApi } from '../../services/vendorRiskApi';
import {
  createMockVendor,
  createMockVendorDetail,
  createMockVendorList,
  createMockRiskAssessment,
  createMockQuestionnaire,
  createMockPagination,
} from '../../testing/mockFactories';
import type { RiskAssessment, Questionnaire } from '../../types/vendor';

// Mock the vendorRiskApi service
jest.mock('../../services/vendorRiskApi');
const mockApi = vendorRiskApi as jest.Mocked<typeof vendorRiskApi>;

describe('Vendor Risk Hooks', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  // ==========================================================================
  // useVendors Hook Tests
  // ==========================================================================

  describe('useVendors', () => {
    it('should fetch vendors on mount', async () => {
      const mockVendors = createMockVendorList(3);
      const mockPagination = createMockPagination();

      mockApi.listVendors.mockResolvedValue({
        vendors: mockVendors,
        pagination: mockPagination,
      });

      const { result } = renderHook(() => useVendors());

      expect(result.current.loading).toBe(true);
      expect(result.current.vendors).toEqual([]);

      await waitFor(() => {
        expect(result.current.loading).toBe(false);
      });

      expect(result.current.vendors).toEqual(mockVendors);
      expect(result.current.pagination).toEqual(mockPagination);
      expect(result.current.error).toBeNull();
      expect(mockApi.listVendors).toHaveBeenCalledWith({
        page: undefined,
        per_page: undefined,
        risk_tier: undefined,
        status: undefined,
        search: undefined,
      });
    });

    it('should apply filter options', async () => {
      const mockVendors = createMockVendorList(2);
      const mockPagination = createMockPagination({ total_count: 2 });

      mockApi.listVendors.mockResolvedValue({
        vendors: mockVendors,
        pagination: mockPagination,
      });

      const options = {
        page: 2,
        perPage: 10,
        riskTier: 'critical' as const,
        status: 'active' as const,
        search: 'test vendor',
      };

      const { result } = renderHook(() => useVendors(options));

      await waitFor(() => {
        expect(result.current.loading).toBe(false);
      });

      expect(mockApi.listVendors).toHaveBeenCalledWith({
        page: 2,
        per_page: 10,
        risk_tier: 'critical',
        status: 'active',
        search: 'test vendor',
      });
    });

    it('should handle loading state', async () => {
      const mockVendors = createMockVendorList(1);

      mockApi.listVendors.mockImplementation(
        () =>
          new Promise((resolve) =>
            setTimeout(
              () =>
                resolve({
                  vendors: mockVendors,
                  pagination: createMockPagination(),
                }),
              100
            )
          )
      );

      const { result } = renderHook(() => useVendors());

      expect(result.current.loading).toBe(true);

      await waitFor(() => {
        expect(result.current.loading).toBe(false);
      });
    });

    it('should handle errors', async () => {
      const errorMessage = 'Failed to fetch vendors';
      mockApi.listVendors.mockRejectedValue(new Error(errorMessage));

      const { result } = renderHook(() => useVendors());

      await waitFor(() => {
        expect(result.current.loading).toBe(false);
      });

      expect(result.current.error).toBe(errorMessage);
      expect(result.current.vendors).toEqual([]);
      expect(result.current.pagination).toBeNull();
    });

    it('should handle errors without message', async () => {
      mockApi.listVendors.mockRejectedValue('Unknown error');

      const { result } = renderHook(() => useVendors());

      await waitFor(() => {
        expect(result.current.loading).toBe(false);
      });

      expect(result.current.error).toBe('Failed to fetch vendors');
    });

    it('should provide refresh function', async () => {
      const mockVendors = createMockVendorList(1);

      mockApi.listVendors.mockResolvedValue({
        vendors: mockVendors,
        pagination: createMockPagination(),
      });

      const { result } = renderHook(() => useVendors());

      await waitFor(() => {
        expect(result.current.loading).toBe(false);
      });

      expect(mockApi.listVendors).toHaveBeenCalledTimes(1);

      await act(async () => {
        await result.current.refresh();
      });

      expect(mockApi.listVendors).toHaveBeenCalledTimes(2);
    });

    it('should refetch when options change', async () => {
      const mockVendors = createMockVendorList(1);

      mockApi.listVendors.mockResolvedValue({
        vendors: mockVendors,
        pagination: createMockPagination(),
      });

      const { result, rerender } = renderHook(
        ({ options }) => useVendors(options),
        {
          initialProps: { options: { page: 1 } },
        }
      );

      await waitFor(() => {
        expect(result.current.loading).toBe(false);
      });

      expect(mockApi.listVendors).toHaveBeenCalledTimes(1);

      rerender({ options: { page: 2 } });

      await waitFor(() => {
        expect(mockApi.listVendors).toHaveBeenCalledTimes(2);
      });

      expect(mockApi.listVendors).toHaveBeenLastCalledWith({
        page: 2,
        per_page: undefined,
        risk_tier: undefined,
        status: undefined,
        search: undefined,
      });
    });
  });

  // ==========================================================================
  // useVendor Hook Tests
  // ==========================================================================

  describe('useVendor', () => {
    it('should fetch vendor detail when id is provided', async () => {
      const mockVendor = createMockVendorDetail();

      mockApi.getVendor.mockResolvedValue(mockVendor);

      const { result } = renderHook(() => useVendor(mockVendor.id));

      expect(result.current.loading).toBe(true);
      expect(result.current.vendor).toBeNull();

      await waitFor(() => {
        expect(result.current.loading).toBe(false);
      });

      expect(result.current.vendor).toEqual(mockVendor);
      expect(result.current.error).toBeNull();
      expect(mockApi.getVendor).toHaveBeenCalledWith(mockVendor.id);
    });

    it('should not fetch when id is null', async () => {
      const { result } = renderHook(() => useVendor(null));

      await waitFor(() => {
        expect(result.current.loading).toBe(false);
      }, { timeout: 100 });

      expect(mockApi.getVendor).not.toHaveBeenCalled();
      expect(result.current.vendor).toBeNull();
      expect(result.current.error).toBeNull();
    });

    it('should handle loading state', async () => {
      const mockVendor = createMockVendorDetail();

      mockApi.getVendor.mockImplementation(
        () =>
          new Promise((resolve) =>
            setTimeout(() => resolve(mockVendor), 100)
          )
      );

      const { result } = renderHook(() => useVendor(mockVendor.id));

      expect(result.current.loading).toBe(true);

      await waitFor(() => {
        expect(result.current.loading).toBe(false);
      });
    });

    it('should handle errors', async () => {
      const errorMessage = 'Failed to fetch vendor';
      mockApi.getVendor.mockRejectedValue(new Error(errorMessage));

      const { result } = renderHook(() => useVendor('vendor-123'));

      await waitFor(() => {
        expect(result.current.loading).toBe(false);
      });

      expect(result.current.error).toBe(errorMessage);
      expect(result.current.vendor).toBeNull();
    });

    it('should handle errors without message', async () => {
      mockApi.getVendor.mockRejectedValue('Unknown error');

      const { result } = renderHook(() => useVendor('vendor-123'));

      await waitFor(() => {
        expect(result.current.loading).toBe(false);
      });

      expect(result.current.error).toBe('Failed to fetch vendor');
    });

    it('should refetch when id changes', async () => {
      const mockVendor1 = createMockVendorDetail({ id: 'vendor-1' });
      const mockVendor2 = createMockVendorDetail({ id: 'vendor-2' });

      mockApi.getVendor.mockImplementation((id) =>
        Promise.resolve(
          id === 'vendor-1' ? mockVendor1 : mockVendor2
        )
      );

      const { result, rerender } = renderHook(({ id }) => useVendor(id), {
        initialProps: { id: 'vendor-1' as string | null },
      });

      await waitFor(() => {
        expect(result.current.loading).toBe(false);
      });

      expect(result.current.vendor).toEqual(mockVendor1);
      expect(mockApi.getVendor).toHaveBeenCalledWith('vendor-1');

      rerender({ id: 'vendor-2' });

      await waitFor(() => {
        expect(result.current.vendor).toEqual(mockVendor2);
      });

      expect(mockApi.getVendor).toHaveBeenCalledWith('vendor-2');
    });

    it('should provide refresh function', async () => {
      const mockVendor = createMockVendorDetail();

      mockApi.getVendor.mockResolvedValue(mockVendor);

      const { result } = renderHook(() => useVendor(mockVendor.id));

      await waitFor(() => {
        expect(result.current.loading).toBe(false);
      });

      expect(mockApi.getVendor).toHaveBeenCalledTimes(1);

      await act(async () => {
        await result.current.refresh();
      });

      expect(mockApi.getVendor).toHaveBeenCalledTimes(2);
    });

    it('should include vendor detail data (assessments, questionnaires, monitoring_events)', async () => {
      const mockAssessment = createMockRiskAssessment();
      const mockQuestionnaire = createMockQuestionnaire();

      const mockVendor = createMockVendorDetail({
        assessments: [mockAssessment],
        questionnaires: [mockQuestionnaire],
        monitoring_events: [
          {
            id: 'event-1',
            event_type: 'security_incident',
            severity: 'high',
            message: 'Test incident',
            created_at: new Date().toISOString(),
          },
        ],
      });

      mockApi.getVendor.mockResolvedValue(mockVendor);

      const { result } = renderHook(() => useVendor(mockVendor.id));

      await waitFor(() => {
        expect(result.current.loading).toBe(false);
      });

      expect(result.current.vendor?.assessments).toEqual([mockAssessment]);
      expect(result.current.vendor?.questionnaires).toEqual([
        mockQuestionnaire,
      ]);
      expect(result.current.vendor?.monitoring_events).toHaveLength(1);
    });
  });

  // ==========================================================================
  // useVendorRiskDashboard Hook Tests
  // ==========================================================================

  describe('useVendorRiskDashboard', () => {
    it('should fetch dashboard data on mount', async () => {
      const mockDashboardData = {
        total_vendors: 25,
        critical_vendors: 2,
        high_risk_vendors: 5,
        vendors_needing_assessment: 3,
        upcoming_assessments: [
          {
            vendor_id: 'vendor-1',
            vendor_name: 'Test Vendor',
            due_date: new Date(Date.now() + 86400000).toISOString(),
          },
        ],
        risk_distribution: {
          critical: 2,
          high: 5,
          medium: 10,
          low: 8,
        },
      };

      mockApi.getRiskDashboard.mockResolvedValue(mockDashboardData);

      const { result } = renderHook(() => useVendorRiskDashboard());

      expect(result.current.loading).toBe(true);
      expect(result.current.data).toBeNull();

      await waitFor(() => {
        expect(result.current.loading).toBe(false);
      });

      expect(result.current.data).toEqual(mockDashboardData);
      expect(result.current.error).toBeNull();
      expect(mockApi.getRiskDashboard).toHaveBeenCalled();
    });

    it('should handle loading state', async () => {
      const mockDashboardData = {
        total_vendors: 25,
        critical_vendors: 2,
        high_risk_vendors: 5,
        vendors_needing_assessment: 3,
        upcoming_assessments: [],
        risk_distribution: {
          critical: 2,
          high: 5,
          medium: 10,
          low: 8,
        },
      };

      mockApi.getRiskDashboard.mockImplementation(
        () =>
          new Promise((resolve) =>
            setTimeout(() => resolve(mockDashboardData), 100)
          )
      );

      const { result } = renderHook(() => useVendorRiskDashboard());

      expect(result.current.loading).toBe(true);

      await waitFor(() => {
        expect(result.current.loading).toBe(false);
      });
    });

    it('should handle errors', async () => {
      const errorMessage = 'Failed to fetch dashboard';
      mockApi.getRiskDashboard.mockRejectedValue(new Error(errorMessage));

      const { result } = renderHook(() => useVendorRiskDashboard());

      await waitFor(() => {
        expect(result.current.loading).toBe(false);
      });

      expect(result.current.error).toBe(errorMessage);
      expect(result.current.data).toBeNull();
    });

    it('should handle errors without message', async () => {
      mockApi.getRiskDashboard.mockRejectedValue('Unknown error');

      const { result } = renderHook(() => useVendorRiskDashboard());

      await waitFor(() => {
        expect(result.current.loading).toBe(false);
      });

      expect(result.current.error).toBe('Failed to fetch dashboard');
    });

    it('should provide refresh function', async () => {
      const mockDashboardData = {
        total_vendors: 25,
        critical_vendors: 2,
        high_risk_vendors: 5,
        vendors_needing_assessment: 3,
        upcoming_assessments: [],
        risk_distribution: {
          critical: 2,
          high: 5,
          medium: 10,
          low: 8,
        },
      };

      mockApi.getRiskDashboard.mockResolvedValue(mockDashboardData);

      const { result } = renderHook(() => useVendorRiskDashboard());

      await waitFor(() => {
        expect(result.current.loading).toBe(false);
      });

      expect(mockApi.getRiskDashboard).toHaveBeenCalledTimes(1);

      await act(async () => {
        await result.current.refresh();
      });

      expect(mockApi.getRiskDashboard).toHaveBeenCalledTimes(2);
    });

    it('should have correct dashboard data shape', async () => {
      const mockDashboardData = {
        total_vendors: 25,
        critical_vendors: 2,
        high_risk_vendors: 5,
        vendors_needing_assessment: 3,
        upcoming_assessments: [
          {
            vendor_id: 'vendor-1',
            vendor_name: 'Critical Vendor',
            due_date: new Date().toISOString(),
          },
          {
            vendor_id: 'vendor-2',
            vendor_name: 'High Risk Vendor',
            due_date: new Date().toISOString(),
          },
        ],
        risk_distribution: {
          critical: 2,
          high: 5,
          medium: 10,
          low: 8,
        },
      };

      mockApi.getRiskDashboard.mockResolvedValue(mockDashboardData);

      const { result } = renderHook(() => useVendorRiskDashboard());

      await waitFor(() => {
        expect(result.current.loading).toBe(false);
      });

      expect(result.current.data).toBeDefined();
      expect(result.current.data?.total_vendors).toBe(25);
      expect(result.current.data?.critical_vendors).toBe(2);
      expect(result.current.data?.high_risk_vendors).toBe(5);
      expect(result.current.data?.vendors_needing_assessment).toBe(3);
      expect(result.current.data?.upcoming_assessments).toHaveLength(2);
      expect(result.current.data?.risk_distribution).toEqual({
        critical: 2,
        high: 5,
        medium: 10,
        low: 8,
      });
    });
  });

  // ==========================================================================
  // useCreateVendor Hook Tests
  // ==========================================================================

  describe('useCreateVendor', () => {
    it('should create vendor successfully', async () => {
      const mockVendor = createMockVendor();

      mockApi.createVendor.mockResolvedValue(mockVendor);

      const { result } = renderHook(() => useCreateVendor());

      expect(result.current.isLoading).toBe(false);
      expect(result.current.error).toBeNull();

      const createData = {
        name: 'New Vendor',
        vendor_type: 'saas' as const,
        contact_name: 'John Doe',
        contact_email: 'john@example.com',
      };

      await act(async () => {
        const response = await result.current.mutateAsync(createData);
        expect(response).toEqual(mockVendor);
      });

      expect(mockApi.createVendor).toHaveBeenCalledWith(createData);
      expect(result.current.isLoading).toBe(false);
      expect(result.current.error).toBeNull();
    });

    it('should initialize with no error', async () => {
      const mockVendor = createMockVendor();
      mockApi.createVendor.mockResolvedValue(mockVendor);

      const { result } = renderHook(() => useCreateVendor());

      expect(result.current.isLoading).toBe(false);
      expect(result.current.error).toBeNull();
    });

    it('should handle errors and rethrow', async () => {
      const errorMessage = 'Failed to create vendor';
      mockApi.createVendor.mockRejectedValue(new Error(errorMessage));

      const { result } = renderHook(() => useCreateVendor());

      const createData = {
        name: 'New Vendor',
        vendor_type: 'saas' as const,
      };

      let caughtError: string | null = null;

      await act(async () => {
        try {
          await result.current.mutateAsync(createData);
        } catch (err) {
          caughtError = (err as Error).message;
        }
      });

      expect(caughtError).toBe(errorMessage);
      expect(result.current.error).toBe(errorMessage);
      expect(result.current.isLoading).toBe(false);
    });

    it('should handle errors without message', async () => {
      mockApi.createVendor.mockRejectedValue('Unknown error');

      const { result } = renderHook(() => useCreateVendor());

      const createData = {
        name: 'New Vendor',
        vendor_type: 'saas' as const,
      };

      await act(async () => {
        try {
          await result.current.mutateAsync(createData);
        } catch (_err) {
          // Expected
        }
      });

      expect(result.current.error).toBe('Failed to create vendor');
    });

    it('should return created vendor', async () => {
      const mockVendor = createMockVendor({
        name: 'Custom Vendor',
        handles_pii: true,
      });

      mockApi.createVendor.mockResolvedValue(mockVendor);

      const { result } = renderHook(() => useCreateVendor());

      let returnedVendor;

      await act(async () => {
        returnedVendor = await result.current.mutateAsync({
          name: 'Custom Vendor',
          vendor_type: 'saas',
          handles_pii: true,
        });
      });

      expect(returnedVendor).toEqual(mockVendor);
    });
  });

  // ==========================================================================
  // useUpdateVendor Hook Tests
  // ==========================================================================

  describe('useUpdateVendor', () => {
    it('should update vendor successfully', async () => {
      const mockVendor = createMockVendor({ risk_tier: 'high' });

      mockApi.updateVendor.mockResolvedValue(mockVendor);

      const { result } = renderHook(() => useUpdateVendor());

      const updateData = {
        id: 'vendor-123',
        data: { risk_tier: 'high' as const, status: 'active' as const },
      };

      await act(async () => {
        const response = await result.current.mutateAsync(updateData);
        expect(response).toEqual(mockVendor);
      });

      expect(mockApi.updateVendor).toHaveBeenCalledWith(
        'vendor-123',
        updateData.data
      );
    });

    it('should clear error on successful mutation', async () => {
      const mockVendor = createMockVendor();
      mockApi.updateVendor.mockResolvedValue(mockVendor);

      const { result } = renderHook(() => useUpdateVendor());

      await act(async () => {
        await result.current.mutateAsync({
          id: 'vendor-123',
          data: { status: 'inactive' },
        });
      });

      expect(result.current.error).toBeNull();
    });

    it('should handle errors and rethrow', async () => {
      const errorMessage = 'Failed to update vendor';
      mockApi.updateVendor.mockRejectedValue(new Error(errorMessage));

      const { result } = renderHook(() => useUpdateVendor());

      let caughtError: string | null = null;

      await act(async () => {
        try {
          await result.current.mutateAsync({
            id: 'vendor-123',
            data: { status: 'inactive' },
          });
        } catch (err) {
          caughtError = (err as Error).message;
        }
      });

      expect(caughtError).toBe(errorMessage);
      expect(result.current.error).toBe(errorMessage);
    });

    it('should support partial vendor updates', async () => {
      const mockVendor = createMockVendor();

      mockApi.updateVendor.mockResolvedValue(mockVendor);

      const { result } = renderHook(() => useUpdateVendor());

      const updateData = {
        id: 'vendor-123',
        data: { certifications: ['SOC2', 'ISO27001'] },
      };

      await act(async () => {
        await result.current.mutateAsync(updateData);
      });

      expect(mockApi.updateVendor).toHaveBeenCalledWith(
        'vendor-123',
        updateData.data
      );
    });
  });

  // ==========================================================================
  // useDeleteVendor Hook Tests
  // ==========================================================================

  describe('useDeleteVendor', () => {
    it('should delete vendor successfully', async () => {
      mockApi.deleteVendor.mockResolvedValue(undefined);

      const { result } = renderHook(() => useDeleteVendor());

      expect(result.current.isLoading).toBe(false);
      expect(result.current.error).toBeNull();

      await act(async () => {
        await result.current.mutateAsync('vendor-123');
      });

      expect(mockApi.deleteVendor).toHaveBeenCalledWith('vendor-123');
      expect(result.current.isLoading).toBe(false);
      expect(result.current.error).toBeNull();
    });

    it('should clear error on successful deletion', async () => {
      mockApi.deleteVendor.mockResolvedValue(undefined);

      const { result } = renderHook(() => useDeleteVendor());

      await act(async () => {
        await result.current.mutateAsync('vendor-123');
      });

      expect(result.current.error).toBeNull();
    });

    it('should handle errors and rethrow', async () => {
      const errorMessage = 'Failed to delete vendor';
      mockApi.deleteVendor.mockRejectedValue(new Error(errorMessage));

      const { result } = renderHook(() => useDeleteVendor());

      let caughtError: string | null = null;

      await act(async () => {
        try {
          await result.current.mutateAsync('vendor-123');
        } catch (err) {
          caughtError = (err as Error).message;
        }
      });

      expect(caughtError).toBe(errorMessage);
      expect(result.current.error).toBe(errorMessage);
    });

    it('should handle errors without message', async () => {
      mockApi.deleteVendor.mockRejectedValue('Unknown error');

      const { result } = renderHook(() => useDeleteVendor());

      await act(async () => {
        try {
          await result.current.mutateAsync('vendor-123');
        } catch (_err) {
          // Expected
        }
      });

      expect(result.current.error).toBe('Failed to delete vendor');
    });
  });

  // ==========================================================================
  // useStartAssessment Hook Tests
  // ==========================================================================

  describe('useStartAssessment', () => {
    it('should start assessment successfully', async () => {
      const mockAssessment = createMockRiskAssessment();

      mockApi.startAssessment.mockResolvedValue(mockAssessment);

      const { result } = renderHook(() => useStartAssessment());

      expect(result.current.isLoading).toBe(false);
      expect(result.current.error).toBeNull();

      const params = {
        vendorId: 'vendor-123',
        assessmentType: 'periodic',
      };

      await act(async () => {
        const response = await result.current.mutateAsync(params);
        expect(response).toEqual(mockAssessment);
      });

      expect(mockApi.startAssessment).toHaveBeenCalledWith(
        'vendor-123',
        'periodic'
      );
      expect(result.current.isLoading).toBe(false);
      expect(result.current.error).toBeNull();
    });

    it('should clear error on successful assessment start', async () => {
      const mockAssessment = createMockRiskAssessment();
      mockApi.startAssessment.mockResolvedValue(mockAssessment);

      const { result } = renderHook(() => useStartAssessment());

      await act(async () => {
        await result.current.mutateAsync({
          vendorId: 'vendor-123',
          assessmentType: 'initial',
        });
      });

      expect(result.current.error).toBeNull();
    });

    it('should handle errors and rethrow', async () => {
      const errorMessage = 'Failed to start assessment';
      mockApi.startAssessment.mockRejectedValue(new Error(errorMessage));

      const { result } = renderHook(() => useStartAssessment());

      let caughtError: string | null = null;

      await act(async () => {
        try {
          await result.current.mutateAsync({
            vendorId: 'vendor-123',
            assessmentType: 'renewal',
          });
        } catch (err) {
          caughtError = (err as Error).message;
        }
      });

      expect(caughtError).toBe(errorMessage);
      expect(result.current.error).toBe(errorMessage);
    });

    it('should support different assessment types', async () => {
      const mockAssessment = createMockRiskAssessment();

      mockApi.startAssessment.mockResolvedValue(mockAssessment);

      const { result } = renderHook(() => useStartAssessment());

      const assessmentTypes = ['initial', 'periodic', 'incident', 'renewal'];

      for (const assessmentType of assessmentTypes) {
        await act(async () => {
          await result.current.mutateAsync({
            vendorId: 'vendor-123',
            assessmentType,
          });
        });
      }

      expect(mockApi.startAssessment).toHaveBeenCalledTimes(4);
      expect(mockApi.startAssessment).toHaveBeenNthCalledWith(1, 'vendor-123', 'initial');
      expect(mockApi.startAssessment).toHaveBeenNthCalledWith(2, 'vendor-123', 'periodic');
      expect(mockApi.startAssessment).toHaveBeenNthCalledWith(3, 'vendor-123', 'incident');
      expect(mockApi.startAssessment).toHaveBeenNthCalledWith(4, 'vendor-123', 'renewal');
    });

    it('should return assessment with correct fields', async () => {
      const mockAssessment = createMockRiskAssessment({
        assessment_type: 'periodic',
        status: 'in_progress',
        security_score: 85,
      });

      mockApi.startAssessment.mockResolvedValue(mockAssessment);

      const { result } = renderHook(() => useStartAssessment());

      let returnedAssessment: RiskAssessment | undefined;

      await act(async () => {
        returnedAssessment = await result.current.mutateAsync({
          vendorId: 'vendor-123',
          assessmentType: 'periodic',
        });
      });

      expect(returnedAssessment?.assessment_type).toBe('periodic');
      expect(returnedAssessment?.status).toBe('in_progress');
      expect(returnedAssessment?.security_score).toBe(85);
    });
  });

  // ==========================================================================
  // useSendQuestionnaire Hook Tests
  // ==========================================================================

  describe('useSendQuestionnaire', () => {
    it('should send questionnaire successfully', async () => {
      const mockQuestionnaire = createMockQuestionnaire();

      mockApi.sendQuestionnaire.mockResolvedValue(mockQuestionnaire);

      const { result } = renderHook(() => useSendQuestionnaire());

      expect(result.current.isLoading).toBe(false);
      expect(result.current.error).toBeNull();

      const params = {
        vendorId: 'vendor-123',
        templateId: 'template-456',
      };

      await act(async () => {
        const response = await result.current.mutateAsync(params);
        expect(response).toEqual(mockQuestionnaire);
      });

      expect(mockApi.sendQuestionnaire).toHaveBeenCalledWith(
        'vendor-123',
        'template-456'
      );
      expect(result.current.isLoading).toBe(false);
      expect(result.current.error).toBeNull();
    });

    it('should clear error on successful send', async () => {
      const mockQuestionnaire = createMockQuestionnaire();
      mockApi.sendQuestionnaire.mockResolvedValue(mockQuestionnaire);

      const { result } = renderHook(() => useSendQuestionnaire());

      await act(async () => {
        await result.current.mutateAsync({
          vendorId: 'vendor-123',
          templateId: 'template-456',
        });
      });

      expect(result.current.error).toBeNull();
    });

    it('should handle errors and rethrow', async () => {
      const errorMessage = 'Failed to send questionnaire';
      mockApi.sendQuestionnaire.mockRejectedValue(new Error(errorMessage));

      const { result } = renderHook(() => useSendQuestionnaire());

      let caughtError: string | null = null;

      await act(async () => {
        try {
          await result.current.mutateAsync({
            vendorId: 'vendor-123',
            templateId: 'template-456',
          });
        } catch (err) {
          caughtError = (err as Error).message;
        }
      });

      expect(caughtError).toBe(errorMessage);
      expect(result.current.error).toBe(errorMessage);
    });

    it('should handle errors without message', async () => {
      mockApi.sendQuestionnaire.mockRejectedValue('Unknown error');

      const { result } = renderHook(() => useSendQuestionnaire());

      await act(async () => {
        try {
          await result.current.mutateAsync({
            vendorId: 'vendor-123',
            templateId: 'template-456',
          });
        } catch (_err) {
          // Expected
        }
      });

      expect(result.current.error).toBe('Failed to send questionnaire');
    });

    it('should return questionnaire with correct fields', async () => {
      const mockQuestionnaire = createMockQuestionnaire({
        status: 'sent',
        response_count: 0,
        template_name: 'Q1 2024 Security Assessment',
      });

      mockApi.sendQuestionnaire.mockResolvedValue(mockQuestionnaire);

      const { result } = renderHook(() => useSendQuestionnaire());

      let returnedQuestionnaire: Questionnaire | undefined;

      await act(async () => {
        returnedQuestionnaire = await result.current.mutateAsync({
          vendorId: 'vendor-123',
          templateId: 'template-456',
        });
      });

      expect(returnedQuestionnaire?.status).toBe('sent');
      expect(returnedQuestionnaire?.response_count).toBe(0);
      expect(returnedQuestionnaire?.template_name).toBe(
        'Q1 2024 Security Assessment'
      );
    });

    it('should support multiple questionnaire sends', async () => {
      const mockQuestionnaire1 = createMockQuestionnaire({
        template_name: 'Template 1',
      });
      const mockQuestionnaire2 = createMockQuestionnaire({
        template_name: 'Template 2',
      });

      mockApi.sendQuestionnaire
        .mockResolvedValueOnce(mockQuestionnaire1)
        .mockResolvedValueOnce(mockQuestionnaire2);

      const { result } = renderHook(() => useSendQuestionnaire());

      let response1: Questionnaire | undefined, response2: Questionnaire | undefined;

      await act(async () => {
        response1 = await result.current.mutateAsync({
          vendorId: 'vendor-123',
          templateId: 'template-1',
        });

        response2 = await result.current.mutateAsync({
          vendorId: 'vendor-123',
          templateId: 'template-2',
        });
      });

      expect(response1?.template_name).toBe('Template 1');
      expect(response2?.template_name).toBe('Template 2');
      expect(mockApi.sendQuestionnaire).toHaveBeenCalledTimes(2);
    });
  });

  // ==========================================================================
  // Cross-Hook Integration Tests
  // ==========================================================================

  describe('Cross-Hook Integration', () => {
    it('should work with multiple hooks in same component', async () => {
      const mockVendors = createMockVendorList(1);
      const mockDashboard = {
        total_vendors: 1,
        critical_vendors: 0,
        high_risk_vendors: 0,
        vendors_needing_assessment: 0,
        upcoming_assessments: [],
        risk_distribution: { critical: 0, high: 0, medium: 0, low: 1 },
      };

      mockApi.listVendors.mockResolvedValue({
        vendors: mockVendors,
        pagination: createMockPagination(),
      });
      mockApi.getRiskDashboard.mockResolvedValue(mockDashboard);

      const { result: vendorsResult } = renderHook(() => useVendors());
      const { result: dashboardResult } = renderHook(() =>
        useVendorRiskDashboard()
      );

      await waitFor(() => {
        expect(vendorsResult.current.loading).toBe(false);
        expect(dashboardResult.current.loading).toBe(false);
      });

      expect(vendorsResult.current.vendors).toEqual(mockVendors);
      expect(dashboardResult.current.data).toEqual(mockDashboard);
    });
  });
});

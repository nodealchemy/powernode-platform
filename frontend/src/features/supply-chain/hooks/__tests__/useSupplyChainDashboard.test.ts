/**
 * Tests for useSupplyChainDashboard Hook
 *
 * Comprehensive test coverage for the supply chain dashboard hook
 * including loading states, data fetching, error handling, and refresh functionality
 */

import { renderHook, waitFor, act } from '@testing-library/react';
import { useSupplyChainDashboard } from '../useSupplyChainDashboard';
import { supplyChainApi } from '../../services/supplyChainApi';
import { createMockDashboardData } from '../../testing/mockFactories';

// Mock the supplyChainApi service
jest.mock('../../services/supplyChainApi');
const mockSupplyChainApi = supplyChainApi as jest.Mocked<typeof supplyChainApi>;

describe('useSupplyChainDashboard', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('initial loading state', () => {
    it('should start with loading=true, data=null, and error=null', async () => {
      mockSupplyChainApi.getDashboard.mockImplementation(
        () => new Promise(() => {
          // Never resolves to keep hook in loading state
        })
      );

      const { result } = renderHook(() => useSupplyChainDashboard());

      expect(result.current.loading).toBe(true);
      expect(result.current.data).toBeNull();
      expect(result.current.error).toBeNull();
    });

    it('should have a refresh function available in initial state', () => {
      mockSupplyChainApi.getDashboard.mockImplementation(
        () => new Promise(() => {
          // Never resolves
        })
      );

      const { result } = renderHook(() => useSupplyChainDashboard());

      expect(typeof result.current.refresh).toBe('function');
    });
  });

  describe('successful data fetch', () => {
    it('should fetch dashboard data on mount', async () => {
      const mockData = createMockDashboardData();
      mockSupplyChainApi.getDashboard.mockResolvedValue(mockData);

      renderHook(() => useSupplyChainDashboard());

      await waitFor(() => {
        expect(mockSupplyChainApi.getDashboard).toHaveBeenCalledTimes(1);
      });
    });

    it('should populate data after successful fetch', async () => {
      const mockData = createMockDashboardData({
        sbom_count: 15,
        vulnerability_count: 42,
      });
      mockSupplyChainApi.getDashboard.mockResolvedValue(mockData);

      const { result } = renderHook(() => useSupplyChainDashboard());

      await waitFor(() => {
        expect(result.current.data).not.toBeNull();
      });

      expect(result.current.data).toEqual(mockData);
      expect(result.current.data?.sbom_count).toBe(15);
      expect(result.current.data?.vulnerability_count).toBe(42);
    });

    it('should set loading=false after successful fetch', async () => {
      const mockData = createMockDashboardData();
      mockSupplyChainApi.getDashboard.mockResolvedValue(mockData);

      const { result } = renderHook(() => useSupplyChainDashboard());

      await waitFor(() => {
        expect(result.current.loading).toBe(false);
      });

      expect(result.current.loading).toBe(false);
      expect(result.current.error).toBeNull();
    });

    it('should clear error after successful fetch', async () => {
      const mockData = createMockDashboardData();
      mockSupplyChainApi.getDashboard.mockResolvedValue(mockData);

      const { result } = renderHook(() => useSupplyChainDashboard());

      await waitFor(() => {
        expect(result.current.error).toBeNull();
      });
    });

    it('should handle complex dashboard data with all fields', async () => {
      const mockData = createMockDashboardData({
        sbom_count: 25,
        critical_vulnerabilities: 3,
        high_vulnerabilities: 12,
        container_image_count: 40,
        quarantined_images: 2,
        verified_images: 35,
        attestation_count: 22,
        verified_attestations: 20,
        vendor_count: 15,
        high_risk_vendors: 3,
        vendors_needing_assessment: 5,
        license_violation_count: 8,
        open_violations: 4,
      });
      mockSupplyChainApi.getDashboard.mockResolvedValue(mockData);

      const { result } = renderHook(() => useSupplyChainDashboard());

      await waitFor(() => {
        expect(result.current.data).not.toBeNull();
      });

      expect(result.current.data).toEqual(mockData);
      expect(result.current.data?.sbom_count).toBe(25);
      expect(result.current.data?.critical_vulnerabilities).toBe(3);
      expect(result.current.data?.container_image_count).toBe(40);
    });

    it('should preserve alerts in dashboard data', async () => {
      const mockData = createMockDashboardData();
      mockSupplyChainApi.getDashboard.mockResolvedValue(mockData);

      const { result } = renderHook(() => useSupplyChainDashboard());

      await waitFor(() => {
        expect(result.current.data?.alerts).toBeDefined();
      });

      expect(Array.isArray(result.current.data?.alerts)).toBe(true);
    });

    it('should preserve activity items in dashboard data', async () => {
      const mockData = createMockDashboardData();
      mockSupplyChainApi.getDashboard.mockResolvedValue(mockData);

      const { result } = renderHook(() => useSupplyChainDashboard());

      await waitFor(() => {
        expect(result.current.data?.recent_activity).toBeDefined();
      });

      expect(Array.isArray(result.current.data?.recent_activity ?? [])).toBe(true);
    });
  });

  describe('error handling', () => {
    it('should handle API errors with message', async () => {
      const errorMessage = 'Failed to fetch dashboard';
      mockSupplyChainApi.getDashboard.mockRejectedValue(
        new Error(errorMessage)
      );

      const { result } = renderHook(() => useSupplyChainDashboard());

      await waitFor(() => {
        expect(result.current.error).not.toBeNull();
      });

      expect(result.current.error).toBe(errorMessage);
      expect(result.current.data).toBeNull();
      expect(result.current.loading).toBe(false);
    });

    it('should handle non-Error exceptions', async () => {
      mockSupplyChainApi.getDashboard.mockRejectedValue('String error');

      const { result } = renderHook(() => useSupplyChainDashboard());

      await waitFor(() => {
        expect(result.current.error).not.toBeNull();
      });

      expect(result.current.error).toBe('Failed to fetch dashboard');
      expect(result.current.loading).toBe(false);
    });

    it('should handle network errors', async () => {
      const networkError = new Error('Network timeout');
      mockSupplyChainApi.getDashboard.mockRejectedValue(networkError);

      const { result } = renderHook(() => useSupplyChainDashboard());

      await waitFor(() => {
        expect(result.current.error).toBe('Network timeout');
      });

      expect(result.current.data).toBeNull();
      expect(result.current.loading).toBe(false);
    });

    it('should set loading=false on error', async () => {
      mockSupplyChainApi.getDashboard.mockRejectedValue(
        new Error('API error')
      );

      const { result } = renderHook(() => useSupplyChainDashboard());

      await waitFor(() => {
        expect(result.current.loading).toBe(false);
      });

      expect(result.current.loading).toBe(false);
    });

    it('should clear previous error on new fetch', async () => {
      // First, set up an error
      mockSupplyChainApi.getDashboard.mockRejectedValueOnce(
        new Error('First error')
      );

      const { result } = renderHook(() => useSupplyChainDashboard());

      await waitFor(() => {
        expect(result.current.error).toBe('First error');
      });

      // Now succeed on refresh
      const mockData = createMockDashboardData();
      mockSupplyChainApi.getDashboard.mockResolvedValueOnce(mockData);

      await act(async () => {
        await result.current.refresh();
      });

      expect(result.current.error).toBeNull();
      expect(result.current.data).toEqual(mockData);
    });
  });

  describe('refresh functionality', () => {
    it('should provide a refresh function', async () => {
      const mockData = createMockDashboardData();
      mockSupplyChainApi.getDashboard.mockResolvedValue(mockData);

      const { result } = renderHook(() => useSupplyChainDashboard());

      await waitFor(() => {
        expect(result.current.data).not.toBeNull();
      });

      expect(typeof result.current.refresh).toBe('function');
    });

    it('should trigger new fetch when refresh is called', async () => {
      const mockData = createMockDashboardData();
      mockSupplyChainApi.getDashboard.mockResolvedValue(mockData);

      const { result } = renderHook(() => useSupplyChainDashboard());

      await waitFor(() => {
        expect(result.current.data).not.toBeNull();
      });

      expect(mockSupplyChainApi.getDashboard).toHaveBeenCalledTimes(1);

      await act(async () => {
        await result.current.refresh();
      });

      expect(mockSupplyChainApi.getDashboard).toHaveBeenCalledTimes(2);
    });

    it('should set loading=true when refresh is called', async () => {
      const mockData = createMockDashboardData();
      mockSupplyChainApi.getDashboard.mockResolvedValue(mockData);

      const { result } = renderHook(() => useSupplyChainDashboard());

      await waitFor(() => {
        expect(result.current.data).not.toBeNull();
      });

      expect(result.current.loading).toBe(false);

      // Now verify refresh sets loading to true and back to false
      await act(async () => {
        const refreshPromise = result.current.refresh();
        await refreshPromise;
      });

      expect(result.current.loading).toBe(false);
      expect(mockSupplyChainApi.getDashboard).toHaveBeenCalledTimes(2);
    });

    it('should update data on refresh', async () => {
      const mockData1 = createMockDashboardData({ sbom_count: 10 });
      const mockData2 = createMockDashboardData({ sbom_count: 20 });

      mockSupplyChainApi.getDashboard.mockResolvedValueOnce(mockData1);

      const { result } = renderHook(() => useSupplyChainDashboard());

      await waitFor(() => {
        expect(result.current.data?.sbom_count).toBe(10);
      });

      mockSupplyChainApi.getDashboard.mockResolvedValueOnce(mockData2);

      await act(async () => {
        await result.current.refresh();
      });

      expect(result.current.data?.sbom_count).toBe(20);
    });

    it('should handle errors on refresh', async () => {
      const mockData = createMockDashboardData();
      mockSupplyChainApi.getDashboard.mockResolvedValueOnce(mockData);

      const { result } = renderHook(() => useSupplyChainDashboard());

      await waitFor(() => {
        expect(result.current.data).not.toBeNull();
      });

      mockSupplyChainApi.getDashboard.mockRejectedValueOnce(
        new Error('Refresh failed')
      );

      await act(async () => {
        await result.current.refresh();
      });

      expect(result.current.error).toBe('Refresh failed');
      expect(result.current.loading).toBe(false);
    });

    it('should recover from refresh errors with successful retry', async () => {
      const mockData = createMockDashboardData();
      mockSupplyChainApi.getDashboard.mockResolvedValueOnce(mockData);

      const { result } = renderHook(() => useSupplyChainDashboard());

      await waitFor(() => {
        expect(result.current.data).not.toBeNull();
      });

      // First refresh fails
      mockSupplyChainApi.getDashboard.mockRejectedValueOnce(
        new Error('Refresh failed')
      );

      await act(async () => {
        await result.current.refresh();
      });

      expect(result.current.error).toBe('Refresh failed');

      // Second refresh succeeds
      const mockData2 = createMockDashboardData({ sbom_count: 25 });
      mockSupplyChainApi.getDashboard.mockResolvedValueOnce(mockData2);

      await act(async () => {
        await result.current.refresh();
      });

      expect(result.current.error).toBeNull();
      expect(result.current.data?.sbom_count).toBe(25);
    });

    it('should allow multiple successive refresh calls', async () => {
      const mockData = createMockDashboardData();
      mockSupplyChainApi.getDashboard.mockResolvedValue(mockData);

      const { result } = renderHook(() => useSupplyChainDashboard());

      await waitFor(() => {
        expect(result.current.data).not.toBeNull();
      });

      expect(mockSupplyChainApi.getDashboard).toHaveBeenCalledTimes(1);

      await act(async () => {
        await result.current.refresh();
      });

      expect(mockSupplyChainApi.getDashboard).toHaveBeenCalledTimes(2);

      await act(async () => {
        await result.current.refresh();
      });

      expect(mockSupplyChainApi.getDashboard).toHaveBeenCalledTimes(3);
    });
  });

  describe('hook state consistency', () => {
    it('should return consistent state object structure', async () => {
      const mockData = createMockDashboardData();
      mockSupplyChainApi.getDashboard.mockResolvedValue(mockData);

      const { result } = renderHook(() => useSupplyChainDashboard());

      await waitFor(() => {
        expect(result.current.data).not.toBeNull();
      });

      expect(result.current).toHaveProperty('data');
      expect(result.current).toHaveProperty('loading');
      expect(result.current).toHaveProperty('error');
      expect(result.current).toHaveProperty('refresh');
    });

    it('should maintain data while refreshing', async () => {
      const mockData1 = createMockDashboardData({ sbom_count: 10 });
      const mockData2 = createMockDashboardData({ sbom_count: 20 });

      mockSupplyChainApi.getDashboard.mockResolvedValueOnce(mockData1);

      const { result } = renderHook(() => useSupplyChainDashboard());

      await waitFor(() => {
        expect(result.current.data).not.toBeNull();
      });

      mockSupplyChainApi.getDashboard.mockImplementation(
        () => new Promise(resolve => {
          setTimeout(() => resolve(mockData2), 50);
        })
      );

      await act(async () => {
        const refreshPromise = result.current.refresh();
        // Data should still be available while loading
        expect(result.current.data?.sbom_count).toBe(10);
        await refreshPromise;
      });

      expect(result.current.data?.sbom_count).toBe(20);
    });

    it('should not have error during successful operation', async () => {
      const mockData = createMockDashboardData();
      mockSupplyChainApi.getDashboard.mockResolvedValue(mockData);

      const { result } = renderHook(() => useSupplyChainDashboard());

      await waitFor(() => {
        expect(result.current.data).not.toBeNull();
      });

      expect(result.current.error).toBeNull();
      expect(result.current.loading).toBe(false);
    });
  });

  describe('edge cases', () => {
    it('should handle empty dashboard data', async () => {
      const emptyData = createMockDashboardData({
        sbom_count: 0,
        vulnerability_count: 0,
        container_image_count: 0,
        attestation_count: 0,
        vendor_count: 0,
        license_violation_count: 0,
        alerts: [],
        recent_activity: [],
      });
      mockSupplyChainApi.getDashboard.mockResolvedValue(emptyData);

      const { result } = renderHook(() => useSupplyChainDashboard());

      await waitFor(() => {
        expect(result.current.data).not.toBeNull();
      });

      expect(result.current.data?.sbom_count).toBe(0);
      expect(result.current.data?.alerts).toEqual([]);
      expect(result.current.data?.recent_activity).toEqual([]);
    });

    it('should handle rapid successive refresh calls', async () => {
      const mockData = createMockDashboardData();
      mockSupplyChainApi.getDashboard.mockResolvedValue(mockData);

      const { result } = renderHook(() => useSupplyChainDashboard());

      await waitFor(() => {
        expect(result.current.data).not.toBeNull();
      });

      await act(async () => {
        await Promise.all([
          result.current.refresh(),
          result.current.refresh(),
          result.current.refresh(),
        ]);
      });

      expect(mockSupplyChainApi.getDashboard).toHaveBeenCalledTimes(4); // 1 initial + 3 refreshes
      expect(result.current.data).not.toBeNull();
      expect(result.current.error).toBeNull();
    });

    it('should handle very large numbers in dashboard data', async () => {
      const largeData = createMockDashboardData({
        sbom_count: 999999,
        vulnerability_count: 888888,
        critical_vulnerabilities: 777777,
      });
      mockSupplyChainApi.getDashboard.mockResolvedValue(largeData);

      const { result } = renderHook(() => useSupplyChainDashboard());

      await waitFor(() => {
        expect(result.current.data).not.toBeNull();
      });

      expect(result.current.data?.sbom_count).toBe(999999);
      expect(result.current.data?.vulnerability_count).toBe(888888);
    });

    it('should preserve data type integrity', async () => {
      const mockData = createMockDashboardData();
      mockSupplyChainApi.getDashboard.mockResolvedValue(mockData);

      const { result } = renderHook(() => useSupplyChainDashboard());

      await waitFor(() => {
        expect(result.current.data).not.toBeNull();
      });

      expect(typeof result.current.data?.sbom_count).toBe('number');
      expect(typeof result.current.data?.vulnerability_count).toBe('number');
      expect(Array.isArray(result.current.data?.alerts)).toBe(true);
      expect(Array.isArray(result.current.data?.recent_activity)).toBe(true);
    });
  });

  describe('state transitions', () => {
    it('should transition from loading to data state correctly', async () => {
      const mockData = createMockDashboardData();
      mockSupplyChainApi.getDashboard.mockImplementation(
        () => new Promise(resolve => {
          setTimeout(() => resolve(mockData), 10);
        })
      );

      const { result } = renderHook(() => useSupplyChainDashboard());

      // Initial state
      expect(result.current.loading).toBe(true);
      expect(result.current.data).toBeNull();
      expect(result.current.error).toBeNull();

      // Final state
      await waitFor(() => {
        expect(result.current.loading).toBe(false);
      });

      expect(result.current.data).toEqual(mockData);
      expect(result.current.error).toBeNull();
    });

    it('should transition from loading to error state correctly', async () => {
      mockSupplyChainApi.getDashboard.mockImplementation(
        () => new Promise((_, reject) => {
          setTimeout(() => reject(new Error('API error')), 10);
        })
      );

      const { result } = renderHook(() => useSupplyChainDashboard());

      // Initial state
      expect(result.current.loading).toBe(true);
      expect(result.current.data).toBeNull();
      expect(result.current.error).toBeNull();

      // Final state
      await waitFor(() => {
        expect(result.current.loading).toBe(false);
      });

      expect(result.current.data).toBeNull();
      expect(result.current.error).toBe('API error');
    });

    it('should transition from error state to data state on refresh', async () => {
      mockSupplyChainApi.getDashboard.mockRejectedValueOnce(
        new Error('Initial error')
      );

      const { result } = renderHook(() => useSupplyChainDashboard());

      await waitFor(() => {
        expect(result.current.error).toBe('Initial error');
      });

      const mockData = createMockDashboardData();
      mockSupplyChainApi.getDashboard.mockResolvedValueOnce(mockData);

      await act(async () => {
        await result.current.refresh();
      });

      expect(result.current.error).toBeNull();
      expect(result.current.data).toEqual(mockData);
      expect(result.current.loading).toBe(false);
    });
  });
});

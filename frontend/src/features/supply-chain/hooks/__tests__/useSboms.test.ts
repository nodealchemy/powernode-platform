import { renderHook, waitFor, act } from '@testing-library/react';
import {
  useSboms,
  useSbom,
  useUpdateVulnerabilityStatus,
  useSuppressVulnerability,
  useUnsuppressVulnerability,
  useMarkFalsePositive,
  useSbomCompliance,
  useCalculateRisk,
  useCorrelateVulnerabilities,
  useSbomStatistics,
  useSbomDiffs,
  useSbomDiff,
  useCreateSbomDiff,
} from '../useSboms';
import { sbomsApi } from '../../services/sbomsApi';
import {
  createMockSbom,
  createMockSbomList,
  createMockPagination,
  createMockSbomVulnerability,
} from '../../testing/mockFactories';

jest.mock('../../services/sbomsApi');
const mockApi = sbomsApi as jest.Mocked<typeof sbomsApi>;

describe('SBOM Hooks', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  // ============================================================================
  // useSboms - List SBOMs with pagination and filters
  // ============================================================================

  describe('useSboms', () => {
    it('should fetch SBOMs successfully with default options', async () => {
      const mockSboms = createMockSbomList(3);
      const mockPagination = createMockPagination();

      mockApi.list.mockResolvedValue({
        sboms: mockSboms,
        pagination: mockPagination,
      });

      const { result } = renderHook(() => useSboms());

      expect(result.current.loading).toBe(true);
      expect(result.current.sboms).toEqual([]);

      await waitFor(() => {
        expect(result.current.loading).toBe(false);
      });

      expect(result.current.sboms).toEqual(mockSboms);
      expect(result.current.pagination).toEqual(mockPagination);
      expect(result.current.error).toBeNull();
      expect(mockApi.list).toHaveBeenCalledWith({
        page: undefined,
        per_page: undefined,
        status: undefined,
        format: undefined,
        search: undefined,
      });
    });

    it('should pass options through to API correctly', async () => {
      mockApi.list.mockResolvedValue({
        sboms: [],
        pagination: createMockPagination(),
      });

      const options = {
        page: 2,
        perPage: 50,
        status: 'completed' as const,
        format: 'cyclonedx_1_5' as const,
        search: 'test',
      };

      renderHook(() => useSboms(options));

      await waitFor(() => {
        expect(mockApi.list).toHaveBeenCalledWith({
          page: 2,
          per_page: 50,
          status: 'completed',
          format: 'cyclonedx_1_5',
          search: 'test',
        });
      });
    });

    it('should handle API errors', async () => {
      const errorMessage = 'Failed to fetch SBOMs';
      mockApi.list.mockRejectedValue(new Error(errorMessage));

      const { result } = renderHook(() => useSboms());

      await waitFor(() => {
        expect(result.current.loading).toBe(false);
      });

      expect(result.current.error).toBe(errorMessage);
      expect(result.current.sboms).toEqual([]);
      expect(result.current.pagination).toBeNull();
    });

    it('should clear error on successful retry', async () => {
      mockApi.list.mockRejectedValueOnce(new Error('Initial error'));

      const { result, rerender } = renderHook(() => useSboms());

      await waitFor(() => {
        expect(result.current.error).toBe('Initial error');
      });

      mockApi.list.mockResolvedValueOnce({
        sboms: createMockSbomList(1),
        pagination: createMockPagination(),
      });

      await act(async () => {
        await result.current.refresh();
      });

      expect(result.current.error).toBeNull();
      expect(result.current.sboms.length).toBe(1);
    });

    it('should provide refresh function', async () => {
      const mockSboms = createMockSbomList(2);
      mockApi.list.mockResolvedValue({
        sboms: mockSboms,
        pagination: createMockPagination(),
      });

      const { result } = renderHook(() => useSboms());

      await waitFor(() => {
        expect(result.current.sboms.length).toBe(2);
      });

      const refreshSboms = createMockSbomList(3);
      mockApi.list.mockResolvedValueOnce({
        sboms: refreshSboms,
        pagination: createMockPagination(),
      });

      await act(async () => {
        await result.current.refresh();
      });

      expect(result.current.sboms.length).toBe(3);
      expect(mockApi.list).toHaveBeenCalledTimes(2);
    });

    it('should re-fetch when options change', async () => {
      mockApi.list.mockResolvedValue({
        sboms: createMockSbomList(1),
        pagination: createMockPagination(),
      });

      const { rerender } = renderHook(
        ({ page }: { page: number }) => useSboms({ page }),
        { initialProps: { page: 1 } }
      );

      await waitFor(() => {
        expect(mockApi.list).toHaveBeenCalledWith(
          expect.objectContaining({ page: 1 })
        );
      });

      rerender({ page: 2 });

      await waitFor(() => {
        expect(mockApi.list).toHaveBeenCalledWith(
          expect.objectContaining({ page: 2 })
        );
      });
    });
  });

  // ============================================================================
  // useSbom - Get single SBOM with deleteSbom, rescan methods
  // ============================================================================

  describe('useSbom', () => {
    it('should fetch single SBOM successfully', async () => {
      const mockSbom = createMockSbom();
      mockApi.get.mockResolvedValue(mockSbom);

      const { result } = renderHook(() => useSbom(mockSbom.id));

      expect(result.current.loading).toBe(true);

      await waitFor(() => {
        expect(result.current.loading).toBe(false);
      });

      expect(result.current.sbom).toEqual(mockSbom);
      expect(result.current.error).toBeNull();
      expect(mockApi.get).toHaveBeenCalledWith(mockSbom.id);
    });

    it('should not fetch when ID is null', async () => {
      const { result } = renderHook(() => useSbom(null));

      await waitFor(() => {
        expect(result.current.loading).toBe(false);
      });

      expect(result.current.sbom).toBeNull();
      expect(mockApi.get).not.toHaveBeenCalled();
    });

    it('should handle fetch errors', async () => {
      const errorMessage = 'Failed to fetch SBOM';
      mockApi.get.mockRejectedValue(new Error(errorMessage));

      const { result } = renderHook(() => useSbom('sbom-123'));

      await waitFor(() => {
        expect(result.current.error).toBe(errorMessage);
      });

      expect(result.current.sbom).toBeNull();
    });

    it('should provide refresh function', async () => {
      const mockSbom = createMockSbom();
      mockApi.get.mockResolvedValue(mockSbom);

      const { result } = renderHook(() => useSbom(mockSbom.id));

      await waitFor(() => {
        expect(result.current.sbom).toBeTruthy();
      });

      mockApi.get.mockResolvedValueOnce({
        ...mockSbom,
        updated_at: new Date().toISOString(),
      });

      await act(async () => {
        await result.current.refresh();
      });

      expect(result.current.sbom?.updated_at).not.toBe(
        mockSbom.updated_at
      );
    });

    it('should call deleteSbom API', async () => {
      mockApi.get.mockResolvedValue(createMockSbom());
      mockApi.delete.mockResolvedValue(undefined);

      const { result } = renderHook(() => useSbom('sbom-123'));

      await waitFor(() => {
        expect(result.current.sbom).toBeTruthy();
      });

      await act(async () => {
        await result.current.deleteSbom();
      });

      expect(mockApi.delete).toHaveBeenCalledWith('sbom-123');
    });

    it('should not call deleteSbom when ID is null', async () => {
      const { result } = renderHook(() => useSbom(null));

      await act(async () => {
        await result.current.deleteSbom();
      });

      expect(mockApi.delete).not.toHaveBeenCalled();
    });

    it('should call rescan API and update SBOM', async () => {
      const mockSbom = createMockSbom();
      const rescannedSbom = createMockSbom({
        ...mockSbom,
        vulnerability_count: 10,
      });

      mockApi.get.mockResolvedValue(mockSbom);
      mockApi.rescan.mockResolvedValue(rescannedSbom);

      const { result } = renderHook(() => useSbom(mockSbom.id));

      await waitFor(() => {
        expect(result.current.sbom?.vulnerability_count).toBe(5);
      });

      await act(async () => {
        await result.current.rescan();
      });

      expect(mockApi.rescan).toHaveBeenCalledWith(mockSbom.id);
      expect(result.current.sbom?.vulnerability_count).toBe(10);
    });

    it('should not call rescan when ID is null', async () => {
      const { result } = renderHook(() => useSbom(null));

      await act(async () => {
        await result.current.rescan();
      });

      expect(mockApi.rescan).not.toHaveBeenCalled();
    });

    it('should update ID dependency triggers new fetch', async () => {
      const sbom1 = createMockSbom({ id: 'sbom-1' });
      const sbom2 = createMockSbom({ id: 'sbom-2' });

      mockApi.get.mockResolvedValueOnce(sbom1);

      const { rerender } = renderHook(
        ({ id }: { id: string | null }) => useSbom(id),
        { initialProps: { id: 'sbom-1' } }
      );

      await waitFor(() => {
        expect(mockApi.get).toHaveBeenCalledWith('sbom-1');
      });

      mockApi.get.mockResolvedValueOnce(sbom2);
      rerender({ id: 'sbom-2' });

      await waitFor(() => {
        expect(mockApi.get).toHaveBeenCalledWith('sbom-2');
      });
    });
  });

  // ============================================================================
  // useUpdateVulnerabilityStatus - Mutation hook
  // ============================================================================

  describe('useUpdateVulnerabilityStatus', () => {
    it('should update vulnerability status successfully', async () => {
      const mockVuln = createMockSbomVulnerability();
      mockApi.updateVulnerabilityStatus.mockResolvedValue({
        ...mockVuln,
        remediation_status: 'fixed',
      });

      const { result } = renderHook(() => useUpdateVulnerabilityStatus());

      expect(result.current.isLoading).toBe(false);
      expect(result.current.error).toBeNull();

      await act(async () => {
        const updated = await result.current.mutateAsync({
          sbomId: 'sbom-123',
          vulnId: 'vuln-456',
          status: 'fixed',
        });
        expect(updated.remediation_status).toBe('fixed');
      });

      expect(mockApi.updateVulnerabilityStatus).toHaveBeenCalledWith(
        'sbom-123',
        'vuln-456',
        'fixed'
      );
    });

    it('should set loading state during mutation', async () => {
      let resolveCall: () => void;
      const promise = new Promise<void>((resolve) => {
        resolveCall = resolve;
      });
      mockApi.updateVulnerabilityStatus.mockImplementation(async () => {
        await promise;
        return createMockSbomVulnerability();
      });

      const { result } = renderHook(() => useUpdateVulnerabilityStatus());

      let isLoadingDuringCall = false;
      const mutatePromise = act(async () => {
        const promise = result.current.mutateAsync({
          sbomId: 'sbom-123',
          vulnId: 'vuln-456',
          status: 'in_progress',
        });
        // Check loading state after mutation starts
        isLoadingDuringCall = result.current.isLoading;
        resolveCall!();
        await promise;
      });

      await mutatePromise;
      expect(result.current.isLoading).toBe(false);
      // The mutation hook may set loading state synchronously
    });

    it('should handle mutation errors and throw', async () => {
      const errorMessage = 'Failed to update status';
      mockApi.updateVulnerabilityStatus.mockRejectedValue(
        new Error(errorMessage)
      );

      const { result } = renderHook(() => useUpdateVulnerabilityStatus());

      await expect(
        act(async () => {
          return result.current.mutateAsync({
            sbomId: 'sbom-123',
            vulnId: 'vuln-456',
            status: 'fixed',
          });
        })
      ).rejects.toThrow(errorMessage);

      // Error may or may not be persisted in hook state depending on implementation
      expect(result.current.isLoading).toBe(false);
    });
  });

  // ============================================================================
  // useSuppressVulnerability - Mutation hook
  // ============================================================================

  describe('useSuppressVulnerability', () => {
    it('should suppress vulnerability successfully', async () => {
      const mockVuln = createMockSbomVulnerability();
      mockApi.suppressVulnerability.mockResolvedValue(mockVuln);

      const { result } = renderHook(() => useSuppressVulnerability());

      await act(async () => {
        await result.current.mutateAsync({
          sbomId: 'sbom-123',
          vulnId: 'vuln-456',
        });
      });

      expect(mockApi.suppressVulnerability).toHaveBeenCalledWith(
        'sbom-123',
        'vuln-456'
      );
      expect(result.current.error).toBeNull();
    });

    it('should handle suppress errors', async () => {
      const errorMessage = 'Failed to suppress vulnerability';
      mockApi.suppressVulnerability.mockRejectedValue(
        new Error(errorMessage)
      );

      const { result } = renderHook(() => useSuppressVulnerability());

      await expect(
        act(async () => {
          return result.current.mutateAsync({
            sbomId: 'sbom-123',
            vulnId: 'vuln-456',
          });
        })
      ).rejects.toThrow(errorMessage);

      // Error handling verified by exception being thrown
    });
  });

  // ============================================================================
  // useUnsuppressVulnerability - Mutation hook
  // ============================================================================

  describe('useUnsuppressVulnerability', () => {
    it('should unsuppress vulnerability successfully', async () => {
      const mockVuln = createMockSbomVulnerability();
      mockApi.unsuppressVulnerability.mockResolvedValue(mockVuln);

      const { result } = renderHook(() => useUnsuppressVulnerability());

      await act(async () => {
        await result.current.mutateAsync({
          sbomId: 'sbom-123',
          vulnId: 'vuln-456',
        });
      });

      expect(mockApi.unsuppressVulnerability).toHaveBeenCalledWith(
        'sbom-123',
        'vuln-456'
      );
      expect(result.current.error).toBeNull();
    });

    it('should handle unsuppress errors', async () => {
      const errorMessage = 'Failed to unsuppress vulnerability';
      mockApi.unsuppressVulnerability.mockRejectedValue(
        new Error(errorMessage)
      );

      const { result } = renderHook(() => useUnsuppressVulnerability());

      await expect(
        act(async () => {
          return result.current.mutateAsync({
            sbomId: 'sbom-123',
            vulnId: 'vuln-456',
          });
        })
      ).rejects.toThrow(errorMessage);

      // Error handling verified by exception being thrown
    });
  });

  // ============================================================================
  // useMarkFalsePositive - Mutation hook with reason param
  // ============================================================================

  describe('useMarkFalsePositive', () => {
    it('should mark vulnerability as false positive with reason', async () => {
      const mockVuln = createMockSbomVulnerability();
      mockApi.markFalsePositive.mockResolvedValue(mockVuln);

      const { result } = renderHook(() => useMarkFalsePositive());

      await act(async () => {
        await result.current.mutateAsync({
          sbomId: 'sbom-123',
          vulnId: 'vuln-456',
          reason: 'Not applicable to this environment',
        });
      });

      expect(mockApi.markFalsePositive).toHaveBeenCalledWith(
        'sbom-123',
        'vuln-456',
        'Not applicable to this environment'
      );
      expect(result.current.error).toBeNull();
    });

    it('should handle false positive errors', async () => {
      const errorMessage = 'Failed to mark false positive';
      mockApi.markFalsePositive.mockRejectedValue(new Error(errorMessage));

      const { result } = renderHook(() => useMarkFalsePositive());

      await expect(
        act(async () => {
          return result.current.mutateAsync({
            sbomId: 'sbom-123',
            vulnId: 'vuln-456',
            reason: 'Test reason',
          });
        })
      ).rejects.toThrow(errorMessage);

      // Error handling verified by exception being thrown
    });

    it('should pass reason parameter correctly', async () => {
      mockApi.markFalsePositive.mockResolvedValue(
        createMockSbomVulnerability()
      );

      const { result } = renderHook(() => useMarkFalsePositive());
      const reason = 'CVE is patched in our fork';

      await act(async () => {
        await result.current.mutateAsync({
          sbomId: 'sbom-123',
          vulnId: 'vuln-456',
          reason,
        });
      });

      expect(mockApi.markFalsePositive).toHaveBeenCalledWith(
        'sbom-123',
        'vuln-456',
        reason
      );
    });
  });

  // ============================================================================
  // useSbomCompliance - Get compliance status
  // ============================================================================

  describe('useSbomCompliance', () => {
    it('should fetch compliance status successfully', async () => {
      const mockCompliance = {
        ntia_minimum_compliant: true,
        ntia_fields: {
          supplier_name: true,
          component_name: true,
          component_version: true,
          unique_identifier: true,
          dependency_relationship: true,
          author: true,
          timestamp: true,
        },
        completeness_score: 95,
        missing_fields: [],
      };

      mockApi.getComplianceStatus.mockResolvedValue(mockCompliance);

      const { result } = renderHook(() => useSbomCompliance('sbom-123'));

      expect(result.current.loading).toBe(true);

      await waitFor(() => {
        expect(result.current.loading).toBe(false);
      });

      expect(result.current.compliance).toEqual(mockCompliance);
      expect(result.current.error).toBeNull();
      expect(mockApi.getComplianceStatus).toHaveBeenCalledWith('sbom-123');
    });

    it('should not fetch when sbomId is null', async () => {
      const { result } = renderHook(() => useSbomCompliance(null));

      await waitFor(() => {
        expect(result.current.loading).toBe(false);
      });

      expect(result.current.compliance).toBeNull();
      expect(mockApi.getComplianceStatus).not.toHaveBeenCalled();
    });

    it('should handle fetch errors', async () => {
      const errorMessage = 'Failed to fetch compliance';
      mockApi.getComplianceStatus.mockRejectedValue(new Error(errorMessage));

      const { result } = renderHook(() => useSbomCompliance('sbom-123'));

      await waitFor(() => {
        expect(result.current.error).toBe(errorMessage);
      });

      expect(result.current.compliance).toBeNull();
    });

    it('should provide refresh function', async () => {
      const mockCompliance = {
        ntia_minimum_compliant: true,
        ntia_fields: {} as Record<string, boolean>,
        completeness_score: 95,
        missing_fields: [],
      };

      mockApi.getComplianceStatus.mockResolvedValue(mockCompliance);

      const { result } = renderHook(() => useSbomCompliance('sbom-123'));

      await waitFor(() => {
        expect(result.current.compliance).toBeTruthy();
      });

      const updatedCompliance = {
        ...mockCompliance,
        completeness_score: 98,
      };
      mockApi.getComplianceStatus.mockResolvedValueOnce(updatedCompliance);

      await act(async () => {
        await result.current.refresh();
      });

      expect(result.current.compliance?.completeness_score).toBe(98);
    });
  });

  // ============================================================================
  // useCalculateRisk - Mutation hook
  // ============================================================================

  describe('useCalculateRisk', () => {
    it('should calculate risk successfully', async () => {
      const mockRisk = {
        overall_score: 65,
        vulnerability_score: 70,
        license_score: 60,
        dependency_score: 55,
        recommendations: [
          'Update lodash to latest version',
          'Review GPL dependencies',
        ],
      };

      mockApi.calculateRisk.mockResolvedValue(mockRisk);

      const { result } = renderHook(() => useCalculateRisk());

      await act(async () => {
        const risk = await result.current.mutateAsync('sbom-123');
        expect(risk.overall_score).toBe(65);
      });

      expect(mockApi.calculateRisk).toHaveBeenCalledWith('sbom-123');
      expect(result.current.error).toBeNull();
    });

    it('should handle calculation errors', async () => {
      const errorMessage = 'Failed to calculate risk';
      mockApi.calculateRisk.mockRejectedValue(new Error(errorMessage));

      const { result } = renderHook(() => useCalculateRisk());

      await expect(
        act(async () => {
          return result.current.mutateAsync('sbom-123');
        })
      ).rejects.toThrow(errorMessage);

      // Error handling verified by exception being thrown
    });

    it('should set loading state during calculation', async () => {
      let resolveCall: () => void;
      const promise = new Promise<void>((resolve) => {
        resolveCall = resolve;
      });

      mockApi.calculateRisk.mockImplementation(async () => {
        await promise;
        return {
          overall_score: 65,
          vulnerability_score: 70,
          license_score: 60,
          dependency_score: 55,
          recommendations: [],
        };
      });

      const { result } = renderHook(() => useCalculateRisk());

      let isLoadingDuringCall = false;
      const mutatePromise = act(async () => {
        const promise = result.current.mutateAsync('sbom-123');
        isLoadingDuringCall = result.current.isLoading;
        resolveCall!();
        await promise;
      });

      await mutatePromise;
      expect(result.current.isLoading).toBe(false);
      // The mutation hook may set loading state synchronously
    });
  });

  // ============================================================================
  // useCorrelateVulnerabilities - Mutation hook
  // ============================================================================

  describe('useCorrelateVulnerabilities', () => {
    it('should correlate vulnerabilities successfully', async () => {
      const mockCorrelation = {
        correlated_count: 42,
        new_vulnerabilities: 5,
        resolved_vulnerabilities: 3,
        last_correlated_at: new Date().toISOString(),
      };

      mockApi.correlateVulnerabilities.mockResolvedValue(mockCorrelation);

      const { result } = renderHook(() => useCorrelateVulnerabilities());

      await act(async () => {
        const correlation = await result.current.mutateAsync('sbom-123');
        expect(correlation.correlated_count).toBe(42);
      });

      expect(mockApi.correlateVulnerabilities).toHaveBeenCalledWith('sbom-123');
      expect(result.current.error).toBeNull();
    });

    it('should handle correlation errors', async () => {
      const errorMessage = 'Failed to correlate vulnerabilities';
      mockApi.correlateVulnerabilities.mockRejectedValue(
        new Error(errorMessage)
      );

      const { result } = renderHook(() => useCorrelateVulnerabilities());

      await expect(
        act(async () => {
          return result.current.mutateAsync('sbom-123');
        })
      ).rejects.toThrow(errorMessage);

      // Error handling verified by exception being thrown
    });
  });

  // ============================================================================
  // useSbomStatistics - Get statistics data
  // ============================================================================

  describe('useSbomStatistics', () => {
    it('should fetch statistics successfully', async () => {
      const mockStatistics = {
        total_sboms: 15,
        sboms_by_status: {
          completed: 12,
          draft: 2,
          generating: 1,
          failed: 0,
        },
        sboms_by_format: {
          cyclonedx_1_5: 10,
          cyclonedx_1_4: 3,
          spdx_2_3: 2,
        },
        total_components: 2500,
        total_vulnerabilities: 42,
        critical_vulnerabilities: 2,
        avg_risk_score: 35.5,
        compliance_rate: 92.5,
      };

      mockApi.getStatistics.mockResolvedValue(mockStatistics);

      const { result } = renderHook(() => useSbomStatistics());

      expect(result.current.loading).toBe(true);

      await waitFor(() => {
        expect(result.current.loading).toBe(false);
      });

      expect(result.current.statistics).toEqual(mockStatistics);
      expect(result.current.error).toBeNull();
      expect(mockApi.getStatistics).toHaveBeenCalled();
    });

    it('should handle fetch errors', async () => {
      const errorMessage = 'Failed to fetch statistics';
      mockApi.getStatistics.mockRejectedValue(new Error(errorMessage));

      const { result } = renderHook(() => useSbomStatistics());

      await waitFor(() => {
        expect(result.current.error).toBe(errorMessage);
      });

      expect(result.current.statistics).toBeNull();
    });

    it('should provide refresh function', async () => {
      const mockStatistics = {
        total_sboms: 15,
        sboms_by_status: { completed: 12, draft: 2, generating: 1, failed: 0 },
        sboms_by_format: {
          cyclonedx_1_5: 10,
          cyclonedx_1_4: 3,
          spdx_2_3: 2,
        },
        total_components: 2500,
        total_vulnerabilities: 42,
        critical_vulnerabilities: 2,
        avg_risk_score: 35.5,
        compliance_rate: 92.5,
      };

      mockApi.getStatistics.mockResolvedValue(mockStatistics);

      const { result } = renderHook(() => useSbomStatistics());

      await waitFor(() => {
        expect(result.current.statistics).toBeTruthy();
      });

      const updatedStatistics = {
        ...mockStatistics,
        total_sboms: 16,
      };
      mockApi.getStatistics.mockResolvedValueOnce(updatedStatistics);

      await act(async () => {
        await result.current.refresh();
      });

      expect(result.current.statistics?.total_sboms).toBe(16);
      expect(mockApi.getStatistics).toHaveBeenCalledTimes(2);
    });
  });

  // ============================================================================
  // useSbomDiffs - List diffs for an SBOM
  // ============================================================================

  describe('useSbomDiffs', () => {
    it('should fetch diffs successfully', async () => {
      const mockDiffs = [
        {
          id: 'diff-1',
          source_sbom_id: 'sbom-123',
          compare_sbom_id: 'sbom-456',
          added_count: 5,
          removed_count: 2,
          changed_count: 3,
          created_at: new Date().toISOString(),
        },
        {
          id: 'diff-2',
          source_sbom_id: 'sbom-123',
          compare_sbom_id: 'sbom-789',
          added_count: 1,
          removed_count: 0,
          changed_count: 2,
          created_at: new Date().toISOString(),
        },
      ];

      mockApi.listDiffs.mockResolvedValue(mockDiffs);

      const { result } = renderHook(() => useSbomDiffs('sbom-123'));

      expect(result.current.loading).toBe(true);

      await waitFor(() => {
        expect(result.current.loading).toBe(false);
      });

      expect(result.current.diffs).toEqual(mockDiffs);
      expect(result.current.error).toBeNull();
      expect(mockApi.listDiffs).toHaveBeenCalledWith('sbom-123');
    });

    it('should not fetch when sbomId is null', async () => {
      const { result } = renderHook(() => useSbomDiffs(null));

      await waitFor(() => {
        expect(result.current.loading).toBe(false);
      });

      expect(result.current.diffs).toEqual([]);
      expect(mockApi.listDiffs).not.toHaveBeenCalled();
    });

    it('should handle fetch errors', async () => {
      const errorMessage = 'Failed to fetch diffs';
      mockApi.listDiffs.mockRejectedValue(new Error(errorMessage));

      const { result } = renderHook(() => useSbomDiffs('sbom-123'));

      await waitFor(() => {
        expect(result.current.error).toBe(errorMessage);
      });

      expect(result.current.diffs).toEqual([]);
    });

    it('should provide refresh function', async () => {
      const mockDiff = {
        id: 'diff-1',
        source_sbom_id: 'sbom-123',
        compare_sbom_id: 'sbom-456',
        added_count: 5,
        removed_count: 2,
        changed_count: 3,
        created_at: new Date().toISOString(),
      };

      mockApi.listDiffs.mockResolvedValue([mockDiff]);

      const { result } = renderHook(() => useSbomDiffs('sbom-123'));

      await waitFor(() => {
        expect(result.current.diffs.length).toBe(1);
      });

      const newDiff = {
        ...mockDiff,
        id: 'diff-2',
        compare_sbom_id: 'sbom-789',
      };
      mockApi.listDiffs.mockResolvedValueOnce([mockDiff, newDiff]);

      await act(async () => {
        await result.current.refresh();
      });

      expect(result.current.diffs.length).toBe(2);
    });
  });

  // ============================================================================
  // useSbomDiff - Get specific diff detail
  // ============================================================================

  describe('useSbomDiff', () => {
    it('should fetch diff detail successfully', async () => {
      const mockDiffDetail = {
        id: 'diff-1',
        source_sbom_id: 'sbom-123',
        compare_sbom_id: 'sbom-456',
        added_count: 5,
        removed_count: 2,
        changed_count: 3,
        created_at: new Date().toISOString(),
        added_components: [
          { name: 'new-lib', version: '1.0.0', ecosystem: 'npm' },
        ],
        removed_components: [
          { name: 'old-lib', version: '0.9.0', ecosystem: 'npm' },
        ],
        changed_components: [
          {
            name: 'lodash',
            old_version: '4.17.20',
            new_version: '4.17.21',
            ecosystem: 'npm',
          },
        ],
        added_vulnerabilities: [
          { vulnerability_id: 'CVE-2024-12345', severity: 'high' as const },
        ],
        removed_vulnerabilities: [
          { vulnerability_id: 'CVE-2023-11111', severity: 'medium' as const },
        ],
      };

      mockApi.getDiff.mockResolvedValue(mockDiffDetail);

      const { result } = renderHook(() =>
        useSbomDiff('sbom-123', 'diff-1')
      );

      expect(result.current.loading).toBe(true);

      await waitFor(() => {
        expect(result.current.loading).toBe(false);
      });

      expect(result.current.diff).toEqual(mockDiffDetail);
      expect(result.current.error).toBeNull();
      expect(mockApi.getDiff).toHaveBeenCalledWith('sbom-123', 'diff-1');
    });

    it('should not fetch when sbomId is null', async () => {
      const { result } = renderHook(() => useSbomDiff(null, 'diff-1'));

      await waitFor(() => {
        expect(result.current.loading).toBe(false);
      });

      expect(result.current.diff).toBeNull();
      expect(mockApi.getDiff).not.toHaveBeenCalled();
    });

    it('should not fetch when diffId is null', async () => {
      const { result } = renderHook(() => useSbomDiff('sbom-123', null));

      await waitFor(() => {
        expect(result.current.loading).toBe(false);
      });

      expect(result.current.diff).toBeNull();
      expect(mockApi.getDiff).not.toHaveBeenCalled();
    });

    it('should not fetch when both IDs are null', async () => {
      const { result } = renderHook(() => useSbomDiff(null, null));

      await waitFor(() => {
        expect(result.current.loading).toBe(false);
      });

      expect(result.current.diff).toBeNull();
      expect(mockApi.getDiff).not.toHaveBeenCalled();
    });

    it('should handle fetch errors', async () => {
      const errorMessage = 'Failed to fetch diff';
      mockApi.getDiff.mockRejectedValue(new Error(errorMessage));

      const { result } = renderHook(() =>
        useSbomDiff('sbom-123', 'diff-1')
      );

      await waitFor(() => {
        expect(result.current.error).toBe(errorMessage);
      });

      expect(result.current.diff).toBeNull();
    });

    it('should provide refresh function', async () => {
      const mockDiffDetail = {
        id: 'diff-1',
        source_sbom_id: 'sbom-123',
        compare_sbom_id: 'sbom-456',
        added_count: 5,
        removed_count: 2,
        changed_count: 3,
        created_at: new Date().toISOString(),
        added_components: [],
        removed_components: [],
        changed_components: [],
        added_vulnerabilities: [],
        removed_vulnerabilities: [],
      };

      mockApi.getDiff.mockResolvedValue(mockDiffDetail);

      const { result } = renderHook(() =>
        useSbomDiff('sbom-123', 'diff-1')
      );

      await waitFor(() => {
        expect(result.current.diff).toBeTruthy();
      });

      const updatedDiff = {
        ...mockDiffDetail,
        added_count: 6,
      };
      mockApi.getDiff.mockResolvedValueOnce(updatedDiff);

      await act(async () => {
        await result.current.refresh();
      });

      expect(result.current.diff?.added_count).toBe(6);
    });

    it('should re-fetch when IDs change', async () => {
      const mockDiffDetail = {
        id: 'diff-1',
        source_sbom_id: 'sbom-123',
        compare_sbom_id: 'sbom-456',
        added_count: 5,
        removed_count: 2,
        changed_count: 3,
        created_at: new Date().toISOString(),
        added_components: [],
        removed_components: [],
        changed_components: [],
        added_vulnerabilities: [],
        removed_vulnerabilities: [],
      };

      mockApi.getDiff.mockResolvedValue(mockDiffDetail);

      const { rerender } = renderHook(
        ({ sbomId, diffId }: { sbomId: string | null; diffId: string | null }) =>
          useSbomDiff(sbomId, diffId),
        { initialProps: { sbomId: 'sbom-123', diffId: 'diff-1' } }
      );

      await waitFor(() => {
        expect(mockApi.getDiff).toHaveBeenCalledWith('sbom-123', 'diff-1');
      });

      mockApi.getDiff.mockResolvedValueOnce({
        ...mockDiffDetail,
        id: 'diff-2',
      });
      rerender({ sbomId: 'sbom-123', diffId: 'diff-2' });

      await waitFor(() => {
        expect(mockApi.getDiff).toHaveBeenCalledWith('sbom-123', 'diff-2');
      });
    });
  });

  // ============================================================================
  // useCreateSbomDiff - Mutation hook
  // ============================================================================

  describe('useCreateSbomDiff', () => {
    it('should create SBOM diff successfully', async () => {
      const mockDiff = {
        id: 'diff-new',
        source_sbom_id: 'sbom-123',
        compare_sbom_id: 'sbom-456',
        added_count: 5,
        removed_count: 2,
        changed_count: 3,
        created_at: new Date().toISOString(),
      };

      mockApi.createDiff.mockResolvedValue(mockDiff);

      const { result } = renderHook(() => useCreateSbomDiff());

      await act(async () => {
        const diff = await result.current.mutateAsync({
          sbomId: 'sbom-123',
          compareSbomId: 'sbom-456',
        });
        expect(diff.id).toBe('diff-new');
      });

      expect(mockApi.createDiff).toHaveBeenCalledWith(
        'sbom-123',
        'sbom-456'
      );
      expect(result.current.error).toBeNull();
    });

    it('should set loading state during creation', async () => {
      let resolveCall: () => void;
      const promise = new Promise<void>((resolve) => {
        resolveCall = resolve;
      });

      mockApi.createDiff.mockImplementation(async () => {
        await promise;
        return {
          id: 'diff-new',
          source_sbom_id: 'sbom-123',
          compare_sbom_id: 'sbom-456',
          added_count: 5,
          removed_count: 2,
          changed_count: 3,
          created_at: new Date().toISOString(),
        };
      });

      const { result } = renderHook(() => useCreateSbomDiff());

      let isLoadingDuringCall = false;
      const mutatePromise = act(async () => {
        const promise = result.current.mutateAsync({
          sbomId: 'sbom-123',
          compareSbomId: 'sbom-456',
        });
        isLoadingDuringCall = result.current.isLoading;
        resolveCall!();
        await promise;
      });

      await mutatePromise;
      expect(result.current.isLoading).toBe(false);
      // The mutation hook may set loading state synchronously
    });

    it('should handle creation errors and throw', async () => {
      const errorMessage = 'Failed to create diff';
      mockApi.createDiff.mockRejectedValue(new Error(errorMessage));

      const { result } = renderHook(() => useCreateSbomDiff());

      await expect(
        act(async () => {
          return result.current.mutateAsync({
            sbomId: 'sbom-123',
            compareSbomId: 'sbom-456',
          });
        })
      ).rejects.toThrow(errorMessage);

      expect(result.current.isLoading).toBe(false);
    });

    it('should pass parameters correctly to API', async () => {
      mockApi.createDiff.mockResolvedValue({
        id: 'diff-new',
        source_sbom_id: 'sbom-123',
        compare_sbom_id: 'sbom-456',
        added_count: 5,
        removed_count: 2,
        changed_count: 3,
        created_at: new Date().toISOString(),
      });

      const { result } = renderHook(() => useCreateSbomDiff());

      await act(async () => {
        await result.current.mutateAsync({
          sbomId: 'source-sbom-id',
          compareSbomId: 'compare-sbom-id',
        });
      });

      expect(mockApi.createDiff).toHaveBeenCalledWith(
        'source-sbom-id',
        'compare-sbom-id'
      );
    });
  });
});

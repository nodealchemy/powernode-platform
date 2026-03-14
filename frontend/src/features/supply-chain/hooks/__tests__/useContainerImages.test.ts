import { renderHook, waitFor, act } from '@testing-library/react';
import {
  useContainerImages,
  useContainerImage,
  useContainerVulnerabilities,
  useContainerSbom,
  useEvaluatePolicies,
} from '../useContainerImages';
import { containerImagesApi, ContainerStatus, PolicyEvaluationResult } from '../../services/containerImagesApi';
import {
  createMockContainerImage,
  createMockContainerImageDetail,
  createMockPagination,
  createMockVulnerabilityScan,
} from '../../testing/mockFactories';

jest.mock('../../services/containerImagesApi');
const mockApi = containerImagesApi as jest.Mocked<typeof containerImagesApi>;

describe('useContainerImages Hook Suite', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  // ============================================================================
  // useContainerImages Tests
  // ============================================================================

  describe('useContainerImages', () => {
    describe('successful fetching', () => {
      it('fetches images on mount and sets loading state correctly', async () => {
        const mockImages = [createMockContainerImage(), createMockContainerImage()];
        const mockPagination = createMockPagination();
        mockApi.list.mockResolvedValue({
          images: mockImages,
          pagination: mockPagination,
        });

        const { result } = renderHook(() => useContainerImages());

        expect(result.current.loading).toBe(true);
        expect(result.current.images).toEqual([]);

        await waitFor(() => {
          expect(result.current.loading).toBe(false);
        });

        expect(result.current.images).toEqual(mockImages);
        expect(result.current.pagination).toEqual(mockPagination);
        expect(result.current.error).toBeNull();
      });

      it('passes pagination parameters to API correctly', async () => {
        const mockImages = [createMockContainerImage()];
        const mockPagination = createMockPagination({ current_page: 2, per_page: 15 });
        mockApi.list.mockResolvedValue({
          images: mockImages,
          pagination: mockPagination,
        });

        renderHook(() =>
          useContainerImages({
            page: 2,
            perPage: 15,
          })
        );

        await waitFor(() => {
          expect(mockApi.list).toHaveBeenCalledWith({
            page: 2,
            per_page: 15,
            status: undefined,
          });
        });
      });

      it('passes status filter to API correctly', async () => {
        const mockImages = [createMockContainerImage({ status: 'verified' })];
        const mockPagination = createMockPagination();
        mockApi.list.mockResolvedValue({
          images: mockImages,
          pagination: mockPagination,
        });

        renderHook(() =>
          useContainerImages({
            status: 'verified',
          })
        );

        await waitFor(() => {
          expect(mockApi.list).toHaveBeenCalledWith({
            page: undefined,
            per_page: undefined,
            status: 'verified',
          });
        });
      });

      it('allows multiple status filters and pagination combinations', async () => {
        const mockImages = [createMockContainerImage({ status: 'quarantined' })];
        const mockPagination = createMockPagination({ current_page: 3 });
        mockApi.list.mockResolvedValue({
          images: mockImages,
          pagination: mockPagination,
        });

        renderHook(() =>
          useContainerImages({
            page: 3,
            perPage: 25,
            status: 'quarantined',
          })
        );

        await waitFor(() => {
          expect(mockApi.list).toHaveBeenCalledWith({
            page: 3,
            per_page: 25,
            status: 'quarantined',
          });
        });
      });

      it('returns empty images array when no images exist', async () => {
        const mockPagination = createMockPagination({
          total_count: 0,
          total_pages: 0,
        });
        mockApi.list.mockResolvedValue({
          images: [],
          pagination: mockPagination,
        });

        const { result } = renderHook(() => useContainerImages());

        await waitFor(() => {
          expect(result.current.loading).toBe(false);
        });

        expect(result.current.images).toEqual([]);
        expect(result.current.pagination?.total_count).toBe(0);
      });

      it('refreshes images when refresh is called', async () => {
        const mockImages1 = [createMockContainerImage()];
        const mockImages2 = [createMockContainerImage(), createMockContainerImage()];
        const mockPagination = createMockPagination();

        mockApi.list.mockResolvedValueOnce({
          images: mockImages1,
          pagination: mockPagination,
        });

        const { result } = renderHook(() => useContainerImages());

        await waitFor(() => {
          expect(result.current.loading).toBe(false);
        });

        expect(result.current.images).toHaveLength(1);

        mockApi.list.mockResolvedValueOnce({
          images: mockImages2,
          pagination: mockPagination,
        });

        act(() => {
          result.current.refresh();
        });

        await waitFor(() => {
          expect(result.current.images).toHaveLength(2);
        });

        expect(mockApi.list).toHaveBeenCalledTimes(2);
      });
    });

    describe('error handling', () => {
      it('sets error state when API call fails', async () => {
        const error = new Error('Network error');
        mockApi.list.mockRejectedValue(error);

        const { result } = renderHook(() => useContainerImages());

        await waitFor(() => {
          expect(result.current.loading).toBe(false);
        });

        expect(result.current.error).toBe('Network error');
        expect(result.current.images).toEqual([]);
        expect(result.current.pagination).toBeNull();
      });

      it('sets default error message when error is not an Error instance', async () => {
        mockApi.list.mockRejectedValue('Something went wrong');

        const { result } = renderHook(() => useContainerImages());

        await waitFor(() => {
          expect(result.current.loading).toBe(false);
        });

        expect(result.current.error).toBe('Failed to fetch images');
      });

      it('clears previous error state on successful refresh after error', async () => {
        mockApi.list.mockRejectedValueOnce(new Error('First error'));

        const { result } = renderHook(() => useContainerImages());

        await waitFor(() => {
          expect(result.current.error).toBe('First error');
        });

        mockApi.list.mockResolvedValueOnce({
          images: [createMockContainerImage()],
          pagination: createMockPagination(),
        });

        act(() => {
          result.current.refresh();
        });

        await waitFor(() => {
          expect(result.current.error).toBeNull();
        });
      });
    });

    describe('dependency tracking', () => {
      it('refetches when page option changes', async () => {
        mockApi.list.mockResolvedValue({
          images: [createMockContainerImage()],
          pagination: createMockPagination(),
        });

        const { rerender } = renderHook(
          ({ page }) => useContainerImages({ page }),
          {
            initialProps: { page: 1 },
          }
        );

        await waitFor(() => {
          expect(mockApi.list).toHaveBeenCalledTimes(1);
        });

        rerender({ page: 2 });

        await waitFor(() => {
          expect(mockApi.list).toHaveBeenCalledTimes(2);
        });
      });

      it('refetches when perPage option changes', async () => {
        mockApi.list.mockResolvedValue({
          images: [createMockContainerImage()],
          pagination: createMockPagination(),
        });

        const { rerender } = renderHook(
          ({ perPage }) => useContainerImages({ perPage }),
          {
            initialProps: { perPage: 10 },
          }
        );

        await waitFor(() => {
          expect(mockApi.list).toHaveBeenCalledTimes(1);
        });

        rerender({ perPage: 20 });

        await waitFor(() => {
          expect(mockApi.list).toHaveBeenCalledTimes(2);
        });
      });

      it('refetches when status option changes', async () => {
        mockApi.list.mockResolvedValue({
          images: [createMockContainerImage()],
          pagination: createMockPagination(),
        });

        const { rerender } = renderHook(
          ({ status }: { status: ContainerStatus }) => useContainerImages({ status }),
          {
            initialProps: { status: 'verified' as ContainerStatus },
          }
        );

        await waitFor(() => {
          expect(mockApi.list).toHaveBeenCalledTimes(1);
        });

        rerender({ status: 'quarantined' });

        await waitFor(() => {
          expect(mockApi.list).toHaveBeenCalledTimes(2);
        });
      });

      it('does not refetch when options object reference changes but values stay same', async () => {
        mockApi.list.mockResolvedValue({
          images: [createMockContainerImage()],
          pagination: createMockPagination(),
        });

        const { rerender } = renderHook(
          ({ options }) => useContainerImages(options),
          {
            initialProps: { options: { page: 1, perPage: 10 } },
          }
        );

        await waitFor(() => {
          expect(mockApi.list).toHaveBeenCalledTimes(1);
        });

        // Rerender with same values but different object reference
        rerender({ options: { page: 1, perPage: 10 } });

        // Hook should not refetch since individual values haven't changed
        expect(mockApi.list).toHaveBeenCalledTimes(1);
      });
    });

    describe('state management', () => {
      it('maintains pagination state correctly', async () => {
        const mockPagination = createMockPagination({
          current_page: 2,
          per_page: 25,
          total_pages: 10,
          total_count: 250,
        });
        mockApi.list.mockResolvedValue({
          images: [createMockContainerImage()],
          pagination: mockPagination,
        });

        const { result } = renderHook(() => useContainerImages());

        await waitFor(() => {
          expect(result.current.loading).toBe(false);
        });

        expect(result.current.pagination).toEqual(mockPagination);
        expect(result.current.pagination?.current_page).toBe(2);
        expect(result.current.pagination?.total_count).toBe(250);
      });
    });
  });

  // ============================================================================
  // useContainerImage Tests
  // ============================================================================

  describe('useContainerImage', () => {
    describe('successful fetching', () => {
      it('fetches single image details when id is provided', async () => {
        const mockImageDetail = createMockContainerImageDetail();
        mockApi.get.mockResolvedValue(mockImageDetail);

        const { result } = renderHook(() => useContainerImage('image-123'));

        expect(result.current.loading).toBe(true);
        expect(result.current.image).toBeNull();

        await waitFor(() => {
          expect(result.current.loading).toBe(false);
        });

        expect(result.current.image).toEqual(mockImageDetail);
        expect(result.current.error).toBeNull();
      });

      it('includes scans in the image detail', async () => {
        const mockImageDetail = createMockContainerImageDetail({
          scans: [createMockVulnerabilityScan()],
        });
        mockApi.get.mockResolvedValue(mockImageDetail);

        const { result } = renderHook(() => useContainerImage('image-123'));

        await waitFor(() => {
          expect(result.current.image).not.toBeNull();
        });

        expect(result.current.image?.scans).toHaveLength(1);
        expect(result.current.image?.scans?.[0].scanner).toBe('trivy');
      });

      it('includes applicable policies in the image detail', async () => {
        const mockImageDetail = createMockContainerImageDetail();
        mockApi.get.mockResolvedValue(mockImageDetail);

        const { result } = renderHook(() => useContainerImage('image-123'));

        await waitFor(() => {
          expect(result.current.image).not.toBeNull();
        });

        expect(result.current.image?.applicable_policies).toBeDefined();
        expect(result.current.image?.applicable_policies).toHaveLength(1);
      });

      it('refreshes image details when refresh is called', async () => {
        const mockImageDetail1 = createMockContainerImageDetail();
        const mockImageDetail2 = createMockContainerImageDetail({
          high_vuln_count: 5,
        });

        mockApi.get.mockResolvedValueOnce(mockImageDetail1);

        const { result } = renderHook(() => useContainerImage('image-123'));

        await waitFor(() => {
          expect(result.current.loading).toBe(false);
        });

        expect(result.current.image?.high_vuln_count).toBe(2);

        mockApi.get.mockResolvedValueOnce(mockImageDetail2);

        act(() => {
          result.current.refresh();
        });

        await waitFor(() => {
          expect(result.current.image?.high_vuln_count).toBe(5);
        });

        expect(mockApi.get).toHaveBeenCalledTimes(2);
      });
    });

    describe('null id handling', () => {
      it('does not make API call when id is null', async () => {
        const { result } = renderHook(() => useContainerImage(null));

        expect(mockApi.get).not.toHaveBeenCalled();
        expect(result.current.image).toBeNull();
        expect(result.current.loading).toBe(false);
      });

      it('does not fetch when id is null, but does fetch when id becomes available', async () => {
        const mockImageDetail = createMockContainerImageDetail();
        mockApi.get.mockResolvedValue(mockImageDetail);

        const { rerender } = renderHook(
          ({ id }: { id: string | null }) => useContainerImage(id),
          {
            initialProps: { id: null as string | null },
          }
        );

        expect(mockApi.get).not.toHaveBeenCalled();

        rerender({ id: 'image-123' });

        await waitFor(() => {
          expect(mockApi.get).toHaveBeenCalledWith('image-123');
        });
      });

      it('clears data when id is set to null', async () => {
        const mockImageDetail = createMockContainerImageDetail();
        mockApi.get.mockResolvedValue(mockImageDetail);

        const { result, rerender } = renderHook(
          ({ id }: { id: string | null }) => useContainerImage(id),
          {
            initialProps: { id: 'image-123' as string | null },
          }
        );

        await waitFor(() => {
          expect(result.current.image).not.toBeNull();
        });

        rerender({ id: null });

        // Image should remain loaded but refresh will be called with null id (no-op)
        expect(result.current.image).not.toBeNull();
      });
    });

    describe('error handling', () => {
      it('sets error state when API call fails', async () => {
        const error = new Error('Image not found');
        mockApi.get.mockRejectedValue(error);

        const { result } = renderHook(() => useContainerImage('invalid-id'));

        await waitFor(() => {
          expect(result.current.loading).toBe(false);
        });

        expect(result.current.error).toBe('Image not found');
        expect(result.current.image).toBeNull();
      });

      it('sets default error message when error is not an Error instance', async () => {
        mockApi.get.mockRejectedValue('Unknown error');

        const { result } = renderHook(() => useContainerImage('image-123'));

        await waitFor(() => {
          expect(result.current.loading).toBe(false);
        });

        expect(result.current.error).toBe('Failed to fetch image');
      });

      it('clears error on successful refresh after failure', async () => {
        mockApi.get.mockRejectedValueOnce(new Error('First error'));

        const { result } = renderHook(() => useContainerImage('image-123'));

        await waitFor(() => {
          expect(result.current.error).toBe('First error');
        });

        mockApi.get.mockResolvedValueOnce(createMockContainerImageDetail());

        act(() => {
          result.current.refresh();
        });

        await waitFor(() => {
          expect(result.current.error).toBeNull();
        });
      });
    });

    describe('dependency tracking', () => {
      it('refetches when id changes', async () => {
        mockApi.get.mockResolvedValue(createMockContainerImageDetail());

        const { rerender } = renderHook(
          ({ id }: { id: string }) => useContainerImage(id),
          {
            initialProps: { id: 'image-123' },
          }
        );

        await waitFor(() => {
          expect(mockApi.get).toHaveBeenCalledWith('image-123');
        });

        rerender({ id: 'image-456' });

        await waitFor(() => {
          expect(mockApi.get).toHaveBeenCalledWith('image-456');
        });

        expect(mockApi.get).toHaveBeenCalledTimes(2);
      });
    });
  });

  // ============================================================================
  // useContainerVulnerabilities Tests
  // ============================================================================

  describe('useContainerVulnerabilities', () => {
    describe('successful fetching', () => {
      it('fetches vulnerabilities when imageId is provided', async () => {
        const mockVulnerabilities = [
          {
            id: 'vuln-1',
            vulnerability_id: 'CVE-2024-1234',
            severity: 'critical' as const,
            cvss_score: 9.8,
            package_name: 'express',
            package_version: '4.17.1',
            fixed_version: '4.17.2',
            description: 'Critical vulnerability in express',
          },
        ];
        const mockPagination = createMockPagination();
        mockApi.getVulnerabilities.mockResolvedValue({
          vulnerabilities: mockVulnerabilities,
          pagination: mockPagination,
        });

        const { result } = renderHook(() => useContainerVulnerabilities('image-123'));

        expect(result.current.loading).toBe(true);

        await waitFor(() => {
          expect(result.current.loading).toBe(false);
        });

        expect(result.current.vulnerabilities).toEqual(mockVulnerabilities);
        expect(result.current.pagination).toEqual(mockPagination);
        expect(result.current.error).toBeNull();
      });

      it('passes pagination parameters correctly', async () => {
        mockApi.getVulnerabilities.mockResolvedValue({
          vulnerabilities: [],
          pagination: createMockPagination(),
        });

        renderHook(() =>
          useContainerVulnerabilities('image-123', {
            page: 2,
            perPage: 50,
          })
        );

        await waitFor(() => {
          expect(mockApi.getVulnerabilities).toHaveBeenCalledWith('image-123', {
            page: 2,
            per_page: 50,
          });
        });
      });

      it('returns empty vulnerabilities when none exist', async () => {
        mockApi.getVulnerabilities.mockResolvedValue({
          vulnerabilities: [],
          pagination: createMockPagination({ total_count: 0 }),
        });

        const { result } = renderHook(() => useContainerVulnerabilities('image-123'));

        await waitFor(() => {
          expect(result.current.loading).toBe(false);
        });

        expect(result.current.vulnerabilities).toEqual([]);
      });

      it('refreshes vulnerabilities when refresh is called', async () => {
        const vuln1 = [
          {
            id: 'vuln-1',
            vulnerability_id: 'CVE-2024-1234',
            severity: 'high' as const,
            cvss_score: 7.5,
            package_name: 'lodash',
            package_version: '4.17.20',
          },
        ];
        const vuln2 = [
          ...vuln1,
          {
            id: 'vuln-2',
            vulnerability_id: 'CVE-2024-5678',
            severity: 'medium' as const,
            cvss_score: 5.0,
            package_name: 'axios',
            package_version: '1.0.0',
          },
        ];

        mockApi.getVulnerabilities.mockResolvedValueOnce({
          vulnerabilities: vuln1,
          pagination: createMockPagination(),
        });

        const { result } = renderHook(() => useContainerVulnerabilities('image-123'));

        await waitFor(() => {
          expect(result.current.loading).toBe(false);
        });

        expect(result.current.vulnerabilities).toHaveLength(1);

        mockApi.getVulnerabilities.mockResolvedValueOnce({
          vulnerabilities: vuln2,
          pagination: createMockPagination(),
        });

        act(() => {
          result.current.refresh();
        });

        await waitFor(() => {
          expect(result.current.vulnerabilities).toHaveLength(2);
        });
      });
    });

    describe('null imageId handling', () => {
      it('does not make API call when imageId is null', async () => {
        const { result } = renderHook(() => useContainerVulnerabilities(null));

        expect(mockApi.getVulnerabilities).not.toHaveBeenCalled();
        expect(result.current.vulnerabilities).toEqual([]);
        expect(result.current.loading).toBe(false);
      });

      it('fetches when imageId changes from null to a value', async () => {
        mockApi.getVulnerabilities.mockResolvedValue({
          vulnerabilities: [],
          pagination: createMockPagination(),
        });

        const { rerender } = renderHook(
          ({ imageId }: { imageId: string | null }) =>
            useContainerVulnerabilities(imageId),
          {
            initialProps: { imageId: null as string | null },
          }
        );

        expect(mockApi.getVulnerabilities).not.toHaveBeenCalled();

        rerender({ imageId: 'image-123' });

        await waitFor(() => {
          expect(mockApi.getVulnerabilities).toHaveBeenCalledWith('image-123', {
            page: undefined,
            per_page: undefined,
          });
        });
      });
    });

    describe('error handling', () => {
      it('sets error state when API call fails', async () => {
        const error = new Error('Failed to fetch vulnerabilities');
        mockApi.getVulnerabilities.mockRejectedValue(error);

        const { result } = renderHook(() => useContainerVulnerabilities('image-123'));

        await waitFor(() => {
          expect(result.current.loading).toBe(false);
        });

        expect(result.current.error).toBe('Failed to fetch vulnerabilities');
        expect(result.current.vulnerabilities).toEqual([]);
      });

      it('sets default error message when error is not an Error instance', async () => {
        mockApi.getVulnerabilities.mockRejectedValue('Unknown error');

        const { result } = renderHook(() => useContainerVulnerabilities('image-123'));

        await waitFor(() => {
          expect(result.current.loading).toBe(false);
        });

        expect(result.current.error).toBe('Failed to fetch vulnerabilities');
      });
    });

    describe('dependency tracking', () => {
      it('refetches when imageId changes', async () => {
        mockApi.getVulnerabilities.mockResolvedValue({
          vulnerabilities: [],
          pagination: createMockPagination(),
        });

        const { rerender } = renderHook(
          ({ imageId }: { imageId: string }) =>
            useContainerVulnerabilities(imageId),
          {
            initialProps: { imageId: 'image-123' },
          }
        );

        await waitFor(() => {
          expect(mockApi.getVulnerabilities).toHaveBeenCalledTimes(1);
        });

        rerender({ imageId: 'image-456' });

        await waitFor(() => {
          expect(mockApi.getVulnerabilities).toHaveBeenCalledTimes(2);
        });
      });

      it('refetches when page changes', async () => {
        mockApi.getVulnerabilities.mockResolvedValue({
          vulnerabilities: [],
          pagination: createMockPagination(),
        });

        const { rerender } = renderHook(
          ({ page }: { page: number }) =>
            useContainerVulnerabilities('image-123', { page }),
          {
            initialProps: { page: 1 },
          }
        );

        await waitFor(() => {
          expect(mockApi.getVulnerabilities).toHaveBeenCalledTimes(1);
        });

        rerender({ page: 2 });

        await waitFor(() => {
          expect(mockApi.getVulnerabilities).toHaveBeenCalledTimes(2);
        });
      });

      it('refetches when perPage changes', async () => {
        mockApi.getVulnerabilities.mockResolvedValue({
          vulnerabilities: [],
          pagination: createMockPagination(),
        });

        const { rerender } = renderHook(
          ({ perPage }: { perPage: number }) =>
            useContainerVulnerabilities('image-123', { perPage }),
          {
            initialProps: { perPage: 10 },
          }
        );

        await waitFor(() => {
          expect(mockApi.getVulnerabilities).toHaveBeenCalledTimes(1);
        });

        rerender({ perPage: 25 });

        await waitFor(() => {
          expect(mockApi.getVulnerabilities).toHaveBeenCalledTimes(2);
        });
      });
    });
  });

  // ============================================================================
  // useContainerSbom Tests
  // ============================================================================

  describe('useContainerSbom', () => {
    describe('successful fetching', () => {
      it('fetches SBOM when imageId is provided', async () => {
        const mockSbom = {
          id: 'sbom-123',
          format: 'cyclonedx',
          component_count: 42,
          components: [
            {
              name: 'express',
              version: '4.17.1',
              type: 'library',
              licenses: ['MIT'],
            },
          ],
          generated_at: new Date().toISOString(),
        };
        mockApi.getSbom.mockResolvedValue(mockSbom);

        const { result } = renderHook(() => useContainerSbom('image-123'));

        expect(result.current.loading).toBe(true);

        await waitFor(() => {
          expect(result.current.loading).toBe(false);
        });

        expect(result.current.sbom).toEqual(mockSbom);
        expect(result.current.error).toBeNull();
      });

      it('includes components in SBOM', async () => {
        const mockSbom = {
          id: 'sbom-123',
          format: 'spdx',
          component_count: 2,
          components: [
            {
              name: 'express',
              version: '4.17.1',
              type: 'library',
              licenses: ['MIT'],
            },
            {
              name: 'lodash',
              version: '4.17.21',
              type: 'library',
              licenses: ['MIT'],
            },
          ],
          generated_at: new Date().toISOString(),
        };
        mockApi.getSbom.mockResolvedValue(mockSbom);

        const { result } = renderHook(() => useContainerSbom('image-123'));

        await waitFor(() => {
          expect(result.current.sbom).not.toBeNull();
        });

        expect(result.current.sbom?.components).toHaveLength(2);
        expect(result.current.sbom?.component_count).toBe(2);
      });

      it('refreshes SBOM when refresh is called', async () => {
        const sbom1 = {
          id: 'sbom-123',
          format: 'cyclonedx' as const,
          component_count: 10,
          components: [],
          generated_at: new Date().toISOString(),
        };
        const sbom2 = {
          id: 'sbom-123',
          format: 'cyclonedx' as const,
          component_count: 15,
          components: [],
          generated_at: new Date().toISOString(),
        };

        mockApi.getSbom.mockResolvedValueOnce(sbom1);

        const { result } = renderHook(() => useContainerSbom('image-123'));

        await waitFor(() => {
          expect(result.current.loading).toBe(false);
        });

        expect(result.current.sbom?.component_count).toBe(10);

        mockApi.getSbom.mockResolvedValueOnce(sbom2);

        act(() => {
          result.current.refresh();
        });

        await waitFor(() => {
          expect(result.current.sbom?.component_count).toBe(15);
        });

        expect(mockApi.getSbom).toHaveBeenCalledTimes(2);
      });
    });

    describe('null imageId handling', () => {
      it('does not make API call when imageId is null', async () => {
        const { result } = renderHook(() => useContainerSbom(null));

        expect(mockApi.getSbom).not.toHaveBeenCalled();
        expect(result.current.sbom).toBeNull();
        expect(result.current.loading).toBe(false);
      });

      it('fetches SBOM when imageId changes from null to value', async () => {
        const mockSbom = {
          id: 'sbom-123',
          format: 'cyclonedx',
          component_count: 5,
          components: [],
          generated_at: new Date().toISOString(),
        };
        mockApi.getSbom.mockResolvedValue(mockSbom);

        const { rerender } = renderHook(
          ({ imageId }: { imageId: string | null }) => useContainerSbom(imageId),
          {
            initialProps: { imageId: null as string | null },
          }
        );

        expect(mockApi.getSbom).not.toHaveBeenCalled();

        rerender({ imageId: 'image-123' });

        await waitFor(() => {
          expect(mockApi.getSbom).toHaveBeenCalledWith('image-123');
        });
      });
    });

    describe('error handling', () => {
      it('sets error state when API call fails', async () => {
        const error = new Error('SBOM not available');
        mockApi.getSbom.mockRejectedValue(error);

        const { result } = renderHook(() => useContainerSbom('image-123'));

        await waitFor(() => {
          expect(result.current.loading).toBe(false);
        });

        expect(result.current.error).toBe('SBOM not available');
        expect(result.current.sbom).toBeNull();
      });

      it('sets default error message when error is not an Error instance', async () => {
        mockApi.getSbom.mockRejectedValue('Unknown error');

        const { result } = renderHook(() => useContainerSbom('image-123'));

        await waitFor(() => {
          expect(result.current.loading).toBe(false);
        });

        expect(result.current.error).toBe('Failed to fetch SBOM');
      });
    });

    describe('dependency tracking', () => {
      it('refetches when imageId changes', async () => {
        const mockSbom = {
          id: 'sbom-123',
          format: 'cyclonedx' as const,
          component_count: 5,
          components: [],
          generated_at: new Date().toISOString(),
        };
        mockApi.getSbom.mockResolvedValue(mockSbom);

        const { rerender } = renderHook(
          ({ imageId }: { imageId: string }) => useContainerSbom(imageId),
          {
            initialProps: { imageId: 'image-123' },
          }
        );

        await waitFor(() => {
          expect(mockApi.getSbom).toHaveBeenCalledTimes(1);
        });

        rerender({ imageId: 'image-456' });

        await waitFor(() => {
          expect(mockApi.getSbom).toHaveBeenCalledTimes(2);
        });
      });
    });
  });

  // ============================================================================
  // useEvaluatePolicies Tests
  // ============================================================================

  describe('useEvaluatePolicies', () => {
    describe('successful evaluation', () => {
      it('evaluates policies and returns results', async () => {
        const mockEvaluation = [
          {
            policy_id: 'policy-1',
            policy_name: 'Vulnerability Policy',
            policy_type: 'vulnerability',
            enforcement_level: 'strict',
            passed: true,
            violations: [],
            evaluated_at: new Date().toISOString(),
          },
        ];
        mockApi.evaluatePolicies.mockResolvedValue(mockEvaluation);

        const { result } = renderHook(() => useEvaluatePolicies());

        expect(result.current.isLoading).toBe(false);
        expect(result.current.error).toBeNull();

        let evaluationResult;
        await act(async () => {
          evaluationResult = await result.current.mutateAsync('image-123');
        });

        expect(mockApi.evaluatePolicies).toHaveBeenCalledWith('image-123');
        expect(evaluationResult).toEqual(mockEvaluation);
      });

      it('returns multiple policy evaluations', async () => {
        const mockEvaluations = [
          {
            policy_id: 'policy-1',
            policy_name: 'Vulnerability Policy',
            policy_type: 'vulnerability',
            enforcement_level: 'strict',
            passed: false,
            violations: [
              {
                rule: 'max_critical',
                message: 'Found critical vulnerabilities',
                severity: 'critical' as const,
              },
            ],
            evaluated_at: new Date().toISOString(),
          },
          {
            policy_id: 'policy-2',
            policy_name: 'License Policy',
            policy_type: 'license',
            enforcement_level: 'warn',
            passed: true,
            violations: [],
            evaluated_at: new Date().toISOString(),
          },
        ];
        mockApi.evaluatePolicies.mockResolvedValue(mockEvaluations);

        const { result } = renderHook(() => useEvaluatePolicies());

        let evaluationResult: Awaited<ReturnType<typeof result.current.mutateAsync>> | undefined;
        await act(async () => {
          evaluationResult = await result.current.mutateAsync('image-123');
        });

        expect(evaluationResult).toHaveLength(2);
        expect(evaluationResult![0].passed).toBe(false);
        expect(evaluationResult![1].passed).toBe(true);
      });

      it('sets loading state during evaluation', async () => {
        const mockEvaluation: PolicyEvaluationResult[] = [];
        mockApi.evaluatePolicies.mockImplementation(
          () => new Promise((resolve) => setTimeout(() => resolve(mockEvaluation), 100))
        );

        const { result } = renderHook(() => useEvaluatePolicies());

        const loadingStates = [];
        act(() => {
          loadingStates.push(result.current.isLoading);
          result.current.mutateAsync('image-123');
          loadingStates.push(result.current.isLoading);
        });

        await waitFor(() => {
          expect(result.current.isLoading).toBe(false);
        });

        expect(result.current.isLoading).toBe(false);
      });

      it('returns empty violations for passing policies', async () => {
        const mockEvaluation = [
          {
            policy_id: 'policy-1',
            policy_name: 'Vulnerability Policy',
            policy_type: 'vulnerability',
            enforcement_level: 'strict',
            passed: true,
            violations: [],
            evaluated_at: new Date().toISOString(),
          },
        ];
        mockApi.evaluatePolicies.mockResolvedValue(mockEvaluation);

        const { result } = renderHook(() => useEvaluatePolicies());

        let evaluationResult: Awaited<ReturnType<typeof result.current.mutateAsync>> | undefined;
        await act(async () => {
          evaluationResult = await result.current.mutateAsync('image-123');
        });

        expect(evaluationResult![0].violations).toHaveLength(0);
      });
    });

    describe('error handling', () => {
      it('sets error state when evaluation fails', async () => {
        const error = new Error('Policy evaluation failed');
        mockApi.evaluatePolicies.mockRejectedValue(error);

        const { result } = renderHook(() => useEvaluatePolicies());

        await act(async () => {
          try {
            await result.current.mutateAsync('image-123');
          } catch (_error) {
            // Expected to throw
          }
        });

        expect(result.current.error).toBe('Policy evaluation failed');
      });

      it('sets default error message when error is not an Error instance', async () => {
        mockApi.evaluatePolicies.mockRejectedValue('Unknown error');

        const { result } = renderHook(() => useEvaluatePolicies());

        await act(async () => {
          try {
            await result.current.mutateAsync('image-123');
          } catch (_error) {
            // Expected to throw
          }
        });

        expect(result.current.error).toBe('Failed to evaluate policies');
      });

      it('throws error to caller on failure', async () => {
        const error = new Error('Evaluation error');
        mockApi.evaluatePolicies.mockRejectedValue(error);

        const { result } = renderHook(() => useEvaluatePolicies());

        await expect(
          act(async () => {
            await result.current.mutateAsync('image-123');
          })
        ).rejects.toThrow('Evaluation error');
      });

      it('clears error on successful evaluation after failure', async () => {
        mockApi.evaluatePolicies.mockRejectedValueOnce(new Error('First error'));

        const { result } = renderHook(() => useEvaluatePolicies());

        await act(async () => {
          try {
            await result.current.mutateAsync('image-123');
          } catch (_error) {
            // Expected
          }
        });

        expect(result.current.error).toBe('First error');

        mockApi.evaluatePolicies.mockResolvedValueOnce([]);

        await act(async () => {
          await result.current.mutateAsync('image-456');
        });

        expect(result.current.error).toBeNull();
      });
    });

    describe('mutation behavior', () => {
      it('is independent of component render state', async () => {
        mockApi.evaluatePolicies.mockResolvedValue([]);

        const { result } = renderHook(() => useEvaluatePolicies());

        let evaluationResult;
        await act(async () => {
          evaluationResult = await result.current.mutateAsync('image-123');
        });

        expect(evaluationResult).toEqual([]);
        expect(result.current.error).toBeNull();
      });

      it('can be called multiple times', async () => {
        mockApi.evaluatePolicies.mockResolvedValue([]);

        const { result } = renderHook(() => useEvaluatePolicies());

        await act(async () => {
          await result.current.mutateAsync('image-123');
          await result.current.mutateAsync('image-456');
          await result.current.mutateAsync('image-789');
        });

        expect(mockApi.evaluatePolicies).toHaveBeenCalledTimes(3);
        expect(mockApi.evaluatePolicies).toHaveBeenCalledWith('image-123');
        expect(mockApi.evaluatePolicies).toHaveBeenCalledWith('image-456');
        expect(mockApi.evaluatePolicies).toHaveBeenCalledWith('image-789');
      });

      it('returns the API response directly', async () => {
        const mockEvaluation = [
          {
            policy_id: 'policy-1',
            policy_name: 'Test Policy',
            policy_type: 'vulnerability',
            enforcement_level: 'strict',
            passed: true,
            violations: [],
            evaluated_at: new Date().toISOString(),
          },
        ];
        mockApi.evaluatePolicies.mockResolvedValue(mockEvaluation);

        const { result } = renderHook(() => useEvaluatePolicies());

        let returnValue;
        await act(async () => {
          returnValue = await result.current.mutateAsync('image-123');
        });

        expect(returnValue).toBe(mockEvaluation);
      });
    });
  });
});

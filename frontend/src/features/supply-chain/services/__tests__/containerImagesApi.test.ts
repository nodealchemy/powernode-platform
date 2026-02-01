import { containerImagesApi } from '../containerImagesApi';
import { apiClient } from '@/shared/services/apiClient';
import type { AxiosResponse, InternalAxiosRequestConfig, AxiosHeaders } from 'axios';

jest.mock('@/shared/services/apiClient', () => ({
  apiClient: {
    get: jest.fn(),
    post: jest.fn(),
    patch: jest.fn(),
    delete: jest.fn(),
  },
}));

const mockApiClient = apiClient as jest.Mocked<typeof apiClient>;

// Helper to create mock Axios responses
function mockAxiosResponse<T>(data: T): AxiosResponse<T> {
  return {
    data,
    status: 200,
    statusText: 'OK',
    headers: {},
    config: { headers: {} as AxiosHeaders } as InternalAxiosRequestConfig,
  };
}

describe('containerImagesApi', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  // Mock data
  const mockContainerImage = {
    id: 'image-001',
    registry: 'docker.io',
    repository: 'myapp',
    tag: 'latest',
    digest: 'sha256:abc123',
    status: 'verified' as const,
    critical_vuln_count: 0,
    high_vuln_count: 2,
    medium_vuln_count: 5,
    low_vuln_count: 10,
    is_deployed: true,
    last_scanned_at: '2024-01-21T10:00:00Z',
    created_at: '2024-01-20T10:00:00Z',
    updated_at: '2024-01-21T10:00:00Z',
  };

  const mockContainerImageDetail = {
    ...mockContainerImage,
    scans: [
      {
        id: 'scan-001',
        scanner: 'trivy',
        status: 'completed',
        critical_count: 0,
        high_count: 2,
        medium_count: 5,
        low_count: 10,
        started_at: '2024-01-21T09:00:00Z',
        completed_at: '2024-01-21T10:00:00Z',
      },
    ],
    applicable_policies: [
      {
        id: 'policy-001',
        name: 'Vulnerability Policy',
        policy_type: 'vulnerability',
        enforcement_level: 'strict',
        is_active: true,
      },
    ],
  };

  const mockPagination = {
    current_page: 1,
    per_page: 20,
    total_pages: 5,
    total_count: 100,
  };

  const mockVulnerability = {
    id: 'vuln-001',
    vulnerability_id: 'CVE-2024-1234',
    severity: 'high' as const,
    cvss_score: 7.5,
    package_name: 'express',
    package_version: '4.17.1',
    fixed_version: '4.17.2',
    description: 'Vulnerability in express package',
    published_at: '2024-01-15T00:00:00Z',
    exploit_available: true,
  };

  const mockSbom = {
    id: 'sbom-001',
    format: 'cyclonedx',
    component_count: 25,
    components: [
      {
        name: 'express',
        version: '4.17.1',
        type: 'library',
        licenses: ['MIT'],
      },
    ],
    generated_at: '2024-01-21T10:00:00Z',
  };

  const mockPolicyEvaluation = {
    policy_id: 'policy-001',
    policy_name: 'Vulnerability Policy',
    policy_type: 'vulnerability',
    enforcement_level: 'strict',
    passed: false,
    violations: [
      {
        rule: 'max_critical_vulnerabilities',
        message: 'Found 1 critical vulnerability, max is 0',
        severity: 'critical' as const,
      },
    ],
    evaluated_at: '2024-01-21T10:00:00Z',
  };

  describe('list', () => {
    it('should fetch container images without parameters', async () => {
      mockApiClient.get.mockResolvedValueOnce(mockAxiosResponse({
        data: {
          images: [mockContainerImage],
          pagination: mockPagination,
        },
      }));

      const result = await containerImagesApi.list();

      expect(mockApiClient.get).toHaveBeenCalledWith('/supply_chain/container_images', {
        params: undefined,
      });
      expect(result).toEqual({
        images: [mockContainerImage],
        pagination: mockPagination,
      });
    });

    it('should fetch container images with pagination parameters', async () => {
      const params = { page: 2, per_page: 10 };
      mockApiClient.get.mockResolvedValueOnce(mockAxiosResponse({
        data: {
          images: [mockContainerImage],
          pagination: { ...mockPagination, current_page: 2 },
        },
      }));

      const result = await containerImagesApi.list(params);

      expect(mockApiClient.get).toHaveBeenCalledWith('/supply_chain/container_images', {
        params,
      });
      expect(result.pagination.current_page).toBe(2);
    });

    it('should fetch container images filtered by status', async () => {
      const params = { status: 'quarantined' as const };
      mockApiClient.get.mockResolvedValueOnce(mockAxiosResponse({
        data: {
          images: [{ ...mockContainerImage, status: 'quarantined' }],
          pagination: mockPagination,
        },
      }));

      const result = await containerImagesApi.list(params);

      expect(mockApiClient.get).toHaveBeenCalledWith('/supply_chain/container_images', {
        params,
      });
      expect(result.images[0].status).toBe('quarantined');
    });

    it('should fetch container images filtered by registry', async () => {
      const params = { registry: 'gcr.io' };
      mockApiClient.get.mockResolvedValueOnce(mockAxiosResponse({
        data: {
          images: [{ ...mockContainerImage, registry: 'gcr.io' }],
          pagination: mockPagination,
        },
      }));

      const result = await containerImagesApi.list(params);

      expect(mockApiClient.get).toHaveBeenCalledWith('/supply_chain/container_images', {
        params,
      });
      expect(result.images[0].registry).toBe('gcr.io');
    });

    it('should fetch container images filtered by deployment status', async () => {
      const params = { is_deployed: false };
      mockApiClient.get.mockResolvedValueOnce(mockAxiosResponse({
        data: {
          images: [{ ...mockContainerImage, is_deployed: false }],
          pagination: mockPagination,
        },
      }));

      const result = await containerImagesApi.list(params);

      expect(mockApiClient.get).toHaveBeenCalledWith('/supply_chain/container_images', {
        params,
      });
      expect(result.images[0].is_deployed).toBe(false);
    });

    it('should handle list error', async () => {
      const error = new Error('Failed to fetch images');
      mockApiClient.get.mockRejectedValueOnce(error);

      await expect(containerImagesApi.list()).rejects.toThrow('Failed to fetch images');
    });
  });

  describe('get', () => {
    it('should fetch a single container image by id', async () => {
      mockApiClient.get.mockResolvedValueOnce(mockAxiosResponse({
        data: {
          image: mockContainerImageDetail,
        },
      }));

      const result = await containerImagesApi.get('image-001');

      expect(mockApiClient.get).toHaveBeenCalledWith('/supply_chain/container_images/image-001');
      expect(result).toEqual(mockContainerImageDetail);
      expect(result.scans).toBeDefined();
      expect(result.applicable_policies).toBeDefined();
    });

    it('should return container image with scans', async () => {
      mockApiClient.get.mockResolvedValueOnce(mockAxiosResponse({
        data: {
          image: mockContainerImageDetail,
        },
      }));

      const result = await containerImagesApi.get('image-001');

      expect(result.scans).toHaveLength(1);
      expect(result.scans?.[0].scanner).toBe('trivy');
    });

    it('should return container image with applicable policies', async () => {
      mockApiClient.get.mockResolvedValueOnce(mockAxiosResponse({
        data: {
          image: mockContainerImageDetail,
        },
      }));

      const result = await containerImagesApi.get('image-001');

      expect(result.applicable_policies).toHaveLength(1);
      expect(result.applicable_policies?.[0].name).toBe('Vulnerability Policy');
    });

    it('should handle get error', async () => {
      const error = new Error('Image not found');
      mockApiClient.get.mockRejectedValueOnce(error);

      await expect(containerImagesApi.get('invalid-id')).rejects.toThrow('Image not found');
    });
  });

  describe('scan', () => {
    it('should initiate a scan on a container image', async () => {
      mockApiClient.post.mockResolvedValueOnce(mockAxiosResponse({
        data: {
          image: mockContainerImage,
        },
      }));

      const result = await containerImagesApi.scan('image-001');

      expect(mockApiClient.post).toHaveBeenCalledWith(
        '/supply_chain/container_images/image-001/scan'
      );
      expect(result).toEqual(mockContainerImage);
    });

    it('should return updated image after scan', async () => {
      const scannedImage = { ...mockContainerImage, last_scanned_at: '2024-01-21T11:00:00Z' };
      mockApiClient.post.mockResolvedValueOnce(mockAxiosResponse({
        data: {
          image: scannedImage,
        },
      }));

      const result = await containerImagesApi.scan('image-001');

      expect(result.last_scanned_at).toBe('2024-01-21T11:00:00Z');
    });

    it('should handle scan error', async () => {
      const error = new Error('Scan failed');
      mockApiClient.post.mockRejectedValueOnce(error);

      await expect(containerImagesApi.scan('image-001')).rejects.toThrow('Scan failed');
    });
  });

  describe('verify', () => {
    it('should verify a container image', async () => {
      mockApiClient.post.mockResolvedValueOnce(mockAxiosResponse({
        data: {
          image: mockContainerImage,
        },
      }));

      const result = await containerImagesApi.verify('image-001');

      expect(mockApiClient.post).toHaveBeenCalledWith(
        '/supply_chain/container_images/image-001/verify'
      );
      expect(result).toEqual(mockContainerImage);
    });

    it('should update status to verified', async () => {
      const verifiedImage = { ...mockContainerImage, status: 'verified' as const };
      mockApiClient.post.mockResolvedValueOnce(mockAxiosResponse({
        data: {
          image: verifiedImage,
        },
      }));

      const result = await containerImagesApi.verify('image-001');

      expect(result.status).toBe('verified');
    });

    it('should handle verify error', async () => {
      const error = new Error('Verification failed');
      mockApiClient.post.mockRejectedValueOnce(error);

      await expect(containerImagesApi.verify('image-001')).rejects.toThrow(
        'Verification failed'
      );
    });
  });

  describe('quarantine', () => {
    it('should quarantine a container image with reason', async () => {
      const reason = 'Critical vulnerabilities detected';
      mockApiClient.post.mockResolvedValueOnce(mockAxiosResponse({
        data: {
          image: { ...mockContainerImage, status: 'quarantined' as const },
        },
      }));

      const result = await containerImagesApi.quarantine('image-001', reason);

      expect(mockApiClient.post).toHaveBeenCalledWith(
        '/supply_chain/container_images/image-001/quarantine',
        { reason }
      );
      expect(result.status).toBe('quarantined');
    });

    it('should pass reason in request body', async () => {
      const reason = 'Policy violation detected';
      mockApiClient.post.mockResolvedValueOnce(mockAxiosResponse({
        data: {
          image: mockContainerImage,
        },
      }));

      await containerImagesApi.quarantine('image-001', reason);

      expect(mockApiClient.post).toHaveBeenCalledWith(
        '/supply_chain/container_images/image-001/quarantine',
        { reason }
      );
    });

    it('should handle quarantine error', async () => {
      const error = new Error('Cannot quarantine image');
      mockApiClient.post.mockRejectedValueOnce(error);

      await expect(
        containerImagesApi.quarantine('image-001', 'Some reason')
      ).rejects.toThrow('Cannot quarantine image');
    });
  });

  describe('delete', () => {
    it('should delete a container image', async () => {
      mockApiClient.delete.mockResolvedValueOnce(mockAxiosResponse(null));

      await containerImagesApi.delete('image-001');

      expect(mockApiClient.delete).toHaveBeenCalledWith(
        '/supply_chain/container_images/image-001'
      );
    });

    it('should handle delete error', async () => {
      const error = new Error('Cannot delete deployed image');
      mockApiClient.delete.mockRejectedValueOnce(error);

      await expect(containerImagesApi.delete('image-001')).rejects.toThrow(
        'Cannot delete deployed image'
      );
    });

    it('should successfully delete and not return data', async () => {
      mockApiClient.delete.mockResolvedValueOnce(mockAxiosResponse(null));

      const result = await containerImagesApi.delete('image-001');

      expect(result).toBeUndefined();
    });
  });

  describe('getVulnerabilities', () => {
    it('should fetch vulnerabilities for an image without parameters', async () => {
      mockApiClient.get.mockResolvedValueOnce(mockAxiosResponse({
        data: {
          vulnerabilities: [mockVulnerability],
          pagination: mockPagination,
        },
      }));

      const result = await containerImagesApi.getVulnerabilities('image-001');

      expect(mockApiClient.get).toHaveBeenCalledWith(
        '/supply_chain/container_images/image-001/vulnerabilities',
        { params: undefined }
      );
      expect(result).toEqual({
        vulnerabilities: [mockVulnerability],
        pagination: mockPagination,
      });
    });

    it('should fetch vulnerabilities with pagination parameters', async () => {
      const params = { page: 2, per_page: 25 };
      mockApiClient.get.mockResolvedValueOnce(mockAxiosResponse({
        data: {
          vulnerabilities: [mockVulnerability],
          pagination: { ...mockPagination, current_page: 2 },
        },
      }));

      await containerImagesApi.getVulnerabilities('image-001', params);

      expect(mockApiClient.get).toHaveBeenCalledWith(
        '/supply_chain/container_images/image-001/vulnerabilities',
        { params }
      );
    });

    it('should fetch vulnerabilities filtered by severity', async () => {
      const params = { severity: 'critical' as const };
      mockApiClient.get.mockResolvedValueOnce(mockAxiosResponse({
        data: {
          vulnerabilities: [
            { ...mockVulnerability, severity: 'critical' as const, cvss_score: 9.8 },
          ],
          pagination: mockPagination,
        },
      }));

      const result = await containerImagesApi.getVulnerabilities('image-001', params);

      expect(mockApiClient.get).toHaveBeenCalledWith(
        '/supply_chain/container_images/image-001/vulnerabilities',
        { params }
      );
      expect(result.vulnerabilities[0].severity).toBe('critical');
    });

    it('should handle vulnerability fetch error', async () => {
      const error = new Error('Failed to fetch vulnerabilities');
      mockApiClient.get.mockRejectedValueOnce(error);

      await expect(containerImagesApi.getVulnerabilities('image-001')).rejects.toThrow(
        'Failed to fetch vulnerabilities'
      );
    });

    it('should return multiple vulnerabilities', async () => {
      const vulnerabilities = [
        mockVulnerability,
        { ...mockVulnerability, id: 'vuln-002', vulnerability_id: 'CVE-2024-5678' },
      ];
      mockApiClient.get.mockResolvedValueOnce(mockAxiosResponse({
        data: {
          vulnerabilities,
          pagination: mockPagination,
        },
      }));

      const result = await containerImagesApi.getVulnerabilities('image-001');

      expect(result.vulnerabilities).toHaveLength(2);
    });
  });

  describe('getSbom', () => {
    it('should fetch SBOM for an image', async () => {
      mockApiClient.get.mockResolvedValueOnce(mockAxiosResponse({
        data: {
          sbom: mockSbom,
        },
      }));

      const result = await containerImagesApi.getSbom('image-001');

      expect(mockApiClient.get).toHaveBeenCalledWith(
        '/supply_chain/container_images/image-001/sbom'
      );
      expect(result).toEqual(mockSbom);
    });

    it('should return SBOM with components', async () => {
      mockApiClient.get.mockResolvedValueOnce(mockAxiosResponse({
        data: {
          sbom: mockSbom,
        },
      }));

      const result = await containerImagesApi.getSbom('image-001');

      expect(result.components).toHaveLength(1);
      expect(result.components[0].name).toBe('express');
    });

    it('should return SBOM with correct format', async () => {
      mockApiClient.get.mockResolvedValueOnce(mockAxiosResponse({
        data: {
          sbom: mockSbom,
        },
      }));

      const result = await containerImagesApi.getSbom('image-001');

      expect(result.format).toBe('cyclonedx');
      expect(result.component_count).toBe(25);
    });

    it('should handle SBOM fetch error', async () => {
      const error = new Error('SBOM not available');
      mockApiClient.get.mockRejectedValueOnce(error);

      await expect(containerImagesApi.getSbom('image-001')).rejects.toThrow(
        'SBOM not available'
      );
    });
  });

  describe('evaluatePolicies', () => {
    it('should evaluate policies for an image', async () => {
      mockApiClient.post.mockResolvedValueOnce(mockAxiosResponse({
        data: {
          evaluations: [mockPolicyEvaluation],
        },
      }));

      const result = await containerImagesApi.evaluatePolicies('image-001');

      expect(mockApiClient.post).toHaveBeenCalledWith(
        '/supply_chain/container_images/image-001/evaluate_policies'
      );
      expect(result).toEqual([mockPolicyEvaluation]);
    });

    it('should return multiple policy evaluations', async () => {
      const evaluations = [
        mockPolicyEvaluation,
        {
          ...mockPolicyEvaluation,
          policy_id: 'policy-002',
          policy_name: 'License Policy',
          passed: true,
          violations: [],
        },
      ];
      mockApiClient.post.mockResolvedValueOnce(mockAxiosResponse({
        data: {
          evaluations,
        },
      }));

      const result = await containerImagesApi.evaluatePolicies('image-001');

      expect(result).toHaveLength(2);
      expect(result[0].passed).toBe(false);
      expect(result[1].passed).toBe(true);
    });

    it('should include violations in policy evaluation', async () => {
      mockApiClient.post.mockResolvedValueOnce(mockAxiosResponse({
        data: {
          evaluations: [mockPolicyEvaluation],
        },
      }));

      const result = await containerImagesApi.evaluatePolicies('image-001');

      expect(result[0].violations).toHaveLength(1);
      expect(result[0].violations[0].rule).toBe('max_critical_vulnerabilities');
    });

    it('should return empty violations for passing policy', async () => {
      const passingEvaluation = {
        ...mockPolicyEvaluation,
        passed: true,
        violations: [],
      };
      mockApiClient.post.mockResolvedValueOnce(mockAxiosResponse({
        data: {
          evaluations: [passingEvaluation],
        },
      }));

      const result = await containerImagesApi.evaluatePolicies('image-001');

      expect(result[0].passed).toBe(true);
      expect(result[0].violations).toHaveLength(0);
    });

    it('should handle policy evaluation error', async () => {
      const error = new Error('Policy evaluation failed');
      mockApiClient.post.mockRejectedValueOnce(error);

      await expect(containerImagesApi.evaluatePolicies('image-001')).rejects.toThrow(
        'Policy evaluation failed'
      );
    });
  });

  describe('API endpoint consistency', () => {
    it('should use correct base path for all endpoints', async () => {
      mockApiClient.get.mockResolvedValueOnce(mockAxiosResponse({
        data: { images: [], pagination: mockPagination },
      }));
      mockApiClient.post.mockResolvedValueOnce(mockAxiosResponse({
        data: { image: mockContainerImage },
      }));
      mockApiClient.delete.mockResolvedValueOnce(mockAxiosResponse(null));

      await containerImagesApi.list();
      await containerImagesApi.scan('image-001');
      await containerImagesApi.delete('image-001');

      const calls = [
        ...mockApiClient.get.mock.calls,
        ...mockApiClient.post.mock.calls,
        ...mockApiClient.delete.mock.calls,
      ];

      calls.forEach((call) => {
        expect(call[0]).toContain('/supply_chain/container_images');
      });
    });
  });
});

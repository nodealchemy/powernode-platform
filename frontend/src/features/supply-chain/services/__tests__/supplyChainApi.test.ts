import { supplyChainApi } from '../supplyChainApi';
import { apiClient } from '@/shared/services/apiClient';
import { createMockAxiosResponse } from '@/test-utils/mockAxios';

jest.mock('@/shared/services/apiClient', () => ({
  apiClient: {
    get: jest.fn(),
    post: jest.fn(),
    patch: jest.fn(),
    delete: jest.fn(),
  },
}));

const mockApiClient = apiClient as jest.Mocked<typeof apiClient>;

describe('supplyChainApi', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('getDashboard', () => {
    it('returns transformed dashboard data on success', async () => {
      const mockBackendResponse = {
        success: true,
        data: {
          overview: {
            sboms: {
              total: 25,
              with_vulnerabilities: 8,
              ntia_compliant: 15,
            },
            vulnerabilities: {
              total: 42,
              critical: 3,
              high: 9,
              open: 30,
            },
            attestations: {
              total: 50,
              signed: 45,
              verified: 40,
            },
            container_images: {
              total: 120,
              verified: 100,
              quarantined: 5,
            },
            vendors: {
              total: 18,
              active: 15,
              high_risk: 2,
            },
          },
          recent_activity: [
            {
              type: 'sbom_uploaded',
              title: 'SBOM uploaded',
              timestamp: '2024-01-20T10:00:00Z',
              details: { component_count: 25 },
            },
          ],
          alerts: [
            {
              severity: 'high',
              type: 'vulnerability_found',
              message: 'Critical vulnerability found in dependency',
              action_url: '/vulnerabilities/1',
            },
          ],
          quick_stats: {
            sboms_this_month: 8,
            scans_this_month: 12,
            attestations_this_month: 5,
            average_risk_score: 6.5,
          },
        },
      };

      mockApiClient.get.mockResolvedValue(createMockAxiosResponse(mockBackendResponse));

      const result = await supplyChainApi.getDashboard();

      expect(mockApiClient.get).toHaveBeenCalledWith('/supply_chain/dashboard');
      expect(result).toEqual({
        sbom_count: 25,
        sboms_with_vulnerabilities: 8,
        vulnerability_count: 42,
        critical_vulnerabilities: 3,
        high_vulnerabilities: 9,
        open_vulnerabilities: 30,
        container_image_count: 120,
        quarantined_images: 5,
        verified_images: 100,
        attestation_count: 50,
        verified_attestations: 40,
        signed_attestations: 45,
        vendor_count: 18,
        active_vendors: 15,
        high_risk_vendors: 2,
        ntia_compliant_sboms: 15,
        sboms_this_month: 8,
        scans_this_month: 12,
        attestations_this_month: 5,
        average_risk_score: 6.5,
        alerts: mockBackendResponse.data.alerts,
        recent_activity: mockBackendResponse.data.recent_activity,
      });
    });

    it('transforms backend structure to frontend format correctly', async () => {
      const mockBackendResponse = {
        success: true,
        data: {
          overview: {
            sboms: {
              total: 100,
              with_vulnerabilities: 25,
              ntia_compliant: 80,
            },
            vulnerabilities: {
              total: 150,
              critical: 10,
              high: 35,
              open: 95,
            },
            attestations: {
              total: 200,
              signed: 150,
              verified: 120,
            },
            container_images: {
              total: 500,
              verified: 450,
              quarantined: 20,
            },
            vendors: {
              total: 50,
              active: 40,
              high_risk: 5,
            },
          },
          recent_activity: [],
          alerts: [],
          quick_stats: {
            sboms_this_month: 20,
            scans_this_month: 45,
            attestations_this_month: 15,
            average_risk_score: 7.2,
          },
        },
      };

      mockApiClient.get.mockResolvedValue(createMockAxiosResponse(mockBackendResponse));

      const result = await supplyChainApi.getDashboard();

      // Verify transformation of nested sboms object
      expect(result.sbom_count).toBe(mockBackendResponse.data.overview.sboms.total);
      expect(result.sboms_with_vulnerabilities).toBe(
        mockBackendResponse.data.overview.sboms.with_vulnerabilities
      );
      expect(result.ntia_compliant_sboms).toBe(
        mockBackendResponse.data.overview.sboms.ntia_compliant
      );

      // Verify transformation of vulnerabilities object
      expect(result.vulnerability_count).toBe(mockBackendResponse.data.overview.vulnerabilities.total);
      expect(result.critical_vulnerabilities).toBe(
        mockBackendResponse.data.overview.vulnerabilities.critical
      );
      expect(result.high_vulnerabilities).toBe(
        mockBackendResponse.data.overview.vulnerabilities.high
      );
      expect(result.open_vulnerabilities).toBe(
        mockBackendResponse.data.overview.vulnerabilities.open
      );

      // Verify transformation of attestations object
      expect(result.attestation_count).toBe(mockBackendResponse.data.overview.attestations.total);
      expect(result.verified_attestations).toBe(
        mockBackendResponse.data.overview.attestations.verified
      );
      expect(result.signed_attestations).toBe(
        mockBackendResponse.data.overview.attestations.signed
      );

      // Verify transformation of container_images object
      expect(result.container_image_count).toBe(
        mockBackendResponse.data.overview.container_images.total
      );
      expect(result.verified_images).toBe(mockBackendResponse.data.overview.container_images.verified);
      expect(result.quarantined_images).toBe(
        mockBackendResponse.data.overview.container_images.quarantined
      );

      // Verify transformation of vendors object
      expect(result.vendor_count).toBe(mockBackendResponse.data.overview.vendors.total);
      expect(result.active_vendors).toBe(mockBackendResponse.data.overview.vendors.active);
      expect(result.high_risk_vendors).toBe(mockBackendResponse.data.overview.vendors.high_risk);

      // Verify transformation of quick_stats
      expect(result.sboms_this_month).toBe(mockBackendResponse.data.quick_stats.sboms_this_month);
      expect(result.scans_this_month).toBe(mockBackendResponse.data.quick_stats.scans_this_month);
      expect(result.attestations_this_month).toBe(
        mockBackendResponse.data.quick_stats.attestations_this_month
      );
      expect(result.average_risk_score).toBe(mockBackendResponse.data.quick_stats.average_risk_score);
    });

    it('preserves alerts and recent_activity without transformation', async () => {
      const mockAlerts = [
        {
          severity: 'critical',
          type: 'compliance_violation',
          message: 'NTIA compliance violation detected',
          action_url: '/compliance/violations/1',
        },
        {
          severity: 'warning',
          type: 'license_issue',
          message: 'Incompatible license detected',
          action_url: '/licenses/issues/1',
        },
      ];

      const mockActivity = [
        {
          type: 'sbom_analyzed',
          title: 'SBOM Analysis Complete',
          timestamp: '2024-01-20T15:30:00Z',
          details: { vulnerabilities_found: 5, components_analyzed: 150 },
        },
        {
          type: 'attestation_verified',
          title: 'Attestation Verified',
          timestamp: '2024-01-20T14:00:00Z',
          details: { attestation_id: 'att_123', slsa_level: 3 },
        },
      ];

      const mockBackendResponse = {
        success: true,
        data: {
          overview: {
            sboms: { total: 10, with_vulnerabilities: 3, ntia_compliant: 8 },
            vulnerabilities: { total: 20, critical: 1, high: 3, open: 15 },
            attestations: { total: 15, signed: 12, verified: 10 },
            container_images: { total: 50, verified: 45, quarantined: 1 },
            vendors: { total: 8, active: 7, high_risk: 0 },
          },
          recent_activity: mockActivity,
          alerts: mockAlerts,
          quick_stats: {
            sboms_this_month: 3,
            scans_this_month: 5,
            attestations_this_month: 2,
            average_risk_score: 4.2,
          },
        },
      };

      mockApiClient.get.mockResolvedValue(createMockAxiosResponse(mockBackendResponse));

      const result = await supplyChainApi.getDashboard();

      expect(result.alerts).toEqual(mockAlerts);
      expect(result.recent_activity).toEqual(mockActivity);
    });

    it('handles API error', async () => {
      const error = {
        response: { data: { error: 'Failed to fetch dashboard' } },
      };

      mockApiClient.get.mockRejectedValue(error);

      await expect(supplyChainApi.getDashboard()).rejects.toEqual(error);
      expect(mockApiClient.get).toHaveBeenCalledWith('/supply_chain/dashboard');
    });

    it('handles network error', async () => {
      const networkError = new TypeError('Network request failed');
      mockApiClient.get.mockRejectedValue(networkError);

      await expect(supplyChainApi.getDashboard()).rejects.toThrow('Network request failed');
      expect(mockApiClient.get).toHaveBeenCalledWith('/supply_chain/dashboard');
    });

    it('handles empty quick_stats with null average_risk_score', async () => {
      const mockBackendResponse = {
        success: true,
        data: {
          overview: {
            sboms: { total: 0, with_vulnerabilities: 0, ntia_compliant: 0 },
            vulnerabilities: { total: 0, critical: 0, high: 0, open: 0 },
            attestations: { total: 0, signed: 0, verified: 0 },
            container_images: { total: 0, verified: 0, quarantined: 0 },
            vendors: { total: 0, active: 0, high_risk: 0 },
          },
          recent_activity: [],
          alerts: [],
          quick_stats: {
            sboms_this_month: 0,
            scans_this_month: 0,
            attestations_this_month: 0,
            average_risk_score: null,
          },
        },
      };

      mockApiClient.get.mockResolvedValue(createMockAxiosResponse(mockBackendResponse));

      const result = await supplyChainApi.getDashboard();

      expect(result.average_risk_score).toBeNull();
      expect(result.sbom_count).toBe(0);
      expect(result.vulnerability_count).toBe(0);
      expect(result.attestation_count).toBe(0);
    });
  });
});

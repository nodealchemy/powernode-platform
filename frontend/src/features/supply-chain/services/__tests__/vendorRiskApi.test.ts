// frozen_string_literal: true
import { vendorRiskApi } from '../vendorRiskApi';
import { apiClient } from '@/shared/services/apiClient';
import { createMockAxiosResponse } from '@/test-utils/mockAxios';

// Mock the apiClient module
jest.mock('@/shared/services/apiClient', () => ({
  apiClient: {
    get: jest.fn(),
    post: jest.fn(),
    patch: jest.fn(),
    delete: jest.fn(),
  },
}));

const mockApiClient = apiClient as jest.Mocked<typeof apiClient>;

describe('vendorRiskApi', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('listVendors', () => {
    it('returns list of vendors without parameters', async () => {
      const mockVendors = [
        {
          id: 'vendor-1',
          name: 'Vendor One',
          vendor_type: 'saas' as const,
          risk_tier: 'low' as const,
          risk_score: 25,
          status: 'active' as const,
          handles_pii: false,
          handles_phi: false,
          handles_pci: false,
          certifications: ['ISO27001'],
          contact_name: 'John Doe',
          contact_email: 'john@vendor.com',
          website: 'https://vendor.com',
          created_at: '2024-01-01T00:00:00Z',
          updated_at: '2024-01-01T00:00:00Z',
        },
      ];

      const mockPagination = {
        current_page: 1,
        per_page: 20,
        total_pages: 1,
        total_count: 1,
      };

      const mockResponse = {
        success: true,
        data: {
          vendors: mockVendors,
          pagination: mockPagination,
        },
      };

      mockApiClient.get.mockResolvedValue(createMockAxiosResponse(mockResponse));

      const result = await vendorRiskApi.listVendors();

      expect(mockApiClient.get).toHaveBeenCalledWith('/supply_chain/vendors', {
        params: undefined,
      });
      expect(result.vendors).toEqual(mockVendors);
      expect(result.pagination).toEqual(mockPagination);
    });

    it('returns filtered vendors with parameters', async () => {
      const mockVendors = [];
      const mockPagination = {
        current_page: 1,
        per_page: 10,
        total_pages: 0,
        total_count: 0,
      };

      mockApiClient.get.mockResolvedValue(
        createMockAxiosResponse({
          success: true,
          data: {
            vendors: mockVendors,
            pagination: mockPagination,
          },
        })
      );

      const params = {
        page: 2,
        per_page: 10,
        risk_tier: 'critical' as const,
        status: 'active' as const,
        vendor_type: 'api' as const,
        search: 'stripe',
      };

      const result = await vendorRiskApi.listVendors(params);

      expect(mockApiClient.get).toHaveBeenCalledWith('/supply_chain/vendors', {
        params,
      });
      expect(result.vendors).toEqual(mockVendors);
      expect(result.pagination).toEqual(mockPagination);
    });

    it('throws error on API failure', async () => {
      const error = new Error('API Error: Failed to fetch vendors');
      mockApiClient.get.mockRejectedValue(error);

      await expect(vendorRiskApi.listVendors()).rejects.toThrow('API Error: Failed to fetch vendors');
    });

    it('handles network errors', async () => {
      const networkError = new TypeError('Network request failed');
      mockApiClient.get.mockRejectedValue(networkError);

      await expect(vendorRiskApi.listVendors()).rejects.toThrow('Network request failed');
    });
  });

  describe('getVendor', () => {
    it('returns vendor detail with assessments and questionnaires', async () => {
      const mockVendorDetail = {
        id: 'vendor-1',
        name: 'Vendor One',
        vendor_type: 'saas' as const,
        risk_tier: 'high' as const,
        risk_score: 65,
        status: 'active' as const,
        handles_pii: true,
        handles_phi: false,
        handles_pci: false,
        certifications: ['ISO27001', 'SOC2'],
        contact_name: 'John Doe',
        contact_email: 'john@vendor.com',
        website: 'https://vendor.com',
        created_at: '2024-01-01T00:00:00Z',
        updated_at: '2024-01-15T00:00:00Z',
        assessments: [
          {
            id: 'assessment-1',
            vendor_id: 'vendor-1',
            assessment_type: 'initial' as const,
            status: 'completed' as const,
            security_score: 75,
            compliance_score: 80,
            operational_score: 70,
            overall_score: 75,
            finding_count: 3,
            completed_at: '2024-01-10T00:00:00Z',
            created_at: '2024-01-05T00:00:00Z',
          },
        ],
        questionnaires: [
          {
            id: 'questionnaire-1',
            vendor_id: 'vendor-1',
            template_name: 'Security Baseline',
            status: 'completed' as const,
            completed_at: '2024-01-12T00:00:00Z',
            response_count: 45,
            total_questions: 50,
            created_at: '2024-01-08T00:00:00Z',
          },
        ],
        monitoring_events: [
          {
            id: 'event-1',
            event_type: 'login_anomaly',
            severity: 'medium',
            message: 'Unusual login detected',
            created_at: '2024-01-15T10:30:00Z',
          },
        ],
      };

      const mockResponse = {
        success: true,
        data: {
          vendor: mockVendorDetail,
        },
      };

      mockApiClient.get.mockResolvedValue(createMockAxiosResponse(mockResponse));

      const result = await vendorRiskApi.getVendor('vendor-1');

      expect(mockApiClient.get).toHaveBeenCalledWith('/supply_chain/vendors/vendor-1');
      expect(result).toEqual(mockVendorDetail);
      expect(result.assessments).toHaveLength(1);
      expect(result.questionnaires).toHaveLength(1);
      expect(result.monitoring_events).toHaveLength(1);
    });

    it('returns vendor without optional fields', async () => {
      const mockVendorDetail = {
        id: 'vendor-2',
        name: 'Vendor Two',
        vendor_type: 'library' as const,
        risk_tier: 'low' as const,
        risk_score: 15,
        status: 'active' as const,
        handles_pii: false,
        handles_phi: false,
        handles_pci: false,
        certifications: [],
        created_at: '2024-01-01T00:00:00Z',
        updated_at: '2024-01-01T00:00:00Z',
      };

      mockApiClient.get.mockResolvedValue(
        createMockAxiosResponse({
          success: true,
          data: {
            vendor: mockVendorDetail,
          },
        })
      );

      const result = await vendorRiskApi.getVendor('vendor-2');

      expect(result).toEqual(mockVendorDetail);
      expect(result.contact_name).toBeUndefined();
      expect(result.assessments).toBeUndefined();
    });

    it('throws error when vendor not found', async () => {
      const error = new Error('Vendor not found');
      mockApiClient.get.mockRejectedValue(error);

      await expect(vendorRiskApi.getVendor('non-existent')).rejects.toThrow('Vendor not found');
    });
  });

  describe('createVendor', () => {
    it('creates vendor with all fields', async () => {
      const vendorData = {
        name: 'New Vendor',
        vendor_type: 'api' as const,
        contact_name: 'Jane Smith',
        contact_email: 'jane@newvendor.com',
        website: 'https://newvendor.com',
        handles_pii: true,
        handles_phi: true,
        handles_pci: false,
        certifications: ['ISO27001', 'HIPAA'],
      };

      const createdVendor = {
        id: 'vendor-new',
        name: vendorData.name,
        vendor_type: vendorData.vendor_type,
        risk_tier: 'medium' as const,
        risk_score: 50,
        status: 'pending' as const,
        handles_pii: vendorData.handles_pii,
        handles_phi: vendorData.handles_phi,
        handles_pci: vendorData.handles_pci,
        certifications: vendorData.certifications,
        contact_name: vendorData.contact_name,
        contact_email: vendorData.contact_email,
        website: vendorData.website,
        created_at: '2024-01-20T00:00:00Z',
        updated_at: '2024-01-20T00:00:00Z',
      };

      mockApiClient.post.mockResolvedValue(
        createMockAxiosResponse({
          success: true,
          data: {
            vendor: createdVendor,
          },
        })
      );

      const result = await vendorRiskApi.createVendor(vendorData);

      expect(mockApiClient.post).toHaveBeenCalledWith('/supply_chain/vendors', {
        vendor: vendorData,
      });
      expect(result).toEqual(createdVendor);
      expect(result.id).toBe('vendor-new');
      expect(result.status).toBe('pending');
    });

    it('creates vendor with minimal fields', async () => {
      const vendorData = {
        name: 'Minimal Vendor',
        vendor_type: 'library' as const,
      };

      const createdVendor = {
        id: 'vendor-minimal',
        name: vendorData.name,
        vendor_type: vendorData.vendor_type,
        risk_tier: 'low' as const,
        risk_score: 10,
        status: 'active' as const,
        handles_pii: false,
        handles_phi: false,
        handles_pci: false,
        certifications: [],
        created_at: '2024-01-20T00:00:00Z',
        updated_at: '2024-01-20T00:00:00Z',
      };

      mockApiClient.post.mockResolvedValue(
        createMockAxiosResponse({
          success: true,
          data: {
            vendor: createdVendor,
          },
        })
      );

      const result = await vendorRiskApi.createVendor(vendorData);

      expect(mockApiClient.post).toHaveBeenCalledWith('/supply_chain/vendors', {
        vendor: vendorData,
      });
      expect(result).toEqual(createdVendor);
    });

    it('throws error on validation failure', async () => {
      const vendorData = {
        name: 'Invalid Vendor',
        vendor_type: 'saas' as const,
      };

      const error = new Error('Validation failed: email format invalid');
      mockApiClient.post.mockRejectedValue(error);

      await expect(vendorRiskApi.createVendor(vendorData)).rejects.toThrow(
        'Validation failed: email format invalid'
      );
    });

    it('throws error on duplicate vendor name', async () => {
      const vendorData = {
        name: 'Existing Vendor',
        vendor_type: 'saas' as const,
      };

      const error = new Error('Vendor with this name already exists');
      mockApiClient.post.mockRejectedValue(error);

      await expect(vendorRiskApi.createVendor(vendorData)).rejects.toThrow(
        'Vendor with this name already exists'
      );
    });
  });

  describe('updateVendor', () => {
    it('updates vendor with partial fields', async () => {
      const updateData = {
        risk_score: 45,
        status: 'inactive' as const,
      };

      const updatedVendor = {
        id: 'vendor-1',
        name: 'Vendor One',
        vendor_type: 'saas' as const,
        risk_tier: 'medium' as const,
        risk_score: 45,
        status: 'inactive' as const,
        handles_pii: false,
        handles_phi: false,
        handles_pci: false,
        certifications: ['ISO27001'],
        created_at: '2024-01-01T00:00:00Z',
        updated_at: '2024-01-20T00:00:00Z',
      };

      mockApiClient.patch.mockResolvedValue(
        createMockAxiosResponse({
          success: true,
          data: {
            vendor: updatedVendor,
          },
        })
      );

      const result = await vendorRiskApi.updateVendor('vendor-1', updateData);

      expect(mockApiClient.patch).toHaveBeenCalledWith('/supply_chain/vendors/vendor-1', {
        vendor: updateData,
      });
      expect(result).toEqual(updatedVendor);
      expect(result.status).toBe('inactive');
    });

    it('updates vendor certifications', async () => {
      const updateData = {
        certifications: ['ISO27001', 'SOC2', 'PCI-DSS'],
      };

      const updatedVendor = {
        id: 'vendor-2',
        name: 'Vendor Two',
        vendor_type: 'api' as const,
        risk_tier: 'low' as const,
        risk_score: 20,
        status: 'active' as const,
        handles_pii: true,
        handles_phi: false,
        handles_pci: true,
        certifications: updateData.certifications,
        created_at: '2024-01-01T00:00:00Z',
        updated_at: '2024-01-20T00:00:00Z',
      };

      mockApiClient.patch.mockResolvedValue(
        createMockAxiosResponse({
          success: true,
          data: {
            vendor: updatedVendor,
          },
        })
      );

      const result = await vendorRiskApi.updateVendor('vendor-2', updateData);

      expect(result.certifications).toEqual(updateData.certifications);
    });

    it('throws error when vendor not found', async () => {
      const error = new Error('Vendor not found');
      mockApiClient.patch.mockRejectedValue(error);

      await expect(
        vendorRiskApi.updateVendor('non-existent', { risk_score: 50 })
      ).rejects.toThrow('Vendor not found');
    });

    it('throws error on invalid update data', async () => {
      const error = new Error('Invalid risk score value');
      mockApiClient.patch.mockRejectedValue(error);

      await expect(
        vendorRiskApi.updateVendor('vendor-1', { risk_score: 999 })
      ).rejects.toThrow('Invalid risk score value');
    });
  });

  describe('deleteVendor', () => {
    it('deletes vendor successfully', async () => {
      mockApiClient.delete.mockResolvedValue(createMockAxiosResponse({ success: true }));

      await expect(vendorRiskApi.deleteVendor('vendor-1')).resolves.toBeUndefined();

      expect(mockApiClient.delete).toHaveBeenCalledWith('/supply_chain/vendors/vendor-1');
    });

    it('throws error when vendor not found', async () => {
      const error = new Error('Vendor not found');
      mockApiClient.delete.mockRejectedValue(error);

      await expect(vendorRiskApi.deleteVendor('non-existent')).rejects.toThrow('Vendor not found');
    });

    it('throws error when vendor has active assessments', async () => {
      const error = new Error('Cannot delete vendor with active assessments');
      mockApiClient.delete.mockRejectedValue(error);

      await expect(vendorRiskApi.deleteVendor('vendor-1')).rejects.toThrow(
        'Cannot delete vendor with active assessments'
      );
    });
  });

  describe('startAssessment', () => {
    it('starts initial assessment successfully', async () => {
      const createdAssessment = {
        id: 'assessment-1',
        vendor_id: 'vendor-1',
        assessment_type: 'initial' as const,
        status: 'draft' as const,
        security_score: 0,
        compliance_score: 0,
        operational_score: 0,
        overall_score: 0,
        finding_count: 0,
        created_at: '2024-01-20T00:00:00Z',
      };

      mockApiClient.post.mockResolvedValue(
        createMockAxiosResponse({
          success: true,
          data: {
            assessment: createdAssessment,
          },
        })
      );

      const result = await vendorRiskApi.startAssessment('vendor-1', 'initial');

      expect(mockApiClient.post).toHaveBeenCalledWith('/supply_chain/vendors/vendor-1/assessments', {
        assessment_type: 'initial',
      });
      expect(result).toEqual(createdAssessment);
      expect(result.status).toBe('draft');
    });

    it('starts periodic assessment', async () => {
      const createdAssessment = {
        id: 'assessment-2',
        vendor_id: 'vendor-2',
        assessment_type: 'periodic' as const,
        status: 'draft' as const,
        security_score: 0,
        compliance_score: 0,
        operational_score: 0,
        overall_score: 0,
        finding_count: 0,
        created_at: '2024-01-20T00:00:00Z',
      };

      mockApiClient.post.mockResolvedValue(
        createMockAxiosResponse({
          success: true,
          data: {
            assessment: createdAssessment,
          },
        })
      );

      const result = await vendorRiskApi.startAssessment('vendor-2', 'periodic');

      expect(result.assessment_type).toBe('periodic');
    });

    it('starts incident assessment', async () => {
      const createdAssessment = {
        id: 'assessment-3',
        vendor_id: 'vendor-3',
        assessment_type: 'incident' as const,
        status: 'draft' as const,
        security_score: 0,
        compliance_score: 0,
        operational_score: 0,
        overall_score: 0,
        finding_count: 0,
        created_at: '2024-01-20T00:00:00Z',
      };

      mockApiClient.post.mockResolvedValue(
        createMockAxiosResponse({
          success: true,
          data: {
            assessment: createdAssessment,
          },
        })
      );

      const result = await vendorRiskApi.startAssessment('vendor-3', 'incident');

      expect(result.assessment_type).toBe('incident');
    });

    it('throws error when vendor not found', async () => {
      const error = new Error('Vendor not found');
      mockApiClient.post.mockRejectedValue(error);

      await expect(vendorRiskApi.startAssessment('non-existent', 'initial')).rejects.toThrow(
        'Vendor not found'
      );
    });

    it('throws error when assessment already in progress', async () => {
      const error = new Error('Assessment already in progress for this vendor');
      mockApiClient.post.mockRejectedValue(error);

      await expect(vendorRiskApi.startAssessment('vendor-1', 'initial')).rejects.toThrow(
        'Assessment already in progress for this vendor'
      );
    });
  });

  describe('sendQuestionnaire', () => {
    it('sends questionnaire successfully', async () => {
      const createdQuestionnaire = {
        id: 'questionnaire-1',
        vendor_id: 'vendor-1',
        template_name: 'Security Baseline',
        status: 'sent' as const,
        sent_at: '2024-01-20T10:00:00Z',
        response_count: 0,
        total_questions: 50,
        created_at: '2024-01-20T00:00:00Z',
      };

      mockApiClient.post.mockResolvedValue(
        createMockAxiosResponse({
          success: true,
          data: {
            questionnaire: createdQuestionnaire,
          },
        })
      );

      const result = await vendorRiskApi.sendQuestionnaire('vendor-1', 'template-security-baseline');

      expect(mockApiClient.post).toHaveBeenCalledWith(
        '/supply_chain/vendors/vendor-1/questionnaires',
        {
          template_id: 'template-security-baseline',
        }
      );
      expect(result).toEqual(createdQuestionnaire);
      expect(result.status).toBe('sent');
    });

    it('sends compliance questionnaire', async () => {
      const createdQuestionnaire = {
        id: 'questionnaire-2',
        vendor_id: 'vendor-2',
        template_name: 'Compliance Assessment',
        status: 'sent' as const,
        sent_at: '2024-01-20T10:00:00Z',
        response_count: 0,
        total_questions: 75,
        created_at: '2024-01-20T00:00:00Z',
      };

      mockApiClient.post.mockResolvedValue(
        createMockAxiosResponse({
          success: true,
          data: {
            questionnaire: createdQuestionnaire,
          },
        })
      );

      const result = await vendorRiskApi.sendQuestionnaire('vendor-2', 'template-compliance');

      expect(result.template_name).toBe('Compliance Assessment');
      expect(result.total_questions).toBe(75);
    });

    it('throws error when vendor not found', async () => {
      const error = new Error('Vendor not found');
      mockApiClient.post.mockRejectedValue(error);

      await expect(
        vendorRiskApi.sendQuestionnaire('non-existent', 'template-id')
      ).rejects.toThrow('Vendor not found');
    });

    it('throws error when template not found', async () => {
      const error = new Error('Questionnaire template not found');
      mockApiClient.post.mockRejectedValue(error);

      await expect(vendorRiskApi.sendQuestionnaire('vendor-1', 'invalid-template')).rejects.toThrow(
        'Questionnaire template not found'
      );
    });

    it('throws error when questionnaire already sent', async () => {
      const error = new Error('Questionnaire has already been sent to this vendor');
      mockApiClient.post.mockRejectedValue(error);

      await expect(vendorRiskApi.sendQuestionnaire('vendor-1', 'template-id')).rejects.toThrow(
        'Questionnaire has already been sent to this vendor'
      );
    });
  });

  describe('getRiskDashboard', () => {
    it('returns complete risk dashboard', async () => {
      const mockDashboard = {
        total_vendors: 15,
        critical_vendors: 2,
        high_risk_vendors: 4,
        vendors_needing_assessment: 3,
        upcoming_assessments: [
          {
            vendor_id: 'vendor-1',
            vendor_name: 'Vendor One',
            due_date: '2024-02-01',
          },
          {
            vendor_id: 'vendor-2',
            vendor_name: 'Vendor Two',
            due_date: '2024-02-15',
          },
        ],
        risk_distribution: {
          critical: 2,
          high: 4,
          medium: 5,
          low: 4,
        },
      };

      mockApiClient.get.mockResolvedValue(
        createMockAxiosResponse({
          success: true,
          data: {
            dashboard: mockDashboard,
          },
        })
      );

      const result = await vendorRiskApi.getRiskDashboard();

      expect(mockApiClient.get).toHaveBeenCalledWith('/supply_chain/vendors/risk_dashboard');
      expect(result).toEqual(mockDashboard);
      expect(result.total_vendors).toBe(15);
      expect(result.critical_vendors).toBe(2);
    });

    it('returns dashboard with no assessments due', async () => {
      const mockDashboard = {
        total_vendors: 5,
        critical_vendors: 0,
        high_risk_vendors: 1,
        vendors_needing_assessment: 0,
        upcoming_assessments: [],
        risk_distribution: {
          critical: 0,
          high: 1,
          medium: 2,
          low: 2,
        },
      };

      mockApiClient.get.mockResolvedValue(
        createMockAxiosResponse({
          success: true,
          data: {
            dashboard: mockDashboard,
          },
        })
      );

      const result = await vendorRiskApi.getRiskDashboard();

      expect(result.upcoming_assessments).toHaveLength(0);
      expect(result.critical_vendors).toBe(0);
    });

    it('returns dashboard with all critical vendors', async () => {
      const mockDashboard = {
        total_vendors: 3,
        critical_vendors: 3,
        high_risk_vendors: 0,
        vendors_needing_assessment: 2,
        upcoming_assessments: [
          {
            vendor_id: 'vendor-1',
            vendor_name: 'Critical Vendor 1',
            due_date: '2024-01-25',
          },
          {
            vendor_id: 'vendor-2',
            vendor_name: 'Critical Vendor 2',
            due_date: '2024-01-28',
          },
        ],
        risk_distribution: {
          critical: 3,
          high: 0,
          medium: 0,
          low: 0,
        },
      };

      mockApiClient.get.mockResolvedValue(
        createMockAxiosResponse({
          success: true,
          data: {
            dashboard: mockDashboard,
          },
        })
      );

      const result = await vendorRiskApi.getRiskDashboard();

      expect(result.critical_vendors).toBe(3);
      expect(result.total_vendors).toBe(3);
      expect(result.risk_distribution.critical).toBe(3);
    });

    it('throws error on API failure', async () => {
      const error = new Error('API Error: Failed to fetch dashboard');
      mockApiClient.get.mockRejectedValue(error);

      await expect(vendorRiskApi.getRiskDashboard()).rejects.toThrow(
        'API Error: Failed to fetch dashboard'
      );
    });

    it('handles network errors', async () => {
      const networkError = new TypeError('Network request failed');
      mockApiClient.get.mockRejectedValue(networkError);

      await expect(vendorRiskApi.getRiskDashboard()).rejects.toThrow('Network request failed');
    });
  });

  describe('Error handling edge cases', () => {
    it('handles 401 unauthorized errors', async () => {
      const error = new Error('Unauthorized');
      mockApiClient.get.mockRejectedValue(error);

      await expect(vendorRiskApi.listVendors()).rejects.toThrow('Unauthorized');
    });

    it('handles 403 forbidden errors', async () => {
      const error = new Error('Forbidden');
      mockApiClient.get.mockRejectedValue(error);

      await expect(vendorRiskApi.getVendor('vendor-1')).rejects.toThrow('Forbidden');
    });

    it('handles 500 server errors', async () => {
      const error = new Error('Internal Server Error');
      mockApiClient.get.mockRejectedValue(error);

      await expect(vendorRiskApi.getRiskDashboard()).rejects.toThrow('Internal Server Error');
    });

    it('handles timeout errors', async () => {
      const error = new Error('Request timeout');
      mockApiClient.post.mockRejectedValue(error);

      await expect(vendorRiskApi.startAssessment('vendor-1', 'initial')).rejects.toThrow(
        'Request timeout'
      );
    });
  });
});

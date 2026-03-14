import { apiClient } from '@/shared/services/apiClient';

interface ApiResponse<T> {
  success: boolean;
  data: T;
}

interface Pagination {
  current_page: number;
  per_page: number;
  total_pages: number;
  total_count: number;
}

type VendorType = 'saas' | 'api' | 'library' | 'infrastructure' | 'hardware' | 'consulting';
type RiskTier = 'critical' | 'high' | 'medium' | 'low';
type VendorStatus = 'active' | 'inactive' | 'pending' | 'suspended';

interface Vendor {
  id: string;
  name: string;
  vendor_type: VendorType;
  risk_tier: RiskTier;
  risk_score: number;
  status: VendorStatus;
  handles_pii: boolean;
  handles_phi: boolean;
  handles_pci: boolean;
  certifications: string[];
  contact_name?: string;
  contact_email?: string;
  website?: string;
  last_assessment_at?: string;
  next_assessment_due?: string;
  created_at: string;
  updated_at: string;
}

interface RiskAssessment {
  id: string;
  vendor_id: string;
  assessment_type: 'initial' | 'periodic' | 'incident' | 'renewal';
  status: 'draft' | 'in_progress' | 'pending_review' | 'completed' | 'expired';
  security_score: number;
  compliance_score: number;
  operational_score: number;
  overall_score: number;
  finding_count: number;
  valid_until?: string;
  completed_at?: string;
  created_at: string;
}

interface Questionnaire {
  id: string;
  vendor_id: string;
  template_name: string;
  status: 'draft' | 'sent' | 'in_progress' | 'completed' | 'expired';
  sent_at?: string;
  completed_at?: string;
  response_count: number;
  total_questions: number;
  created_at: string;
}

interface VendorDetail extends Vendor {
  assessments?: RiskAssessment[];
  questionnaires?: Questionnaire[];
  monitoring_events?: Array<{
    id: string;
    event_type: string;
    severity: string;
    message: string;
    created_at: string;
  }>;
}

export const vendorRiskApi = {
  listVendors: async (params?: {
    page?: number;
    per_page?: number;
    risk_tier?: RiskTier;
    status?: VendorStatus;
    vendor_type?: VendorType;
    search?: string;
  }): Promise<{ vendors: Vendor[]; pagination: Pagination }> => {
    const response = await apiClient.get<ApiResponse<{
      vendors: Vendor[];
      pagination: Pagination;
    }>>('/supply_chain/vendors', { params });
    return response.data.data;
  },

  getVendor: async (id: string): Promise<VendorDetail> => {
    const response = await apiClient.get<ApiResponse<{
      vendor: VendorDetail;
    }>>(`/supply_chain/vendors/${id}`);
    return response.data.data.vendor;
  },

  createVendor: async (data: {
    name: string;
    vendor_type: VendorType;
    contact_name?: string;
    contact_email?: string;
    website?: string;
    handles_pii?: boolean;
    handles_phi?: boolean;
    handles_pci?: boolean;
    certifications?: string[];
  }): Promise<Vendor> => {
    const response = await apiClient.post<ApiResponse<{
      vendor: Vendor;
    }>>('/supply_chain/vendors', { vendor: data });
    return response.data.data.vendor;
  },

  updateVendor: async (id: string, data: Partial<Vendor>): Promise<Vendor> => {
    const response = await apiClient.patch<ApiResponse<{
      vendor: Vendor;
    }>>(`/supply_chain/vendors/${id}`, { vendor: data });
    return response.data.data.vendor;
  },

  deleteVendor: async (id: string): Promise<void> => {
    await apiClient.delete(`/supply_chain/vendors/${id}`);
  },

  startAssessment: async (vendorId: string, assessmentType: string): Promise<RiskAssessment> => {
    const response = await apiClient.post<ApiResponse<{
      assessment: RiskAssessment;
    }>>(`/supply_chain/vendors/${vendorId}/assessments`, { assessment_type: assessmentType });
    return response.data.data.assessment;
  },

  sendQuestionnaire: async (vendorId: string, templateId: string): Promise<Questionnaire> => {
    const response = await apiClient.post<ApiResponse<{
      questionnaire: Questionnaire;
    }>>(`/supply_chain/vendors/${vendorId}/questionnaires`, { template_id: templateId });
    return response.data.data.questionnaire;
  },

  getRiskDashboard: async (): Promise<{
    total_vendors: number;
    critical_vendors: number;
    high_risk_vendors: number;
    vendors_needing_assessment: number;
    upcoming_assessments: Array<{ vendor_id: string; vendor_name: string; due_date: string }>;
    risk_distribution: Record<RiskTier, number>;
  }> => {
    const response = await apiClient.get<ApiResponse<{
      dashboard: {
        total_vendors: number;
        critical_vendors: number;
        high_risk_vendors: number;
        vendors_needing_assessment: number;
        upcoming_assessments: Array<{ vendor_id: string; vendor_name: string; due_date: string }>;
        risk_distribution: Record<RiskTier, number>;
      };
    }>>('/supply_chain/vendors/risk_dashboard');
    return response.data.data.dashboard;
  },
};

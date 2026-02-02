import { useState, useEffect, useCallback } from 'react';
import { vendorRiskApi } from '../services/vendorRiskApi';

type RiskTier = 'critical' | 'high' | 'medium' | 'low';
type VendorStatus = 'active' | 'inactive' | 'pending' | 'suspended';
type VendorType = 'saas' | 'api' | 'library' | 'infrastructure' | 'hardware' | 'consulting';

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

interface MonitoringEvent {
  id: string;
  event_type: string;
  severity: string;
  message: string;
  created_at: string;
}

interface VendorDetail extends Vendor {
  contact_name?: string;
  contact_email?: string;
  website?: string;
  assessments?: RiskAssessment[];
  questionnaires?: Questionnaire[];
  monitoring_events?: MonitoringEvent[];
}

interface Pagination {
  current_page: number;
  per_page: number;
  total_pages: number;
  total_count: number;
}

export function useVendors(options: {
  page?: number;
  perPage?: number;
  riskTier?: RiskTier;
  status?: VendorStatus;
  search?: string;
} = {}) {
  const [vendors, setVendors] = useState<Vendor[]>([]);
  const [pagination, setPagination] = useState<Pagination | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchVendors = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const result = await vendorRiskApi.listVendors({
        page: options.page,
        per_page: options.perPage,
        risk_tier: options.riskTier,
        status: options.status,
        search: options.search,
      });
      setVendors(result.vendors);
      setPagination(result.pagination);
    } catch {
      setError(err instanceof Error ? err.message : 'Failed to fetch vendors');
    } finally {
      setLoading(false);
    }
  }, [options.page, options.perPage, options.riskTier, options.status, options.search]);

  useEffect(() => {
    fetchVendors();
  }, [fetchVendors]);

  return { vendors, pagination, loading, error, refresh: fetchVendors };
}

export function useVendor(id: string | null) {
  const [vendor, setVendor] = useState<VendorDetail | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fetchVendor = useCallback(async () => {
    if (!id) return;
    try {
      setLoading(true);
      setError(null);
      const result = await vendorRiskApi.getVendor(id);
      setVendor(result);
    } catch {
      setError(err instanceof Error ? err.message : 'Failed to fetch vendor');
    } finally {
      setLoading(false);
    }
  }, [id]);

  useEffect(() => {
    fetchVendor();
  }, [fetchVendor]);

  return { vendor, loading, error, refresh: fetchVendor };
}

export function useVendorRiskDashboard() {
  const [data, setData] = useState<{
    total_vendors: number;
    critical_vendors: number;
    high_risk_vendors: number;
    vendors_needing_assessment: number;
    upcoming_assessments: Array<{ vendor_id: string; vendor_name: string; due_date: string }>;
    risk_distribution: Record<RiskTier, number>;
  } | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchDashboard = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const result = await vendorRiskApi.getRiskDashboard();
      setData(result);
    } catch {
      setError(err instanceof Error ? err.message : 'Failed to fetch dashboard');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchDashboard();
  }, [fetchDashboard]);

  return { data, loading, error, refresh: fetchDashboard };
}

// Vendor mutation hooks
export function useCreateVendor() {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const mutateAsync = useCallback(async (data: {
    name: string;
    vendor_type: VendorType;
    contact_name?: string;
    contact_email?: string;
    website?: string;
    handles_pii?: boolean;
    handles_phi?: boolean;
    handles_pci?: boolean;
    certifications?: string[];
  }) => {
    try {
      setLoading(true);
      setError(null);
      const result = await vendorRiskApi.createVendor(data);
      return result;
    } catch {
      const errorMsg = err instanceof Error ? err.message : 'Failed to create vendor';
      setError(errorMsg);
      throw err;
    } finally {
      setLoading(false);
    }
  }, []);

  return { mutateAsync, isLoading: loading, error };
}

export function useUpdateVendor() {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const mutateAsync = useCallback(async ({ id, data }: { id: string; data: Partial<Vendor> }) => {
    try {
      setLoading(true);
      setError(null);
      const result = await vendorRiskApi.updateVendor(id, data);
      return result;
    } catch {
      const errorMsg = err instanceof Error ? err.message : 'Failed to update vendor';
      setError(errorMsg);
      throw err;
    } finally {
      setLoading(false);
    }
  }, []);

  return { mutateAsync, isLoading: loading, error };
}

export function useDeleteVendor() {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const mutateAsync = useCallback(async (id: string) => {
    try {
      setLoading(true);
      setError(null);
      await vendorRiskApi.deleteVendor(id);
    } catch {
      const errorMsg = err instanceof Error ? err.message : 'Failed to delete vendor';
      setError(errorMsg);
      throw err;
    } finally {
      setLoading(false);
    }
  }, []);

  return { mutateAsync, isLoading: loading, error };
}

export function useStartAssessment() {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const mutateAsync = useCallback(async ({
    vendorId,
    assessmentType,
  }: {
    vendorId: string;
    assessmentType: string;
  }) => {
    try {
      setLoading(true);
      setError(null);
      const result = await vendorRiskApi.startAssessment(vendorId, assessmentType);
      return result;
    } catch {
      const errorMsg = err instanceof Error ? err.message : 'Failed to start assessment';
      setError(errorMsg);
      throw err;
    } finally {
      setLoading(false);
    }
  }, []);

  return { mutateAsync, isLoading: loading, error };
}

export function useSendQuestionnaire() {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const mutateAsync = useCallback(async ({
    vendorId,
    templateId,
  }: {
    vendorId: string;
    templateId: string;
  }) => {
    try {
      setLoading(true);
      setError(null);
      const result = await vendorRiskApi.sendQuestionnaire(vendorId, templateId);
      return result;
    } catch {
      const errorMsg = err instanceof Error ? err.message : 'Failed to send questionnaire';
      setError(errorMsg);
      throw err;
    } finally {
      setLoading(false);
    }
  }, []);

  return { mutateAsync, isLoading: loading, error };
}

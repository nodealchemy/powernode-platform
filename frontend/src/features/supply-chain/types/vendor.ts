/**
 * Vendor Risk Management Types
 *
 * Types for third-party vendor risk assessment and monitoring
 */

/** Type of vendor service */
export type VendorType = 'saas' | 'api' | 'library' | 'infrastructure' | 'hardware' | 'consulting';

/** Vendor risk tier classification */
export type RiskTier = 'critical' | 'high' | 'medium' | 'low';

/** Vendor operational status */
export type VendorStatus = 'active' | 'inactive' | 'pending' | 'suspended';

/** Type of risk assessment */
export type AssessmentType = 'initial' | 'periodic' | 'incident' | 'renewal';

/** Risk assessment status */
export type AssessmentStatus = 'draft' | 'in_progress' | 'pending_review' | 'completed' | 'expired';

/**
 * Vendor
 * Third-party vendor information and risk profile
 */
export interface Vendor {
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

/**
 * Risk Assessment
 * Vendor security and compliance assessment
 */
export interface RiskAssessment {
  id: string;
  vendor_id: string;
  assessment_type: AssessmentType;
  status: AssessmentStatus;
  security_score: number;
  compliance_score: number;
  operational_score: number;
  overall_score: number;
  finding_count: number;
  valid_until?: string;
  completed_at?: string;
  created_at: string;
}

/**
 * Questionnaire
 * Security questionnaire sent to vendors
 */
export interface Questionnaire {
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

/**
 * Vendor Detail
 * Extended vendor information with assessments and monitoring
 */
export interface VendorDetail extends Vendor {
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

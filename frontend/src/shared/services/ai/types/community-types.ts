/**
 * Community Agents Types
 *
 * Types for the community agent registry, discovery, ratings, and federation
 */

// Visibility and status types
export type AgentVisibility = 'public' | 'unlisted' | 'private';

export type AgentStatus = 'active' | 'pending' | 'suspended' | 'deprecated';

export type PricingModel = 'free' | 'per_task' | 'subscription' | 'negotiated';

export type ReportReason = 'spam' | 'malicious' | 'inappropriate' | 'broken' | 'copyright' | 'other';

export type ReportStatus = 'pending' | 'investigating' | 'resolved' | 'dismissed';

// Community Agent types
export interface CommunityAgent {
  id: string;
  name: string;
  description: string;
  endpoint_url: string;
  category?: string;
  skills: string[];
  visibility: AgentVisibility;
  status: AgentStatus;
  verified: boolean;
  reputation_score: number;
  task_count: number;
  success_rate?: number;
  avg_rating?: number;
  rating_count: number;
  owner_account_id: string;
  owner_account_name?: string;
  agent_card: Record<string, unknown>;
  documentation_url?: string;
  source_code_url?: string;
  pricing_model: PricingModel;
  price_per_task?: number;
  configuration: Record<string, unknown>;
  federation_key?: string;
  created_at: string;
  updated_at: string;
}

export interface CommunityAgentSummary {
  id: string;
  name: string;
  description: string;
  category?: string;
  skills: string[];
  verified: boolean;
  reputation_score: number;
  avg_rating?: number;
  rating_count: number;
  task_count: number;
  pricing_model: PricingModel;
  price_per_task?: number;
}

export interface CreateCommunityAgentRequest {
  name: string;
  description: string;
  endpoint_url: string;
  category?: string;
  skills?: string[];
  visibility?: AgentVisibility;
  documentation_url?: string;
  source_code_url?: string;
  pricing_model?: PricingModel;
  price_per_task?: number;
  agent_card?: Record<string, unknown>;
  configuration?: Record<string, unknown>;
}

export interface UpdateCommunityAgentRequest {
  name?: string;
  description?: string;
  endpoint_url?: string;
  category?: string;
  skills?: string[];
  visibility?: AgentVisibility;
  documentation_url?: string;
  source_code_url?: string;
  pricing_model?: PricingModel;
  price_per_task?: number;
  agent_card?: Record<string, unknown>;
  configuration?: Record<string, unknown>;
}

export interface CommunityAgentFilters {
  category?: string;
  skill?: string;
  verified?: boolean;
  query?: string;
  sort?: 'popular' | 'rating' | 'recent' | 'reputation';
  page?: number;
  per_page?: number;
  [key: string]: string | number | boolean | undefined;
}

// Rating types
export interface CommunityAgentRating {
  id: string;
  community_agent_id: string;
  user_id: string;
  user_name?: string;
  score: number;
  review?: string;
  task_id?: string;
  helpful_count: number;
  created_at: string;
  updated_at: string;
}

export interface CreateRatingRequest {
  score: number;
  review?: string;
  task_id?: string;
}

// Report types
export interface CommunityAgentReport {
  id: string;
  community_agent_id: string;
  reporter_id: string;
  reason: ReportReason;
  description: string;
  evidence?: string;
  status: ReportStatus;
  resolution?: string;
  created_at: string;
  updated_at: string;
}

export interface CreateReportRequest {
  reason: ReportReason;
  description: string;
  evidence?: string;
}

// Discovery types
export interface DiscoverAgentsRequest {
  task_description: string;
  category?: string;
  min_rating?: number;
  limit?: number;
}

export interface DiscoverAgentsResponse {
  agents: CommunityAgentSummary[];
  query_analyzed?: {
    skills_detected: string[];
    category_suggested?: string;
  };
}

// Federation Partner types
export type FederationStatus = 'pending' | 'pending_verification' | 'active' | 'suspended' | 'revoked';

export type TrustLevel = 'untrusted' | 'basic' | 'verified' | 'trusted' | 'partner';

export interface FederationPartner {
  id: string;
  organization_name: string;
  organization_id?: string;
  endpoint_url: string;
  contact_email?: string;
  federation_key: string;
  mtls_certificate?: string;
  status: FederationStatus;
  trust_level: TrustLevel;
  verified_at?: string;
  last_sync_at?: string;
  agent_count: number;
  allowed_skills: string[];
  configuration: Record<string, unknown>;
  created_at: string;
  updated_at: string;
}

export interface FederationPartnerSummary {
  id: string;
  name: string;
  organization_name: string;
  endpoint_url: string;
  status: FederationStatus;
  trust_level: TrustLevel;
  agent_count: number;
  shared_agent_count: number;
  task_count: number;
  last_sync_at?: string;
}

export interface CreateFederationPartnerRequest {
  organization_name: string;
  organization_id?: string;
  endpoint_url: string;
  contact_email?: string;
  federation_key?: string;
  mtls_certificate?: string;
  trust_level?: TrustLevel;
  allowed_skills?: string[];
  configuration?: Record<string, unknown>;
}

export interface UpdateFederationPartnerRequest {
  organization_name?: string;
  contact_email?: string;
  trust_level?: TrustLevel;
  allowed_skills?: string[];
  configuration?: Record<string, unknown>;
}

export interface FederationPartnerFilters {
  status?: FederationStatus;
  trust_level?: TrustLevel;
  active?: boolean;
  page?: number;
  per_page?: number;
  [key: string]: string | number | boolean | undefined;
}

export interface FederatedAgent {
  id: string;
  name: string;
  description: string;
  endpoint_url: string;
  category?: string;
  skills: string[];
  reputation_score?: number;
  federation_partner_id: string;
  federation_partner_name: string;
}

export interface VerifyFederationKeyResponse {
  valid: boolean;
  organization_name?: string;
  organization_id?: string;
}

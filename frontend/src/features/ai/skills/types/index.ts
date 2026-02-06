export type SkillCategory =
  | 'productivity'
  | 'sales'
  | 'customer_support'
  | 'product_management'
  | 'marketing'
  | 'legal'
  | 'finance'
  | 'data'
  | 'enterprise_search'
  | 'bio_research'
  | 'skill_management';

export type SkillStatus = 'active' | 'inactive' | 'draft';

export interface SkillCommand {
  name: string;
  description: string;
  argument_hint?: string;
  workflow_steps?: string[];
}

export interface SkillConnectorInfo {
  id: string;
  name: string;
  status: string;
}

export interface AiSkill {
  id: string;
  name: string;
  slug: string;
  description: string;
  category: SkillCategory;
  status: SkillStatus;
  system_prompt: string;
  commands: SkillCommand[];
  connectors: SkillConnectorInfo[];
  knowledge_base?: { id: string; name: string } | null;
  activation_rules: Record<string, unknown>;
  metadata: Record<string, unknown>;
  tags: string[];
  is_system: boolean;
  is_enabled: boolean;
  version: string;
  usage_count: number;
  command_count: number;
  connector_count: number;
  has_knowledge_base: boolean;
  created_at: string;
  updated_at: string;
}

export interface AiSkillSummary {
  id: string;
  name: string;
  slug: string;
  description: string;
  category: SkillCategory;
  status: SkillStatus;
  is_system: boolean;
  is_enabled: boolean;
  command_count: number;
  connector_count: number;
  has_knowledge_base: boolean;
  tags: string[];
  usage_count: number;
  version: string;
}

export interface SkillFormData {
  name: string;
  description: string;
  category: SkillCategory;
  status: SkillStatus;
  system_prompt: string;
  commands: SkillCommand[];
  tags: string[];
  knowledge_base_id?: string;
  mcp_server_ids?: string[];
}

export interface SkillsListResponse {
  success: boolean;
  data?: {
    skills: AiSkillSummary[];
    pagination: {
      current_page: number;
      total_pages: number;
      total_count: number;
      per_page: number;
    };
  };
  error?: string;
}

export interface SkillResponse {
  success: boolean;
  data?: {
    skill: AiSkill;
  };
  error?: string;
}

export interface CategoriesResponse {
  success: boolean;
  data?: {
    categories: SkillCategory[];
  };
  error?: string;
}

export interface SkillFilters {
  category?: SkillCategory;
  status?: SkillStatus;
  enabled?: string;
  search?: string;
}

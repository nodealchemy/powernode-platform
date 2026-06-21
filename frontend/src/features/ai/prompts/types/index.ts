/**
 * AI Prompt Templates Types
 */

import type { ContentScope } from '@/features/content/scoped';

export type PromptCategory =
  | 'review'
  | 'implement'
  | 'security'
  | 'deploy'
  | 'docs'
  | 'custom'
  | 'general'
  | 'agent'
  | 'workflow';

export type PromptDomain = 'ai_workflow' | 'cicd' | 'general';

export interface PromptTemplate {
  id: string;
  name: string;
  slug: string;
  description?: string;
  category: PromptCategory;
  domain: PromptDomain;
  content: string;
  variables?: Record<string, unknown>[];
  metadata?: Record<string, unknown>;
  version: number;
  parent_template_id?: string;
  is_active: boolean;
  is_system: boolean;
  usage_count: number;
  variable_names: string[];
  created_by_name?: string;
  created_at: string;
  updated_at: string;
  // Globally-scoped foundational content provenance (see GloballyScopable).
  // `account_id == null` => GLOBAL platform template (read-only); a set
  // `cloned_from_id` => an account copy forked from another template.
  account_id?: string | null;
  cloned_from_id?: string | null;
  source_key?: string | null;
}

export interface PromptTemplateFormData {
  name: string;
  description?: string;
  category: PromptCategory;
  domain?: PromptDomain;
  content: string;
  variables?: Record<string, unknown>[];
  is_active?: boolean;
  parent_template_id?: string;
}

export interface PromptTemplatesResponse {
  prompt_templates: PromptTemplate[];
  meta: {
    total: number;
    by_category: Record<string, number>;
    by_domain: Record<string, number>;
  };
}

export interface PromptPreviewResponse {
  prompt_template_id: string;
  rendered_content: string;
  variables_used: string[];
  rendered_at: string;
}

export interface PromptTemplatesParams {
  category?: PromptCategory;
  domain?: PromptDomain;
  is_active?: boolean;
  root_only?: boolean;
  search?: string;
  scope?: ContentScope;
}

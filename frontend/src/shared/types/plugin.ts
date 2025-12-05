// Plugin System Type Definitions
// Platform-agnostic plugin architecture supporting AI providers, workflow nodes, and extensible types

export interface PluginMarketplace {
  id: string;
  name: string;
  slug: string;
  owner: string;
  description?: string;
  marketplace_type: 'public' | 'private' | 'team';
  source_type: 'git' | 'npm' | 'local' | 'url';
  source_url?: string;
  visibility: 'public' | 'private' | 'team';
  plugin_count: number;
  average_rating?: number;
  configuration: Record<string, unknown>;
  metadata: Record<string, unknown>;
  created_at: string;
  updated_at: string;
}

export interface Plugin {
  id: string;
  plugin_id: string;
  name: string;
  slug: string;
  description: string;
  version: string;
  author: string;
  homepage?: string;
  license?: string;
  plugin_types: PluginType[];
  source_type: 'git' | 'npm' | 'local' | 'url' | 'marketplace';
  source_url?: string;
  source_ref?: string;
  status: 'available' | 'installed' | 'error' | 'deprecated';
  is_verified: boolean;
  is_official: boolean;
  manifest: PluginManifest;
  capabilities: string[];
  configuration: Record<string, unknown>;
  metadata: Record<string, unknown>;
  install_count: number;
  download_count: number;
  average_rating?: number;
  rating_count: number;
  source_marketplace?: {
    id: string;
    name: string;
  };
  installation?: PluginInstallation;
  created_at: string;
  updated_at: string;
}

export type PluginType = 'ai_provider' | 'workflow_node' | 'integration' | 'webhook' | 'tool';

export interface PluginManifest {
  manifest_version: string;
  plugin: {
    id: string;
    name: string;
    version: string;
    author: string;
    description: string;
    homepage?: string;
    license?: string;
    tags?: string[];
    icon?: string;
  };
  compatibility: {
    powernode_version?: string;
    platform?: string[];
    dependencies?: {
      required?: string[];
      optional?: string[];
    };
  };
  plugin_types: PluginType[];
  ai_provider?: AiProviderConfig;
  workflow_nodes?: WorkflowNodeConfig[];
  permissions?: string[];
  lifecycle?: {
    install?: string;
    uninstall?: string;
    activate?: string;
    deactivate?: string;
  };
  endpoints?: {
    health_check?: string;
    provider_execute?: string;
    node_execute?: string;
  };
}

export interface AiProviderConfig {
  provider_type: 'openai_compatible' | 'anthropic_compatible' | 'custom';
  capabilities: string[];
  models: ProviderModel[];
  authentication: {
    type: string;
    fields: AuthenticationField[];
  };
  configuration?: Record<string, unknown>;
}

export interface ProviderModel {
  id: string;
  name: string;
  context_window: number;
  max_tokens: number;
  pricing?: {
    input_per_1k: number;
    output_per_1k: number;
  };
}

export interface AuthenticationField {
  name: string;
  label: string;
  type: 'text' | 'secret' | 'url' | 'number';
  required: boolean;
  default?: string;
}

export interface WorkflowNodeConfig {
  node_type: string;
  name: string;
  description: string;
  category: 'data' | 'logic' | 'integration' | 'ai' | 'custom';
  icon?: string;
  color?: string;
  input_schema: Record<string, unknown>;
  output_schema: Record<string, unknown>;
  configuration_schema?: Record<string, unknown>;
}

export interface PluginInstallation {
  id: string;
  plugin_id: string;
  status: 'active' | 'inactive' | 'error' | 'updating';
  installed_at: string;
  last_activated_at?: string;
  last_used_at?: string;
  configuration: Record<string, unknown>;
  installation_metadata: Record<string, unknown>;
  execution_count: number;
  total_cost: number;
  plugin?: Plugin;
  created_at: string;
  updated_at: string;
}

export interface PluginReview {
  id: string;
  plugin_id: string;
  rating: number;
  review_text?: string;
  is_verified_purchase: boolean;
  plugin_version: string;
  user: {
    id: string;
    email: string;
    full_name: string;
  };
  created_at: string;
  updated_at: string;
}

// API Request/Response Types
export interface CreatePluginMarketplaceRequest {
  marketplace: {
    name: string;
    owner: string;
    description?: string;
    marketplace_type: 'public' | 'private' | 'team';
    source_type: 'git' | 'npm' | 'local' | 'url';
    source_url?: string;
    visibility?: 'public' | 'private' | 'team';
    configuration?: Record<string, unknown>;
  };
}

export interface CreatePluginRequest {
  plugin: {
    plugin_id: string;
    name: string;
    description: string;
    version: string;
    author: string;
    homepage?: string;
    license?: string;
    plugin_types: PluginType[];
    source_type: 'git' | 'npm' | 'local' | 'url' | 'marketplace';
    source_url?: string;
    source_ref?: string;
    manifest: PluginManifest;
    capabilities?: string[];
    configuration?: Record<string, unknown>;
  };
}

export interface InstallPluginRequest {
  configuration?: Record<string, unknown>;
}

export interface UpdatePluginConfigurationRequest {
  configuration: Record<string, unknown>;
}

export interface SetPluginCredentialRequest {
  credential_key: string;
  credential_value: string;
}

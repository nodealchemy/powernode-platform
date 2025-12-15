// ===== CONSOLIDATED NODE CONFIGURATION TYPES =====
// Type-safe configuration for consolidated workflow nodes (Phase 1A)

// Parameter mapping for MCP operations
export interface ParameterMapping {
  parameter_name: string;
  mapping_type: 'static' | 'variable' | 'expression';
  static_value?: unknown;
  variable_path?: string;
  expression?: string;
}

// KB Article node action types
export type KbArticleAction = 'create' | 'read' | 'update' | 'search' | 'publish';

export interface KbArticleNodeConfiguration {
  action: KbArticleAction;
  article_id?: string;
  article_slug?: string;
  title?: string;
  content?: string;
  category_id?: string;
  tags?: string | string[];
  status?: 'draft' | 'published' | 'archived' | 'review';
  query?: string;
  search_query?: string;
  limit?: number;
  sort_by?: 'recent' | 'popular' | 'title';
  is_public?: boolean;
  output_variable?: string;
  output_mapping?: Record<string, string>;
}

// Page node action types
export type PageAction = 'create' | 'read' | 'update' | 'publish';

export interface PageNodeConfiguration {
  action: PageAction;
  page_id?: string;
  title?: string;
  slug?: string;
  content?: string;
  status?: 'draft' | 'published';
  meta_description?: string;
  meta_keywords?: string;
  output_variable?: string;
  output_mapping?: Record<string, string>;
}

// MCP Operation node types
export type McpOperationType = 'tool' | 'resource' | 'prompt';

export interface McpOperationNodeConfiguration {
  operation_type?: McpOperationType;
  mcp_server_id?: string;
  mcp_server_name?: string;
  // Tool-specific fields
  mcp_tool_id?: string;
  mcp_tool_name?: string;
  mcp_tool_description?: string;
  input_schema?: Record<string, unknown>;
  execution_mode?: 'sync' | 'async';
  parameters?: Record<string, unknown>;
  parameter_mappings?: ParameterMapping[];
  // Resource-specific fields
  resource_uri?: string;
  resource_name?: string;
  mime_type?: string;
  cache_duration_seconds?: number;
  // Prompt-specific fields
  prompt_name?: string;
  prompt_description?: string;
  arguments?: Record<string, unknown>;
  argument_mappings?: ParameterMapping[];
  arguments_schema?: Record<string, unknown>;
  // Common fields
  timeout_seconds?: number;
  retry_on_failure?: boolean;
  output_variable?: string;
  output_mapping?: Record<string, string>;
}

// MCP Workflow Builder types
export interface McpServerForWorkflowBuilder {
  id: string;
  name: string;
  description?: string;
  status: string;
  connection_type: string;
  capabilities?: Record<string, unknown>;
  tools: McpToolForWorkflowBuilder[];
  resources: McpResourceForWorkflowBuilder[];
  prompts: McpPromptForWorkflowBuilder[];
}

export interface McpToolForWorkflowBuilder {
  id: string;
  name: string;
  description?: string;
  input_schema?: Record<string, unknown>;
  permission_level?: string;
}

export interface McpResourceForWorkflowBuilder {
  uri: string;
  name?: string;
  description?: string;
  mime_type?: string;
}

export interface McpPromptForWorkflowBuilder {
  name: string;
  description?: string;
  arguments?: Array<{
    name: string;
    description?: string;
    required?: boolean;
  }>;
}

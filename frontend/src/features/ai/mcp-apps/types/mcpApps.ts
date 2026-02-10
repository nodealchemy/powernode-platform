// MCP App Types
export type McpAppType = 'custom' | 'template' | 'system';
export type McpAppStatus = 'draft' | 'published' | 'archived';

// MCP App (list/summary shape)
export interface McpApp {
  id: string;
  account_id: string;
  name: string;
  description: string | null;
  app_type: McpAppType;
  status: McpAppStatus;
  version: string;
  created_by_id: string | null;
  input_schema: Record<string, unknown>;
  output_schema: Record<string, unknown>;
  metadata: Record<string, unknown>;
  created_at: string;
  updated_at: string;
}

// MCP App (detailed shape, includes html_content, csp, sandbox)
export interface McpAppDetailed extends McpApp {
  html_content: string | null;
  csp_policy: Record<string, unknown>;
  sandbox_config: Record<string, unknown>;
  instance_count: number;
}

// Render result
export interface McpAppRenderResult {
  html: string;
  instance_id: string;
  csp_headers: Record<string, string>;
  sandbox_attrs: string;
}

// Process input result
export interface McpAppProcessResult {
  response: Record<string, unknown>;
  state_update: Record<string, unknown> | null;
}

// API params
export interface McpAppFilterParams {
  status?: McpAppStatus;
  app_type?: McpAppType;
  search?: string;
}

export interface CreateMcpAppParams {
  name: string;
  description?: string;
  app_type: McpAppType;
  status?: McpAppStatus;
  html_content?: string;
  version?: string;
  csp_policy?: Record<string, unknown>;
  sandbox_config?: Record<string, unknown>;
  input_schema?: Record<string, unknown>;
  output_schema?: Record<string, unknown>;
  metadata?: Record<string, unknown>;
}

export interface UpdateMcpAppParams extends Partial<CreateMcpAppParams> {
  id: string;
}

export interface RenderMcpAppParams {
  id: string;
  session_id?: string;
  context?: Record<string, unknown>;
}

export interface ProcessMcpAppInputParams {
  id: string;
  instance_id: string;
  input_data: Record<string, unknown>;
}

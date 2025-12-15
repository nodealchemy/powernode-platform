// ===== CORE WORKFLOW TYPES =====

export interface AiWorkflow {
  id: string;
  name: string;
  description: string;
  status: 'draft' | 'active' | 'inactive' | 'paused' | 'archived';
  visibility: 'private' | 'account' | 'public';
  version: number;
  tags: string[];
  is_template?: boolean;
  template_category?: string;
  trigger_types?: string[];
  execution_mode?: 'sequential' | 'parallel' | 'conditional';
  retry_policy?: Record<string, unknown>;
  timeout_seconds?: number;
  max_execution_time?: number;
  cost_limit?: number;
  configuration: Record<string, unknown> & {
    operations_agent_id?: string;
  };
  metadata: Record<string, unknown>;
  input_schema?: Record<string, unknown>;
  output_schema?: Record<string, unknown>;
  created_at: string;
  updated_at: string;
  created_by: {
    id: string;
    name: string;
    email: string;
  };
  nodes?: AiWorkflowNode[];
  edges?: AiWorkflowEdge[];
  triggers?: AiWorkflowTrigger[];
  variables?: AiWorkflowVariable[];
  stats?: {
    nodes_count: number;
    edges_count: number;
    runs_count: number;
    success_rate?: number | null;
    avg_runtime?: number | null;
    last_run_at?: string;
  };
}

// All workflow node types (consolidated in Phase 1A)
export type WorkflowNodeType =
  // Core flow nodes
  | 'start' | 'end' | 'trigger'
  // AI & processing nodes
  | 'ai_agent' | 'prompt_template' | 'data_processor' | 'transform'
  // Flow control nodes
  | 'condition' | 'loop' | 'delay' | 'merge' | 'split'
  // Data nodes
  | 'database' | 'file' | 'validator'
  // Communication nodes
  | 'email' | 'notification'
  // Integration nodes
  | 'api_call' | 'webhook' | 'scheduler'
  // Process nodes
  | 'human_approval' | 'sub_workflow'
  // Consolidated content & MCP nodes (Phase 1A)
  | 'kb_article' | 'page' | 'mcp_operation';

// Per-handle position configuration
export type HandlePosition = 'top' | 'bottom' | 'left' | 'right';
export type HandlePositions = Record<string, HandlePosition>;

export interface AiWorkflowNode {
  id: string;
  node_id: string;
  node_type: WorkflowNodeType;
  name: string;
  description: string;
  position_x: number;
  position_y: number;
  configuration: Record<string, unknown>;
  metadata: Record<string, unknown>;
  handlePositions?: HandlePositions;
  is_start_node?: boolean;
  is_end_node?: boolean;
  is_error_handler?: boolean;
  timeout_seconds?: number;
  retry_count?: number;
  created_at: string;
  updated_at: string;
}

export interface AiWorkflowEdge {
  id: string;
  edge_id: string;
  source_node_id: string;
  target_node_id: string;
  source_handle?: string;
  target_handle?: string;
  condition_type?: string;
  condition_value?: unknown;
  metadata: Record<string, unknown>;
  is_conditional?: boolean;
  edge_type?: 'default' | 'success' | 'error' | 'conditional';
}

export interface AiWorkflowTrigger {
  id: string;
  trigger_type: string;
  name: string;
  is_active: boolean;
  configuration: Record<string, unknown>;
  created_at: string;
}

export interface AiWorkflowVariable {
  id: string;
  name: string;
  variable_type: 'string' | 'number' | 'boolean' | 'object' | 'array';
  default_value?: unknown;
  is_required: boolean;
  is_input?: boolean;
  is_output?: boolean;
  description: string;
}

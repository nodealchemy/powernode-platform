// ===== WORKFLOW TEMPLATE & FILTER TYPES =====

export interface WorkflowTemplate {
  id: string;
  name: string;
  description: string;
  category: string;
  // Support both naming conventions
  executionOrder?: 'sequential' | 'parallel' | 'conditional';
  execution_mode?: 'sequential' | 'parallel' | 'conditional';
  agents?: Array<{
    role: string;
    description: string;
    conditions?: {
      type: string;
      term?: string;
      agentId?: string;
      minStep?: number;
    };
  }>;
  tags?: string[];
  difficulty?: 'beginner' | 'intermediate' | 'advanced';
  estimatedDuration?: string;
  estimated_duration?: string;
  cost?: 'free' | 'premium';
  // Database template fields
  is_database_template?: boolean;
  visibility?: 'private' | 'account' | 'public';
  nodes_count?: number;
  created_at?: string;
  updated_at?: string;
  created_by?: {
    id: string;
    name: string;
  } | null;
}

export interface WorkflowFilters {
  status?: string;
  visibility?: string;
  tags?: string[];
  createdBy?: string;
  dateRange?: {
    start: string;
    end: string;
  };
  search?: string;
  perPage?: number;
  page?: number;
  sort_by?: string;
  sort_order?: 'asc' | 'desc';
}

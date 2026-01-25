/**
 * Workflow validation types - validation rules and results
 */

// ===== NODE OUTPUT DATA TYPES =====
// Type-safe output data for workflow nodes

export type NodeOutputData =
  | { type: 'text'; content: string }
  | { type: 'json'; data: Record<string, unknown> }
  | { type: 'markdown'; content: string }
  | { type: 'html'; content: string }
  | { type: 'error'; message: string; stack?: string; code?: string }
  | { type: 'binary'; data: ArrayBuffer; mimeType?: string };

// ===== WORKFLOW VALIDATION TYPES =====
// Canonical validation types - single source of truth

export interface ValidationIssue {
  id: string;
  node_id: string;
  node_name: string;
  node_type: string;
  severity: 'error' | 'warning' | 'info';
  category: 'configuration' | 'connection' | 'data_flow' | 'performance' | 'security';
  rule_id: string;
  rule_name: string;
  message: string;
  description?: string;
  suggestion?: string;
  auto_fixable: boolean;
  metadata?: Record<string, unknown>;
}

export interface WorkflowValidationResult {
  workflow_id: string;
  workflow_name: string;
  overall_status: 'valid' | 'warnings' | 'errors';
  health_score: number; // 0-100
  total_nodes: number;
  validated_nodes: number;
  issues: ValidationIssue[];
  validation_timestamp: string;
  validation_duration_ms: number;
  categories: {
    configuration: number;
    connection: number;
    data_flow: number;
    performance: number;
    security: number;
  };
}

export interface ValidationRule {
  id: string;
  name: string;
  description: string;
  category: ValidationIssue['category'];
  severity: ValidationIssue['severity'];
  enabled: boolean;
  auto_fixable: boolean;
}

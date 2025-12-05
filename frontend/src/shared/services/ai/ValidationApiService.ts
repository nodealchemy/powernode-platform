import { BaseApiService } from './BaseApiService';
import type {
  ValidationIssue,
  ValidationRule,
  WorkflowValidationResult,
} from '@/shared/types/workflow';

/**
 * API service for workflow validation operations
 */
class ValidationApiService extends BaseApiService {
  protected resource = 'ai_workflows';

  /**
   * Validate a workflow
   */
  async validateWorkflow(workflowId: string): Promise<{
    validation_result: WorkflowValidationResult;
  }> {
    const path = this.buildPath(this.resource);
    return this.post<{
      validation_result: WorkflowValidationResult;
    }>(`${path}/${workflowId}/validate`, {});
  }

  /**
   * Validate specific nodes
   */
  async validateNodes(
    workflowId: string,
    nodeIds: string[]
  ): Promise<{
    issues: ValidationIssue[];
  }> {
    const path = this.buildPath(this.resource);
    return this.post<{
      issues: ValidationIssue[];
    }>(`${path}/${workflowId}/validate_nodes`, {
      node_ids: nodeIds
    });
  }

  /**
   * Auto-fix validation issues
   */
  async autoFix(
    workflowId: string,
    issueIds: string[]
  ): Promise<{
    workflow: any;
    fixed_issues: string[];
    remaining_issues: ValidationIssue[];
  }> {
    const path = this.buildPath(this.resource);
    return this.post<{
      workflow: any;
      fixed_issues: string[];
      remaining_issues: ValidationIssue[];
    }>(`${path}/${workflowId}/auto_fix`, {
      issue_ids: issueIds
    });
  }

  /**
   * Get validation rules
   */
  async getValidationRules(filters?: {
    category?: string;
    severity?: string;
    enabled?: boolean;
  }): Promise<{
    rules: ValidationRule[];
  }> {
    const path = this.buildPath('validation_rules');
    const queryParams = new URLSearchParams();

    if (filters?.category) {
      queryParams.append('category', filters.category);
    }
    if (filters?.severity) {
      queryParams.append('severity', filters.severity);
    }
    if (filters?.enabled !== undefined) {
      queryParams.append('enabled', filters.enabled.toString());
    }

    const query = queryParams.toString();
    const url = `${path}${query ? `?${query}` : ''}`;

    return this.get<{
      rules: ValidationRule[];
    }>(url);
  }

  /**
   * Update validation rule
   */
  async updateValidationRule(
    ruleId: string,
    updates: Partial<ValidationRule>
  ): Promise<{
    rule: ValidationRule;
  }> {
    const path = this.buildPath('validation_rules');
    return this.patch<{
      rule: ValidationRule;
    }>(`${path}/${ruleId}`, {
      rule: updates
    });
  }

  /**
   * Get validation history
   */
  async getValidationHistory(
    workflowId: string,
    limit?: number
  ): Promise<{
    validations: Array<{
      id: string;
      workflow_id: string;
      health_score: number;
      overall_status: string;
      issues_count: number;
      validated_at: string;
    }>;
  }> {
    const path = this.buildPath(this.resource);
    const query = limit ? `?limit=${limit}` : '';
    return this.get<{
      validations: Array<{
        id: string;
        workflow_id: string;
        health_score: number;
        overall_status: string;
        issues_count: number;
        validated_at: string;
      }>;
    }>(`${path}/${workflowId}/validation_history${query}`);
  }

  /**
   * Compare validation results
   */
  async compareValidations(
    workflowId: string,
    validation1Id: string,
    validation2Id: string
  ): Promise<{
    comparison: {
      health_score_diff: number;
      new_issues: ValidationIssue[];
      resolved_issues: ValidationIssue[];
      changed_issues: ValidationIssue[];
    };
  }> {
    const path = this.buildPath(this.resource);
    return this.post<{
      comparison: {
        health_score_diff: number;
        new_issues: ValidationIssue[];
        resolved_issues: ValidationIssue[];
        changed_issues: ValidationIssue[];
      };
    }>(`${path}/${workflowId}/compare_validations`, {
      validation_1_id: validation1Id,
      validation_2_id: validation2Id
    });
  }

  /**
   * Get validation statistics
   */
  async getValidationStatistics(
    workflowId: string,
    timeRange?: '7d' | '30d' | '90d'
  ): Promise<{
    statistics: {
      total_validations: number;
      avg_health_score: number;
      health_score_trend: 'improving' | 'stable' | 'declining';
      most_common_issues: Array<{
        rule_name: string;
        count: number;
        category: string;
      }>;
      validation_frequency: Array<{
        date: string;
        count: number;
        avg_health_score: number;
      }>;
    };
  }> {
    const path = this.buildPath(this.resource);
    const query = timeRange ? `?time_range=${timeRange}` : '';
    return this.get<{
      statistics: {
        total_validations: number;
        avg_health_score: number;
        health_score_trend: 'improving' | 'stable' | 'declining';
        most_common_issues: Array<{
          rule_name: string;
          count: number;
          category: string;
        }>;
        validation_frequency: Array<{
          date: string;
          count: number;
          avg_health_score: number;
        }>;
      };
    }>(`${path}/${workflowId}/validation_statistics${query}`);
  }
}

export const validationApi = new ValidationApiService();

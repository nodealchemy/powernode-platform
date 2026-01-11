import React, { useState, useEffect, useCallback, useMemo } from 'react';
import { CheckCircle2, XCircle, AlertTriangle, Info, RefreshCw, Play, Zap, Filter } from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { Select } from '@/shared/components/ui/Select';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { ValidationRuleCard } from './ValidationRuleCard';
import { WorkflowHealthScore } from './WorkflowHealthScore';
import { useWorkflowValidation } from '../../hooks/useWorkflowValidation';
import type {
  AiWorkflow,
  ValidationIssue,
  WorkflowValidationResult,
} from '@/shared/types/workflow';

export interface NodeValidationPanelProps {
  workflow: AiWorkflow;
  onValidate?: (workflowId: string) => Promise<WorkflowValidationResult>;
  onAutoFix?: (workflowId: string, issueIds: string[]) => Promise<void>;
  autoValidate?: boolean;
}

export const NodeValidationPanel: React.FC<NodeValidationPanelProps> = ({
  workflow,
  onValidate,
  onAutoFix,
  autoValidate = false
}) => {
  const [validationResult, setValidationResult] = useState<WorkflowValidationResult | null>(null);
  const [validating, setValidating] = useState(false);
  const [autoFixing, setAutoFixing] = useState(false);
  const [filterSeverity, setFilterSeverity] = useState<'all' | 'error' | 'warning' | 'info'>('all');
  const [filterCategory, setFilterCategory] = useState<'all' | ValidationIssue['category']>('all');
  const [selectedIssues, setSelectedIssues] = useState<Set<string>>(new Set());

  const { addNotification } = useNotifications();
  const { validate: realtimeValidate, isValidating } = useWorkflowValidation({
    workflowId: workflow.id,
    autoValidate
  });

  // Perform validation
  const performValidation = useCallback(async () => {
    try {
      setValidating(true);

      if (onValidate) {
        const result = await onValidate(workflow.id);
        setValidationResult(result);
      } else {
        // Use realtime validation from API
        const result = await realtimeValidate();
        if (result) {
          setValidationResult(result);
        } else {
          throw new Error('Validation returned no result');
        }
      }

      addNotification({
        type: 'success',
        title: 'Validation Complete',
        message: `Found ${validationResult?.issues.length || 0} issues`
      });
    } catch (error) {
      if (process.env.NODE_ENV === 'development') {
        console.error('Validation failed:', error);
      }
      addNotification({
        type: 'error',
        title: 'Validation Failed',
        message: 'Failed to validate workflow. Please try again.'
      });
    } finally {
      setValidating(false);
    }
  }, [workflow, onValidate, realtimeValidate, addNotification, validationResult?.issues.length]);

  // Initial validation
  useEffect(() => {
    if (autoValidate) {
      performValidation();
    }
  }, [autoValidate, performValidation]);

  // Filter issues
  const filteredIssues = useMemo(() => {
    if (!validationResult) return [];

    let filtered = validationResult.issues;

    if (filterSeverity !== 'all') {
      filtered = filtered.filter(issue => issue.severity === filterSeverity);
    }

    if (filterCategory !== 'all') {
      filtered = filtered.filter(issue => issue.category === filterCategory);
    }

    return filtered;
  }, [validationResult, filterSeverity, filterCategory]);

  // Group issues by severity
  const issuesBySeverity = useMemo(() => {
    if (!validationResult) return { errors: 0, warnings: 0, info: 0 };

    return {
      errors: validationResult.issues.filter(i => i.severity === 'error').length,
      warnings: validationResult.issues.filter(i => i.severity === 'warning').length,
      info: validationResult.issues.filter(i => i.severity === 'info').length
    };
  }, [validationResult]);

  // Auto-fix issues
  const handleAutoFix = useCallback(async () => {
    if (!validationResult || selectedIssues.size === 0) return;

    try {
      setAutoFixing(true);

      if (onAutoFix) {
        await onAutoFix(workflow.id, Array.from(selectedIssues));
      }

      addNotification({
        type: 'success',
        title: 'Auto-Fix Complete',
        message: `Fixed ${selectedIssues.size} issues`
      });

      // Re-validate after auto-fix
      setSelectedIssues(new Set());
      await performValidation();
    } catch (error) {
      addNotification({
        type: 'error',
        title: 'Auto-Fix Failed',
        message: 'Failed to apply automatic fixes. Please try again.'
      });
    } finally {
      setAutoFixing(false);
    }
  }, [workflow.id, validationResult, selectedIssues, onAutoFix, addNotification, performValidation]);

  // Toggle issue selection
  const toggleIssueSelection = useCallback((issueId: string) => {
    setSelectedIssues(prev => {
      const updated = new Set(prev);
      if (updated.has(issueId)) {
        updated.delete(issueId);
      } else {
        updated.add(issueId);
      }
      return updated;
    });
  }, []);

  // Select all auto-fixable issues
  const selectAutoFixable = useCallback(() => {
    if (!validationResult) return;

    const autoFixableIds = new Set(
      validationResult.issues
        .filter(issue => issue.auto_fixable)
        .map(issue => issue.id)
    );

    setSelectedIssues(autoFixableIds);
  }, [validationResult]);

  const autoFixableCount = useMemo(() => {
    if (!validationResult) return 0;
    return validationResult.issues.filter(i => i.auto_fixable).length;
  }, [validationResult]);

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-2xl font-bold text-theme-primary">Workflow Validation</h2>
          <p className="text-theme-secondary mt-1">
            Validate workflow configuration and identify potential issues
          </p>
        </div>
        <div className="flex items-center gap-2">
          <Button
            variant="outline"
            onClick={performValidation}
            disabled={validating || isValidating}
            className="flex items-center gap-2"
          >
            <RefreshCw className={`h-4 w-4 ${validating || isValidating ? 'animate-spin' : ''}`} />
            {validating || isValidating ? 'Validating...' : 'Validate'}
          </Button>
          {autoFixableCount > 0 && (
            <Button
              onClick={selectAutoFixable}
              variant="outline"
              className="flex items-center gap-2"
            >
              <Zap className="h-4 w-4" />
              Select Auto-Fixable ({autoFixableCount})
            </Button>
          )}
          {selectedIssues.size > 0 && (
            <Button
              onClick={handleAutoFix}
              disabled={autoFixing}
              className="flex items-center gap-2"
            >
              <Play className="h-4 w-4" />
              {autoFixing ? 'Fixing...' : `Fix ${selectedIssues.size} Issues`}
            </Button>
          )}
        </div>
      </div>

      {/* Health Score */}
      {validationResult && (
        <WorkflowHealthScore
          healthScore={validationResult.health_score}
          overallStatus={validationResult.overall_status}
          totalNodes={validationResult.total_nodes}
          validatedNodes={validationResult.validated_nodes}
          validationDuration={validationResult.validation_duration_ms}
        />
      )}

      {/* Issue Summary */}
      {validationResult && (
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          <Card className="p-4">
            <div className="flex items-center gap-3">
              <div className="w-12 h-12 bg-theme-error bg-opacity-10 rounded-lg flex items-center justify-center">
                <XCircle className="h-6 w-6 text-theme-error" />
              </div>
              <div>
                <p className="text-xs text-theme-tertiary mb-1">Errors</p>
                <p className="text-2xl font-bold text-theme-primary">{issuesBySeverity.errors}</p>
                <p className="text-xs text-theme-error">Must be fixed</p>
              </div>
            </div>
          </Card>

          <Card className="p-4">
            <div className="flex items-center gap-3">
              <div className="w-12 h-12 bg-theme-warning bg-opacity-10 rounded-lg flex items-center justify-center">
                <AlertTriangle className="h-6 w-6 text-theme-warning" />
              </div>
              <div>
                <p className="text-xs text-theme-tertiary mb-1">Warnings</p>
                <p className="text-2xl font-bold text-theme-primary">{issuesBySeverity.warnings}</p>
                <p className="text-xs text-theme-warning">Should be reviewed</p>
              </div>
            </div>
          </Card>

          <Card className="p-4">
            <div className="flex items-center gap-3">
              <div className="w-12 h-12 bg-theme-info bg-opacity-10 rounded-lg flex items-center justify-center">
                <Info className="h-6 w-6 text-theme-info" />
              </div>
              <div>
                <p className="text-xs text-theme-tertiary mb-1">Info</p>
                <p className="text-2xl font-bold text-theme-primary">{issuesBySeverity.info}</p>
                <p className="text-xs text-theme-info">Suggestions</p>
              </div>
            </div>
          </Card>
        </div>
      )}

      {/* Filters */}
      {validationResult && validationResult.issues.length > 0 && (
        <Card className="p-4">
          <div className="flex items-center gap-4">
            <Filter className="h-4 w-4 text-theme-tertiary" />
            <Select
              value={filterSeverity}
              onChange={(value) => setFilterSeverity(value as any)}
              className="w-40"
            >
              <option value="all">All Severities</option>
              <option value="error">Errors Only</option>
              <option value="warning">Warnings Only</option>
              <option value="info">Info Only</option>
            </Select>
            <Select
              value={filterCategory}
              onChange={(value) => setFilterCategory(value as any)}
              className="w-48"
            >
              <option value="all">All Categories</option>
              <option value="configuration">Configuration</option>
              <option value="connection">Connection</option>
              <option value="data_flow">Data Flow</option>
              <option value="performance">Performance</option>
              <option value="security">Security</option>
            </Select>
          </div>
        </Card>
      )}

      {/* Validation Issues */}
      {validating || isValidating ? (
        <div className="text-center py-12">
          <RefreshCw className="h-8 w-8 animate-spin text-theme-interactive-primary mx-auto mb-4" />
          <p className="text-theme-secondary">Validating workflow...</p>
        </div>
      ) : !validationResult ? (
        <Card className="p-12 text-center">
          <CheckCircle2 className="h-12 w-12 text-theme-tertiary mx-auto mb-4 opacity-50" />
          <p className="text-theme-secondary mb-2">No validation performed yet</p>
          <p className="text-theme-tertiary text-sm mb-4">
            Click "Validate" to check your workflow for potential issues
          </p>
          <Button onClick={performValidation} className="flex items-center gap-2 mx-auto">
            <Play className="h-4 w-4" />
            Run Validation
          </Button>
        </Card>
      ) : filteredIssues.length === 0 ? (
        <Card className="p-12 text-center">
          <CheckCircle2 className="h-12 w-12 text-theme-success mx-auto mb-4" />
          <p className="text-theme-primary font-medium mb-2">No issues found!</p>
          <p className="text-theme-secondary">
            {filterSeverity !== 'all' || filterCategory !== 'all'
              ? 'No issues match your current filters'
              : 'Your workflow passed all validation checks'}
          </p>
        </Card>
      ) : (
        <div className="space-y-3">
          {filteredIssues.map(issue => (
            <ValidationRuleCard
              key={issue.id}
              issue={issue}
              selected={selectedIssues.has(issue.id)}
              onToggleSelect={() => toggleIssueSelection(issue.id)}
            />
          ))}
        </div>
      )}
    </div>
  );
};

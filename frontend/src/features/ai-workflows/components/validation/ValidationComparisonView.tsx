import React, { useState, useEffect } from 'react';
import { GitCompare, TrendingUp, TrendingDown, Plus, Minus, AlertCircle } from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { validationApi } from '@/shared/services/ai';
import { useNotifications } from '@/shared/hooks/useNotifications';
import type { ValidationIssue } from '@/shared/types/workflow';

interface ValidationComparison {
  health_score_diff: number;
  new_issues: ValidationIssue[];
  resolved_issues: ValidationIssue[];
  changed_issues: ValidationIssue[];
}

interface ValidationComparisonViewProps {
  workflowId: string;
  validation1Id: string;
  validation2Id: string;
  onClose?: () => void;
}

export const ValidationComparisonView: React.FC<ValidationComparisonViewProps> = ({
  workflowId,
  validation1Id,
  validation2Id,
  onClose
}) => {
  const [comparison, setComparison] = useState<ValidationComparison | null>(null);
  const [loading, setLoading] = useState(true);
  const { addNotification } = useNotifications();

  // eslint-disable-next-line react-hooks/exhaustive-deps -- Load when IDs change
  useEffect(() => {
    loadComparison();
  }, [workflowId, validation1Id, validation2Id]);

  const loadComparison = async () => {
    try {
      setLoading(true);
      const response = await validationApi.compareValidations(workflowId, validation1Id, validation2Id);
      setComparison(response.comparison);
    } catch (error) {
      if (process.env.NODE_ENV === 'development') {
        console.error('Failed to load comparison:', error);
      }
      addNotification({
        type: 'error',
        title: 'Comparison Failed',
        message: 'Could not compare validations'
      });
    } finally {
      setLoading(false);
    }
  };

  const getSeverityColor = (severity: string) => {
    switch (severity) {
      case 'error': return 'text-theme-error';
      case 'warning': return 'text-theme-warning';
      case 'info': return 'text-theme-info';
      default: return 'text-theme-secondary';
    }
  };

  const getSeverityBg = (severity: string) => {
    switch (severity) {
      case 'error': return 'bg-theme-error bg-opacity-10';
      case 'warning': return 'bg-theme-warning bg-opacity-10';
      case 'info': return 'bg-theme-info bg-opacity-10';
      default: return 'bg-theme-surface-secondary';
    }
  };

  if (loading) {
    return (
      <Card className="p-8 text-center">
        <div className="animate-spin h-8 w-8 border-4 border-theme-interactive-primary border-t-transparent rounded-full mx-auto mb-4" />
        <p className="text-theme-secondary">Comparing validations...</p>
      </Card>
    );
  }

  if (!comparison) {
    return (
      <Card className="p-8 text-center">
        <AlertCircle className="h-12 w-12 text-theme-tertiary mx-auto mb-4 opacity-50" />
        <p className="text-theme-secondary">Could not load comparison</p>
      </Card>
    );
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          <GitCompare className="h-6 w-6 text-theme-primary" />
          <h2 className="text-2xl font-bold text-theme-primary">Validation Comparison</h2>
        </div>
        {onClose && (
          <button
            onClick={onClose}
            className="text-theme-tertiary hover:text-theme-primary transition-colors"
          >
            ×
          </button>
        )}
      </div>

      {/* Health Score Difference */}
      <Card className="p-6">
        <h3 className="text-lg font-semibold text-theme-primary mb-4">Health Score Change</h3>
        <div className="flex items-center justify-center gap-4">
          {comparison.health_score_diff > 0 ? (
            <>
              <TrendingUp className="h-8 w-8 text-theme-success" />
              <div className="text-center">
                <p className="text-4xl font-bold text-theme-success">
                  +{comparison.health_score_diff}
                </p>
                <p className="text-sm text-theme-secondary mt-1">
                  Health score improved
                </p>
              </div>
            </>
          ) : comparison.health_score_diff < 0 ? (
            <>
              <TrendingDown className="h-8 w-8 text-theme-error" />
              <div className="text-center">
                <p className="text-4xl font-bold text-theme-error">
                  {comparison.health_score_diff}
                </p>
                <p className="text-sm text-theme-secondary mt-1">
                  Health score declined
                </p>
              </div>
            </>
          ) : (
            <div className="text-center">
              <p className="text-4xl font-bold text-theme-tertiary">
                0
              </p>
              <p className="text-sm text-theme-secondary mt-1">
                No change in health score
              </p>
            </div>
          )}
        </div>
      </Card>

      {/* Summary Cards */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <Card className="p-4 bg-theme-error bg-opacity-5">
          <div className="flex items-center gap-3 mb-2">
            <Plus className="h-5 w-5 text-theme-error" />
            <p className="font-semibold text-theme-primary">New Issues</p>
          </div>
          <p className="text-3xl font-bold text-theme-error">
            {comparison.new_issues.length}
          </p>
        </Card>

        <Card className="p-4 bg-theme-success bg-opacity-5">
          <div className="flex items-center gap-3 mb-2">
            <Minus className="h-5 w-5 text-theme-success" />
            <p className="font-semibold text-theme-primary">Resolved Issues</p>
          </div>
          <p className="text-3xl font-bold text-theme-success">
            {comparison.resolved_issues.length}
          </p>
        </Card>

        <Card className="p-4 bg-theme-warning bg-opacity-5">
          <div className="flex items-center gap-3 mb-2">
            <AlertCircle className="h-5 w-5 text-theme-warning" />
            <p className="font-semibold text-theme-primary">Changed Issues</p>
          </div>
          <p className="text-3xl font-bold text-theme-warning">
            {comparison.changed_issues.length}
          </p>
        </Card>
      </div>

      {/* New Issues */}
      {comparison.new_issues.length > 0 && (
        <Card className="p-6">
          <div className="flex items-center gap-2 mb-4">
            <Plus className="h-5 w-5 text-theme-error" />
            <h3 className="text-lg font-semibold text-theme-primary">New Issues</h3>
            <Badge variant="danger">{comparison.new_issues.length}</Badge>
          </div>
          <div className="space-y-3">
            {comparison.new_issues.map((issue) => (
              <div
                key={issue.id}
                className={`p-3 rounded-lg ${getSeverityBg(issue.severity)}`}
              >
                <div className="flex items-start gap-3">
                  <AlertCircle className={`h-5 w-5 ${getSeverityColor(issue.severity)} flex-shrink-0 mt-0.5`} />
                  <div className="flex-1">
                    <div className="flex items-center gap-2 mb-1">
                      <p className={`font-medium ${getSeverityColor(issue.severity)}`}>
                        {issue.rule_name}
                      </p>
                      <Badge variant="outline" size="sm">{issue.category}</Badge>
                    </div>
                    <p className="text-sm text-theme-secondary">{issue.message}</p>
                    {issue.node_name && (
                      <p className="text-xs text-theme-tertiary mt-1">
                        Node: {issue.node_name}
                      </p>
                    )}
                  </div>
                </div>
              </div>
            ))}
          </div>
        </Card>
      )}

      {/* Resolved Issues */}
      {comparison.resolved_issues.length > 0 && (
        <Card className="p-6">
          <div className="flex items-center gap-2 mb-4">
            <Minus className="h-5 w-5 text-theme-success" />
            <h3 className="text-lg font-semibold text-theme-primary">Resolved Issues</h3>
            <Badge variant="success">{comparison.resolved_issues.length}</Badge>
          </div>
          <div className="space-y-3">
            {comparison.resolved_issues.map((issue) => (
              <div
                key={issue.id}
                className="p-3 rounded-lg bg-theme-success bg-opacity-10"
              >
                <div className="flex items-start gap-3">
                  <div className="flex-1">
                    <div className="flex items-center gap-2 mb-1">
                      <p className="font-medium text-theme-primary line-through opacity-60">
                        {issue.rule_name}
                      </p>
                      <Badge variant="outline" size="sm">{issue.category}</Badge>
                    </div>
                    <p className="text-sm text-theme-secondary line-through opacity-60">
                      {issue.message}
                    </p>
                    {issue.node_name && (
                      <p className="text-xs text-theme-tertiary mt-1">
                        Node: {issue.node_name}
                      </p>
                    )}
                  </div>
                </div>
              </div>
            ))}
          </div>
        </Card>
      )}

      {/* No Changes Message */}
      {comparison.new_issues.length === 0 &&
        comparison.resolved_issues.length === 0 &&
        comparison.changed_issues.length === 0 && (
        <Card className="p-8 text-center">
          <GitCompare className="h-12 w-12 text-theme-tertiary mx-auto mb-4 opacity-50" />
          <p className="text-theme-secondary">No changes detected between validations</p>
        </Card>
      )}
    </div>
  );
};

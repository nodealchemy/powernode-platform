import React, { useState, useEffect } from 'react';
import { Wrench, CheckCircle, AlertCircle, Eye, Play } from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { validationApi } from '@/shared/services/ai';
import { useNotifications } from '@/shared/hooks/useNotifications';
import type { ValidationIssue } from '@/shared/types/workflow';

interface AutoFixResult {
  fixed_count: number;
  fixes_applied: Array<{
    issue_code: string;
    node_id: string;
    description: string;
  }>;
  errors: string[];
  health_score_improvement: number;
}

interface AutoFixPanelProps {
  workflowId: string;
  issues: ValidationIssue[];
  onFixComplete?: () => void;
}

export const AutoFixPanel: React.FC<AutoFixPanelProps> = ({
  workflowId,
  issues,
  onFixComplete
}) => {
  const [selectedIssues, setSelectedIssues] = useState<Set<string>>(new Set());
  const [loading, setLoading] = useState(false);
  const [fixing, setFixing] = useState(false);
  const { addNotification } = useNotifications();

  const autoFixableIssues = issues.filter(issue => issue.auto_fixable);

  // eslint-disable-next-line react-hooks/exhaustive-deps -- Only react to issues changes
  useEffect(() => {
    // Select all auto-fixable issues by default
    const allAutoFixable = new Set(autoFixableIssues.map(issue => issue.rule_id));
    setSelectedIssues(allAutoFixable);
  }, [issues]);

  const toggleIssue = (ruleId: string) => {
    const newSelection = new Set(selectedIssues);
    if (newSelection.has(ruleId)) {
      newSelection.delete(ruleId);
    } else {
      newSelection.add(ruleId);
    }
    setSelectedIssues(newSelection);
  };

  const toggleAll = () => {
    if (selectedIssues.size === autoFixableIssues.length) {
      setSelectedIssues(new Set());
    } else {
      setSelectedIssues(new Set(autoFixableIssues.map(issue => issue.rule_id)));
    }
  };

  const loadPreview = async () => {
    try {
      setLoading(true);
      // Note: Preview functionality not yet implemented in API
      // Would need backend endpoint for preview
      addNotification({
        type: 'info',
        title: 'Preview Not Available',
        message: 'Preview functionality coming soon'
      });
    } catch (error) {
      if (process.env.NODE_ENV === 'development') {
        console.error('Failed to load preview:', error);
      }
      addNotification({
        type: 'error',
        title: 'Preview Failed',
        message: 'Could not load fix preview'
      });
    } finally {
      setLoading(false);
    }
  };

  const applyAllFixes = async () => {
    try {
      setFixing(true);
      // Get all auto-fixable issue IDs
      const issueIds = autoFixableIssues.map(issue => issue.id);
      const response = await validationApi.autoFix(workflowId, issueIds);
      const result = {
        fixed_count: response.fixed_issues.length,
        fixes_applied: response.fixed_issues.map(id => ({
          issue_code: id,
          node_id: '',
          description: 'Issue fixed'
        })),
        errors: [],
        health_score_improvement: 0 // Not provided by API
      } as AutoFixResult;

      if (result.fixed_count > 0) {
        addNotification({
          type: 'success',
          title: 'Fixes Applied',
          message: `Successfully fixed ${result.fixed_count} issue${result.fixed_count !== 1 ? 's' : ''}. Health score improved by ${result.health_score_improvement} points.`
        });

        if (onFixComplete) {
          onFixComplete();
        }
      } else {
        addNotification({
          type: 'info',
          title: 'No Fixes Applied',
          message: 'No auto-fixable issues were found'
        });
      }

      if (result.errors.length > 0) {
        result.errors.forEach(error => {
          addNotification({
            type: 'warning',
            title: 'Fix Warning',
            message: error
          });
        });
      }
    } catch (error) {
      if (process.env.NODE_ENV === 'development') {
        console.error('Failed to apply fixes:', error);
      }
      addNotification({
        type: 'error',
        title: 'Fix Failed',
        message: 'Could not apply auto-fixes'
      });
    } finally {
      setFixing(false);
    }
  };

  const applySelectedFixes = async () => {
    if (selectedIssues.size === 0) {
      addNotification({
        type: 'warning',
        title: 'No Issues Selected',
        message: 'Please select at least one issue to fix'
      });
      return;
    }

    try {
      setFixing(true);
      // Get selected issue IDs (convert from rule_ids to issue ids)
      const selectedIssueObjects = autoFixableIssues.filter(issue =>
        selectedIssues.has(issue.rule_id)
      );
      const issueIds = selectedIssueObjects.map(issue => issue.id);

      const response = await validationApi.autoFix(workflowId, issueIds);
      const totalFixed = response.fixed_issues.length;

      if (totalFixed > 0) {
        addNotification({
          type: 'success',
          title: 'Fixes Applied',
          message: `Successfully fixed ${totalFixed} of ${selectedIssues.size} selected issue${selectedIssues.size !== 1 ? 's' : ''}.`
        });

        if (onFixComplete) {
          onFixComplete();
        }
      } else {
        addNotification({
          type: 'info',
          title: 'No Fixes Applied',
          message: 'No issues could be automatically fixed'
        });
      }
    } catch (error) {
      if (process.env.NODE_ENV === 'development') {
        console.error('Failed to apply selected fixes:', error);
      }
      addNotification({
        type: 'error',
        title: 'Fix Failed',
        message: 'Could not apply selected fixes'
      });
    } finally {
      setFixing(false);
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

  if (autoFixableIssues.length === 0) {
    return (
      <Card className="p-8 text-center">
        <CheckCircle className="h-12 w-12 text-theme-success mx-auto mb-4" />
        <p className="text-theme-primary font-semibold mb-2">No Auto-Fixable Issues</p>
        <p className="text-theme-secondary text-sm">
          All issues require manual intervention
        </p>
      </Card>
    );
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          <Wrench className="h-6 w-6 text-theme-primary" />
          <div>
            <h2 className="text-2xl font-bold text-theme-primary">Auto-Fix Panel</h2>
            <p className="text-theme-secondary text-sm">
              {autoFixableIssues.length} issue{autoFixableIssues.length !== 1 ? 's' : ''} can be automatically fixed
            </p>
          </div>
        </div>
        <div className="flex items-center gap-2">
          <Button
            variant="outline"
            onClick={loadPreview}
            disabled={loading || fixing}
            className="flex items-center gap-2"
          >
            <Eye className="h-4 w-4" />
            Preview Changes
          </Button>
          <Button
            onClick={selectedIssues.size === autoFixableIssues.length ? applyAllFixes : applySelectedFixes}
            disabled={selectedIssues.size === 0 || fixing}
            className="flex items-center gap-2"
          >
            <Play className="h-4 w-4" />
            {fixing ? 'Applying...' : `Fix ${selectedIssues.size === autoFixableIssues.length ? 'All' : 'Selected'} (${selectedIssues.size})`}
          </Button>
        </div>
      </div>

      {/* Issue List */}
      <Card className="p-6">
        <div className="flex items-center justify-between mb-4">
          <h3 className="text-lg font-semibold text-theme-primary">Auto-Fixable Issues</h3>
          <button
            onClick={toggleAll}
            className="text-sm text-theme-interactive-primary hover:underline"
          >
            {selectedIssues.size === autoFixableIssues.length ? 'Deselect All' : 'Select All'}
          </button>
        </div>

        <div className="space-y-3">
          {autoFixableIssues.map((issue) => (
            <div
              key={issue.id}
              className={`p-4 rounded-lg ${getSeverityBg(issue.severity)} border-2 transition-all ${
                selectedIssues.has(issue.rule_id)
                  ? 'border-theme-interactive-primary'
                  : 'border-transparent'
              }`}
            >
              <div className="flex items-start gap-3">
                {/* Checkbox */}
                <input
                  type="checkbox"
                  checked={selectedIssues.has(issue.rule_id)}
                  onChange={() => toggleIssue(issue.rule_id)}
                  className="mt-1 h-4 w-4 rounded border-theme-border text-theme-interactive-primary focus:ring-2 focus:ring-theme-interactive-primary"
                />

                {/* Issue Content */}
                <div className="flex-1">
                  <div className="flex items-center gap-2 mb-2">
                    <AlertCircle className={`h-5 w-5 ${getSeverityColor(issue.severity)}`} />
                    <p className={`font-medium ${getSeverityColor(issue.severity)}`}>
                      {issue.rule_name}
                    </p>
                    <Badge variant={issue.severity === 'error' ? 'danger' : issue.severity === 'warning' ? 'warning' : 'secondary'}>
                      {issue.severity}
                    </Badge>
                    <Badge variant="outline" size="sm">{issue.category}</Badge>
                  </div>
                  <p className="text-sm text-theme-secondary mb-2">{issue.message}</p>
                  {issue.suggestion && (
                    <div className="bg-theme-surface-secondary rounded p-2 mt-2">
                      <p className="text-xs text-theme-tertiary font-semibold mb-1">Auto-Fix Action:</p>
                      <p className="text-xs text-theme-secondary">{issue.suggestion}</p>
                    </div>
                  )}
                  {issue.node_name && (
                    <p className="text-xs text-theme-tertiary mt-2">
                      Node: {issue.node_name} ({issue.node_type})
                    </p>
                  )}
                </div>

                {/* Auto-fixable Badge */}
                <div className="flex-shrink-0">
                  <Badge variant="success" className="flex items-center gap-1">
                    <Wrench className="h-3 w-3" />
                    Auto-fixable
                  </Badge>
                </div>
              </div>
            </div>
          ))}
        </div>
      </Card>

      {/* Preview Modal - Preview functionality coming soon */}
    </div>
  );
};

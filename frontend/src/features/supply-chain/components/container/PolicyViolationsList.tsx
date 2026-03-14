import React from 'react';
import { Shield, CheckCircle, XCircle, AlertTriangle } from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';

type Severity = 'critical' | 'high' | 'medium' | 'low';

interface PolicyViolation {
  rule: string;
  message: string;
  severity: Severity;
}

interface PolicyEvaluationResult {
  policy_id: string;
  policy_name: string;
  policy_type: string;
  enforcement_level: string;
  passed: boolean;
  violations: PolicyViolation[];
  evaluated_at: string;
}

interface PolicyViolationsListProps {
  evaluations: PolicyEvaluationResult[] | null;
  loading: boolean;
  error?: string | null;
  onEvaluate?: () => void;
}

const severityStyles: Record<Severity, string> = {
  critical: 'bg-theme-error/10 text-theme-error border-theme-error/30',
  high: 'bg-theme-error/10 text-theme-error border-theme-error/30',
  medium: 'bg-theme-warning/10 text-theme-warning border-theme-warning/30',
  low: 'bg-theme-info/10 text-theme-info border-theme-info/30',
};

export const PolicyViolationsList: React.FC<PolicyViolationsListProps> = ({
  evaluations,
  loading,
  error,
  onEvaluate,
}) => {
  if (loading) {
    return (
      <Card className="p-6">
        <div className="flex justify-center items-center py-12">
          <LoadingSpinner size="lg" />
        </div>
      </Card>
    );
  }

  if (error) {
    return (
      <Card className="p-6">
        <div className="text-center py-12 text-theme-error">{error}</div>
      </Card>
    );
  }

  if (!evaluations || evaluations.length === 0) {
    return (
      <Card className="p-6">
        <div className="text-center py-12 text-theme-muted">
          <Shield className="w-12 h-12 mx-auto mb-4 opacity-50" />
          <p>No policy evaluations available</p>
          {onEvaluate && (
            <button
              onClick={onEvaluate}
              className="mt-4 px-4 py-2 bg-theme-interactive-primary text-white rounded-lg hover:bg-theme-interactive-primary-hover"
            >
              Evaluate Policies
            </button>
          )}
        </div>
      </Card>
    );
  }

  const passedCount = evaluations.filter((e) => e.passed).length;
  const failedCount = evaluations.filter((e) => !e.passed).length;

  return (
    <div className="space-y-4">
      <Card className="p-4">
        <div className="flex items-center gap-6">
          <div className="flex items-center gap-2">
            <CheckCircle className="w-5 h-5 text-theme-success" />
            <span className="text-theme-primary">
              <span className="font-bold text-theme-success">{passedCount}</span> passed
            </span>
          </div>
          <div className="flex items-center gap-2">
            <XCircle className="w-5 h-5 text-theme-error" />
            <span className="text-theme-primary">
              <span className="font-bold text-theme-error">{failedCount}</span> failed
            </span>
          </div>
        </div>
      </Card>

      <div className="space-y-4">
        {evaluations.map((evaluation) => (
          <Card key={evaluation.policy_id} className="p-6">
            <div className="flex items-start justify-between mb-4">
              <div className="flex items-center gap-3">
                {evaluation.passed ? (
                  <CheckCircle className="w-6 h-6 text-theme-success" />
                ) : (
                  <XCircle className="w-6 h-6 text-theme-error" />
                )}
                <div>
                  <h3 className="font-semibold text-theme-primary">{evaluation.policy_name}</h3>
                  <div className="flex items-center gap-2 mt-1">
                    <Badge variant="outline" size="xs">
                      {evaluation.policy_type}
                    </Badge>
                    <Badge
                      variant={
                        evaluation.enforcement_level === 'block' ? 'danger' :
                        evaluation.enforcement_level === 'warn' ? 'warning' :
                        'secondary'
                      }
                      size="xs"
                    >
                      {evaluation.enforcement_level}
                    </Badge>
                  </div>
                </div>
              </div>
              <Badge variant={evaluation.passed ? 'success' : 'danger'}>
                {evaluation.passed ? 'Passed' : 'Failed'}
              </Badge>
            </div>

            {evaluation.violations.length > 0 && (
              <div className="space-y-2">
                <p className="text-sm font-medium text-theme-secondary flex items-center gap-1">
                  <AlertTriangle className="w-4 h-4" />
                  Violations ({evaluation.violations.length})
                </p>
                <div className="space-y-2">
                  {evaluation.violations.map((violation, index) => (
                    <div
                      key={index}
                      className={`p-3 rounded-lg border ${severityStyles[violation.severity]}`}
                    >
                      <div className="flex items-center justify-between mb-1">
                        <span className="font-medium text-sm">{violation.rule}</span>
                        <Badge variant="outline" size="xs">
                          {violation.severity}
                        </Badge>
                      </div>
                      <p className="text-sm opacity-90">{violation.message}</p>
                    </div>
                  ))}
                </div>
              </div>
            )}

            <div className="mt-4 text-xs text-theme-muted">
              Evaluated: {new Date(evaluation.evaluated_at).toLocaleString()}
            </div>
          </Card>
        ))}
      </div>
    </div>
  );
};

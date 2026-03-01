import React from 'react';
import { CheckCircle, AlertTriangle, XCircle, MinusCircle } from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useComplianceMatrix } from '../api/securityExtApi';
import type { ComplianceStatus, AsiComplianceItem } from '../types/security';

const STATUS_CONFIG: Record<ComplianceStatus, {
  variant: 'success' | 'warning' | 'danger' | 'default';
  icon: React.ComponentType<{ className?: string }>;
  label: string;
}> = {
  compliant: { variant: 'success', icon: CheckCircle, label: 'Compliant' },
  partial: { variant: 'warning', icon: AlertTriangle, label: 'Partial' },
  non_compliant: { variant: 'danger', icon: XCircle, label: 'Non-Compliant' },
  not_applicable: { variant: 'default', icon: MinusCircle, label: 'N/A' },
};

function getScoreColor(score: number): string {
  if (score >= 80) return 'text-theme-success';
  if (score >= 50) return 'text-theme-warning';
  return 'text-theme-error';
}

function getProgressBarColor(score: number): string {
  if (score >= 80) return 'bg-theme-success';
  if (score >= 50) return 'bg-theme-warning';
  return 'bg-theme-error';
}

const ComplianceRow: React.FC<{ item: AsiComplianceItem }> = ({ item }) => {
  const config = STATUS_CONFIG[item.status] || STATUS_CONFIG.not_applicable;
  const StatusIcon = config.icon;

  return (
    <Card className="p-4">
      <div className="flex items-start justify-between mb-3">
        <div className="flex items-center gap-2">
          <span className="text-sm font-semibold text-theme-primary">{item.asi_reference}</span>
          <Badge variant={config.variant} size="xs">
            <StatusIcon className="h-3 w-3 mr-1" />
            {config.label}
          </Badge>
        </div>
        <span className={`text-lg font-bold ${getScoreColor(item.score)}`}>
          {item.score}%
        </span>
      </div>

      <h4 className="text-sm font-medium text-theme-primary mb-1">{item.name}</h4>
      {item.description && (
        <p className="text-xs text-theme-tertiary mb-3">{item.description}</p>
      )}

      {/* Progress Bar */}
      <div className="w-full bg-theme-bg rounded-full h-2 mb-2">
        <div
          className={`h-2 rounded-full ${getProgressBarColor(item.score)}`}
          style={{ width: `${Math.min(item.score, 100)}%` }}
        />
      </div>

      {/* Controls */}
      <div className="flex items-center justify-between">
        <span className="text-xs text-theme-tertiary">
          Controls: {item.controls_met} / {item.controls_total}
        </span>
        {item.last_assessed_at && (
          <span className="text-xs text-theme-muted">
            Last assessed: {new Date(item.last_assessed_at).toLocaleDateString()}
          </span>
        )}
      </div>
    </Card>
  );
};

export const AsiComplianceMatrix: React.FC = () => {
  const { data, isLoading } = useComplianceMatrix();

  if (isLoading) {
    return <LoadingSpinner size="sm" className="py-8" />;
  }

  const matrix = data?.matrix || [];

  if (matrix.length === 0) {
    return (
      <div className="text-center py-12">
        <CheckCircle className="h-12 w-12 text-theme-muted mx-auto mb-4 opacity-50" />
        <p className="text-theme-secondary">No compliance data available.</p>
        <p className="text-sm text-theme-tertiary mt-1">
          Run a compliance assessment to see ASI01-ASI10 coverage.
        </p>
      </div>
    );
  }

  // Calculate overall score
  const applicableItems = matrix.filter((item) => item.status !== 'not_applicable');
  const overallScore = applicableItems.length > 0
    ? Math.round(applicableItems.reduce((sum, item) => sum + item.score, 0) / applicableItems.length)
    : 0;

  const compliantCount = matrix.filter((item) => item.status === 'compliant').length;
  const partialCount = matrix.filter((item) => item.status === 'partial').length;
  const nonCompliantCount = matrix.filter((item) => item.status === 'non_compliant').length;

  return (
    <div className="space-y-6">
      {/* Summary */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <Card className="p-4 text-center">
          <p className="text-xs text-theme-tertiary">Overall Score</p>
          <p className={`text-3xl font-bold ${getScoreColor(overallScore)}`}>{overallScore}%</p>
        </Card>
        <Card className="p-4 text-center">
          <p className="text-xs text-theme-tertiary">Compliant</p>
          <p className="text-3xl font-bold text-theme-success">{compliantCount}</p>
        </Card>
        <Card className="p-4 text-center">
          <p className="text-xs text-theme-tertiary">Partial</p>
          <p className="text-3xl font-bold text-theme-warning">{partialCount}</p>
        </Card>
        <Card className="p-4 text-center">
          <p className="text-xs text-theme-tertiary">Non-Compliant</p>
          <p className="text-3xl font-bold text-theme-error">{nonCompliantCount}</p>
        </Card>
      </div>

      {/* Matrix Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        {matrix.map((item) => (
          <ComplianceRow key={item.asi_reference} item={item} />
        ))}
      </div>
    </div>
  );
};

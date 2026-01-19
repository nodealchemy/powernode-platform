
import { CheckCircle2, XCircle, AlertTriangle, TrendingUp, Clock } from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';

export interface WorkflowHealthScoreProps {
  healthScore: number; // 0-100
  overallStatus: 'valid' | 'warnings' | 'errors';
  totalNodes: number;
  validatedNodes: number;
  validationDuration: number;
}

export const WorkflowHealthScore: React.FC<WorkflowHealthScoreProps> = ({
  healthScore,
  overallStatus,
  totalNodes,
  validatedNodes,
  validationDuration
}) => {
  const getHealthGrade = () => {
    if (healthScore >= 95) return { grade: 'A+', color: 'text-theme-success', bgColor: 'bg-theme-success' };
    if (healthScore >= 90) return { grade: 'A', color: 'text-theme-success', bgColor: 'bg-theme-success' };
    if (healthScore >= 85) return { grade: 'B+', color: 'text-theme-info', bgColor: 'bg-theme-info' };
    if (healthScore >= 80) return { grade: 'B', color: 'text-theme-info', bgColor: 'bg-theme-info' };
    if (healthScore >= 75) return { grade: 'C+', color: 'text-theme-warning', bgColor: 'bg-theme-warning' };
    if (healthScore >= 70) return { grade: 'C', color: 'text-theme-warning', bgColor: 'bg-theme-warning' };
    if (healthScore >= 60) return { grade: 'D', color: 'text-theme-error', bgColor: 'bg-theme-error' };
    return { grade: 'F', color: 'text-theme-error', bgColor: 'bg-theme-error' };
  };

  const getStatusIcon = () => {
    switch (overallStatus) {
      case 'valid':
        return <CheckCircle2 className="h-6 w-6 text-theme-success" />;
      case 'warnings':
        return <AlertTriangle className="h-6 w-6 text-theme-warning" />;
      case 'errors':
        return <XCircle className="h-6 w-6 text-theme-error" />;
      default:
        return <CheckCircle2 className="h-6 w-6 text-theme-tertiary" />;
    }
  };

  const getStatusBadge = () => {
    switch (overallStatus) {
      case 'valid':
        return <Badge variant="success" size="sm">Valid</Badge>;
      case 'warnings':
        return <Badge variant="warning" size="sm">Has Warnings</Badge>;
      case 'errors':
        return <Badge variant="danger" size="sm">Has Errors</Badge>;
      default:
        return <Badge variant="outline" size="sm">Unknown</Badge>;
    }
  };

  const healthGrade = getHealthGrade();

  const getHealthDescription = () => {
    if (healthScore >= 95) return 'Excellent workflow configuration';
    if (healthScore >= 85) return 'Good workflow configuration with minor suggestions';
    if (healthScore >= 75) return 'Fair configuration with some improvements needed';
    if (healthScore >= 60) return 'Poor configuration requires attention';
    return 'Critical issues must be addressed';
  };

  const getScoreColor = () => {
    if (healthScore >= 85) return 'text-theme-success';
    if (healthScore >= 70) return 'text-theme-warning';
    return 'text-theme-error';
  };

  const getProgressColor = () => {
    if (healthScore >= 85) return 'bg-theme-success';
    if (healthScore >= 70) return 'bg-theme-warning';
    return 'bg-theme-error';
  };

  return (
    <Card className="p-6">
      <div className="flex items-center justify-between mb-6">
        <div>
          <h3 className="text-lg font-semibold text-theme-primary mb-1">Workflow Health</h3>
          <p className="text-sm text-theme-secondary">{getHealthDescription()}</p>
        </div>
        <div className="flex items-center gap-3">
          {getStatusIcon()}
          {getStatusBadge()}
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-4 gap-6">
        {/* Health Score Circle */}
        <div className="flex flex-col items-center justify-center">
          <div className="relative w-32 h-32">
            {/* Background Circle */}
            <svg className="w-full h-full transform -rotate-90">
              <circle
                cx="64"
                cy="64"
                r="56"
                stroke="currentColor"
                strokeWidth="8"
                fill="none"
                className="text-theme-surface"
              />
              {/* Progress Circle */}
              <circle
                cx="64"
                cy="64"
                r="56"
                stroke="currentColor"
                strokeWidth="8"
                fill="none"
                strokeDasharray={`${2 * Math.PI * 56}`}
                strokeDashoffset={`${2 * Math.PI * 56 * (1 - healthScore / 100)}`}
                className={getScoreColor()}
                strokeLinecap="round"
              />
            </svg>
            {/* Score Text */}
            <div className="absolute inset-0 flex flex-col items-center justify-center">
              <p className={`text-3xl font-bold ${getScoreColor()}`}>{healthScore}</p>
              <p className="text-xs text-theme-tertiary">/ 100</p>
            </div>
          </div>
          <div className="mt-3 text-center">
            <p className={`text-2xl font-bold ${healthGrade.color}`}>{healthGrade.grade}</p>
            <p className="text-xs text-theme-tertiary">Grade</p>
          </div>
        </div>

        {/* Statistics */}
        <div className="md:col-span-3 grid grid-cols-1 md:grid-cols-3 gap-4">
          {/* Nodes Validated */}
          <div className="p-4 bg-theme-surface rounded-lg">
            <div className="flex items-center gap-2 mb-2">
              <CheckCircle2 className="h-4 w-4 text-theme-interactive-primary" />
              <p className="text-xs text-theme-tertiary">Nodes Validated</p>
            </div>
            <p className="text-2xl font-bold text-theme-primary">{validatedNodes}/{totalNodes}</p>
            <div className="mt-2 w-full bg-theme-surface rounded-full h-2">
              <div
                className="h-2 rounded-full bg-theme-interactive-primary transition-all"
                style={{ width: `${(validatedNodes / totalNodes) * 100}%` }}
              />
            </div>
          </div>

          {/* Validation Time */}
          <div className="p-4 bg-theme-surface rounded-lg">
            <div className="flex items-center gap-2 mb-2">
              <Clock className="h-4 w-4 text-theme-info" />
              <p className="text-xs text-theme-tertiary">Validation Time</p>
            </div>
            <p className="text-2xl font-bold text-theme-primary">{validationDuration}ms</p>
            <p className="text-xs text-theme-secondary mt-1">
              {validationDuration < 200 ? 'Very fast' :
               validationDuration < 500 ? 'Fast' :
               validationDuration < 1000 ? 'Normal' : 'Slow'}
            </p>
          </div>

          {/* Readiness */}
          <div className="p-4 bg-theme-surface rounded-lg">
            <div className="flex items-center gap-2 mb-2">
              <TrendingUp className="h-4 w-4 text-theme-success" />
              <p className="text-xs text-theme-tertiary">Production Ready</p>
            </div>
            <p className="text-2xl font-bold text-theme-primary">
              {overallStatus === 'valid' ? 'Yes' : overallStatus === 'errors' ? 'No' : 'Mostly'}
            </p>
            <p className="text-xs text-theme-secondary mt-1">
              {overallStatus === 'valid' ? 'Ready to deploy' :
               overallStatus === 'warnings' ? 'Review warnings first' :
               'Fix errors before deployment'}
            </p>
          </div>
        </div>
      </div>

      {/* Health Score Bar */}
      <div className="mt-6">
        <div className="flex items-center justify-between mb-2">
          <p className="text-sm text-theme-secondary">Overall Health Score</p>
          <p className={`text-sm font-medium ${getScoreColor()}`}>{healthScore}%</p>
        </div>
        <div className="w-full bg-theme-surface rounded-full h-3">
          <div
            className={`h-3 rounded-full ${getProgressColor()} transition-all duration-500`}
            style={{ width: `${healthScore}%` }}
          />
        </div>
        <div className="flex justify-between text-xs text-theme-tertiary mt-1">
          <span>0</span>
          <span>25</span>
          <span>50</span>
          <span>75</span>
          <span>100</span>
        </div>
      </div>
    </Card>
  );
};

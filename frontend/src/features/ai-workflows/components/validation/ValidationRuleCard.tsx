
import { CheckCircle2, XCircle, AlertTriangle, Info, Lightbulb, Zap, ChevronRight } from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { Checkbox } from '@/shared/components/ui/Checkbox';
import type { ValidationIssue } from '@/shared/types/workflow';

export interface ValidationRuleCardProps {
  issue: ValidationIssue;
  selected?: boolean;
  onToggleSelect?: () => void;
  onNavigateToNode?: (nodeId: string) => void;
}

export const ValidationRuleCard: React.FC<ValidationRuleCardProps> = ({
  issue,
  selected = false,
  onToggleSelect,
  onNavigateToNode
}) => {
  const getSeverityIcon = () => {
    switch (issue.severity) {
      case 'error':
        return <XCircle className="h-5 w-5 text-theme-error" />;
      case 'warning':
        return <AlertTriangle className="h-5 w-5 text-theme-warning" />;
      case 'info':
        return <Info className="h-5 w-5 text-theme-info" />;
      default:
        return <CheckCircle2 className="h-5 w-5 text-theme-tertiary" />;
    }
  };

  const getSeverityBadge = () => {
    switch (issue.severity) {
      case 'error':
        return <Badge variant="danger" size="sm">Error</Badge>;
      case 'warning':
        return <Badge variant="warning" size="sm">Warning</Badge>;
      case 'info':
        return <Badge variant="info" size="sm">Info</Badge>;
      default:
        return <Badge variant="outline" size="sm">Unknown</Badge>;
    }
  };

  const getCategoryBadge = () => {
    const colors: Record<ValidationIssue['category'], string> = {
      configuration: 'bg-theme-interactive-primary',
      connection: 'bg-theme-success',
      data_flow: 'bg-theme-info',
      performance: 'bg-theme-warning',
      security: 'bg-theme-error'
    };

    const color = colors[issue.category] || 'bg-theme-tertiary';

    return (
      <Badge variant="outline" size="sm" className={`${color} bg-opacity-10 capitalize`}>
        {issue.category.replace('_', ' ')}
      </Badge>
    );
  };

  const getNodeTypeBadge = () => {
    return (
      <Badge variant="outline" size="sm" className="capitalize">
        {issue.node_type.replace('_', ' ')}
      </Badge>
    );
  };

  return (
    <Card
      className={`p-5 transition-all ${
        selected ? 'ring-2 ring-theme-interactive-primary' : ''
      } ${
        issue.severity === 'error' ? 'border-theme-error' :
        issue.severity === 'warning' ? 'border-theme-warning' :
        'border-theme'
      }`}
    >
      {/* Header */}
      <div className="flex items-start gap-3 mb-4">
        {/* Selection Checkbox (only for auto-fixable issues) */}
        {issue.auto_fixable && onToggleSelect && (
          <div className="pt-1">
            <Checkbox
              id={`issue-${issue.id}`}
              checked={selected}
              onCheckedChange={onToggleSelect}
            />
          </div>
        )}

        {/* Severity Icon */}
        <div className={`flex-shrink-0 w-10 h-10 rounded-lg flex items-center justify-center ${
          issue.severity === 'error' ? 'bg-theme-error bg-opacity-10' :
          issue.severity === 'warning' ? 'bg-theme-warning bg-opacity-10' :
          'bg-theme-info bg-opacity-10'
        }`}>
          {getSeverityIcon()}
        </div>

        {/* Issue Content */}
        <div className="flex-1 min-w-0">
          {/* Title Row */}
          <div className="flex items-center gap-2 mb-2 flex-wrap">
            <h3 className="font-semibold text-theme-primary">{issue.rule_name}</h3>
            {getSeverityBadge()}
            {getCategoryBadge()}
            {issue.auto_fixable && (
              <Badge variant="success" size="sm" className="flex items-center gap-1">
                <Zap className="h-3 w-3" />
                Auto-fixable
              </Badge>
            )}
          </div>

          {/* Node Info */}
          <div className="flex items-center gap-2 mb-3 text-sm">
            <span className="text-theme-tertiary">Node:</span>
            <span className="font-medium text-theme-primary">{issue.node_name}</span>
            {getNodeTypeBadge()}
            {onNavigateToNode && (
              <button
                onClick={() => onNavigateToNode(issue.node_id)}
                className="text-theme-interactive-primary hover:underline flex items-center gap-1 ml-auto"
              >
                Go to node
                <ChevronRight className="h-4 w-4" />
              </button>
            )}
          </div>

          {/* Message */}
          <p className="text-theme-primary mb-2">{issue.message}</p>

          {/* Description */}
          {issue.description && (
            <p className="text-sm text-theme-secondary mb-3">{issue.description}</p>
          )}

          {/* Suggestion */}
          {issue.suggestion && (
            <div className="mt-3 p-3 bg-theme-info bg-opacity-5 border border-theme-info rounded-lg">
              <div className="flex items-start gap-2">
                <Lightbulb className="h-4 w-4 text-theme-info flex-shrink-0 mt-0.5" />
                <div>
                  <p className="text-xs font-medium text-theme-info mb-1">Suggestion</p>
                  <p className="text-sm text-theme-primary">{issue.suggestion}</p>
                </div>
              </div>
            </div>
          )}

          {/* Metadata */}
          {issue.metadata && Object.keys(issue.metadata).length > 0 && (
            <div className="mt-3 pt-3 border-t border-theme">
              <p className="text-xs text-theme-tertiary mb-2">Additional Details:</p>
              <div className="text-xs text-theme-secondary space-y-1">
                {Object.entries(issue.metadata).map(([key, value]) => (
                  <div key={key} className="flex justify-between">
                    <span className="capitalize">{key.replace('_', ' ')}:</span>
                    <span className="font-medium text-theme-primary">
                      {typeof value === 'boolean' ? (value ? 'Yes' : 'No') : String(value)}
                    </span>
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>
      </div>
    </Card>
  );
};

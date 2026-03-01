import { useState } from 'react';
import { AlertTriangle, Merge, Trash2, Eye, Check, X } from 'lucide-react';
import { Badge } from '@/shared/components/ui/Badge';
import { Card } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { skillLifecycleApi } from '../services/skillLifecycleApi';
import { useNotifications } from '@/shared/hooks/useNotifications';
import type { SkillConflict, ConflictSeverity, ConflictType } from '../types/lifecycle';

interface ConsolidationSuggestionCardProps {
  conflict: SkillConflict;
  onResolved: () => void;
}

const SEVERITY_VARIANTS: Record<ConflictSeverity, 'danger' | 'warning' | 'info' | 'default'> = {
  critical: 'danger',
  high: 'warning',
  medium: 'info',
  low: 'default',
};

const TYPE_LABELS: Record<ConflictType, string> = {
  duplicate: 'Duplicate',
  overlapping: 'Overlapping',
  circular_dependency: 'Circular Dep',
  stale: 'Stale',
  orphan: 'Orphan',
  version_drift: 'Version Drift',
};

const TYPE_ICONS: Record<ConflictType, typeof Merge> = {
  duplicate: Merge,
  overlapping: Eye,
  circular_dependency: AlertTriangle,
  stale: Trash2,
  orphan: AlertTriangle,
  version_drift: AlertTriangle,
};

export function ConsolidationSuggestionCard({ conflict, onResolved }: ConsolidationSuggestionCardProps) {
  const { showNotification } = useNotifications();
  const [acting, setActing] = useState(false);

  const Icon = TYPE_ICONS[conflict.conflict_type] || AlertTriangle;

  const handleResolve = async () => {
    setActing(true);
    const response = await skillLifecycleApi.resolveConflict(conflict.id, conflict.resolution_strategy || undefined);
    if (response.success) {
      showNotification('Conflict resolved', 'success');
      onResolved();
    } else {
      showNotification(response.error || 'Failed to resolve', 'error');
    }
    setActing(false);
  };

  const handleDismiss = async () => {
    setActing(true);
    const response = await skillLifecycleApi.dismissConflict(conflict.id);
    if (response.success) {
      showNotification('Conflict dismissed', 'success');
      onResolved();
    } else {
      showNotification(response.error || 'Failed to dismiss', 'error');
    }
    setActing(false);
  };

  return (
    <Card variant="outlined" padding="sm" data-testid={`conflict-card-${conflict.id}`}>
      <div className="flex items-start gap-3">
        <Icon className="w-5 h-5 text-theme-secondary flex-shrink-0 mt-0.5" />
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 mb-1">
            <Badge variant={SEVERITY_VARIANTS[conflict.severity]} size="xs">
              {conflict.severity}
            </Badge>
            <Badge variant="secondary" size="xs">
              {TYPE_LABELS[conflict.conflict_type]}
            </Badge>
            {conflict.auto_resolvable && (
              <Badge variant="info" size="xs">Auto-resolvable</Badge>
            )}
          </div>

          <div className="text-sm text-theme-primary mb-1">
            <span className="font-medium">{conflict.skill_a.name}</span>
            {conflict.skill_b && (
              <>
                <span className="text-theme-tertiary mx-1">&harr;</span>
                <span className="font-medium">{conflict.skill_b.name}</span>
              </>
            )}
          </div>

          {conflict.similarity_score != null && (
            <p className="text-xs text-theme-tertiary mb-1">
              Similarity: {Math.round(conflict.similarity_score * 100)}%
            </p>
          )}

          {conflict.resolution_strategy && (
            <p className="text-xs text-theme-secondary">
              Suggested: <span className="capitalize">{conflict.resolution_strategy.replace(/_/g, ' ')}</span>
            </p>
          )}

          <div className="flex gap-2 mt-2">
            <Button size="sm" variant="primary" onClick={handleResolve} disabled={acting}>
              <Check className="w-3 h-3 mr-1" />
              Resolve
            </Button>
            <Button size="sm" variant="ghost" onClick={handleDismiss} disabled={acting}>
              <X className="w-3 h-3 mr-1" />
              Dismiss
            </Button>
          </div>
        </div>
      </div>
    </Card>
  );
}

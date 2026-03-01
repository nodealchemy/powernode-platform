import React, { useState, useEffect } from 'react';
import { History, TrendingUp, TrendingDown, RefreshCw, ExternalLink } from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { validationApi } from '@/shared/services/ai';
import { useNotifications } from '@/shared/hooks/useNotifications';

interface ValidationHistoryItem {
  id: string;
  workflow_id: string;
  health_score: number;
  overall_status: string;
  issues_count: number;
  validated_at: string;
}

interface ValidationHistoryPanelProps {
  workflowId: string;
  onCompare?: (validation1Id: string, validation2Id: string) => void;
}

export const ValidationHistoryPanel: React.FC<ValidationHistoryPanelProps> = ({
  workflowId,
  onCompare
}) => {
  const [history, setHistory] = useState<ValidationHistoryItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [selectedValidations, setSelectedValidations] = useState<Set<string>>(new Set());
  const { addNotification } = useNotifications();

   
  useEffect(() => {
    loadHistory();
  }, [workflowId]);

  const loadHistory = async () => {
    try {
      setLoading(true);
      const response = await validationApi.getValidationHistory(workflowId, 20);
      setHistory(response.validations);
    } catch (_error) {
      addNotification({
        type: 'error',
        title: 'Failed to Load History',
        message: 'Could not load validation history'
      });
    } finally {
      setLoading(false);
    }
  };

  const toggleSelection = (validationId: string) => {
    const newSelection = new Set(selectedValidations);
    if (newSelection.has(validationId)) {
      newSelection.delete(validationId);
    } else {
      if (newSelection.size >= 2) {
        const firstId = Array.from(newSelection)[0];
        newSelection.delete(firstId);
      }
      newSelection.add(validationId);
    }
    setSelectedValidations(newSelection);
  };

  const handleCompare = () => {
    if (selectedValidations.size === 2 && onCompare) {
      const [id1, id2] = Array.from(selectedValidations);
      onCompare(id1, id2);
    }
  };

  const getHealthScoreColor = (score: number) => {
    if (score >= 90) return 'text-theme-success';
    if (score >= 70) return 'text-theme-info';
    if (score >= 50) return 'text-theme-warning';
    return 'text-theme-error';
  };

  const calculateTrend = (current: ValidationHistoryItem, previous: ValidationHistoryItem | undefined) => {
    if (!previous) return null;
    const diff = current.health_score - previous.health_score;
    if (diff > 0) return { direction: 'up', value: diff };
    if (diff < 0) return { direction: 'down', value: Math.abs(diff) };
    return { direction: 'stable', value: 0 };
  };

  const formatDate = (dateString: string) => {
    const date = new Date(dateString);
    const now = new Date();
    const diffMs = now.getTime() - date.getTime();
    const diffDays = Math.floor(diffMs / (1000 * 60 * 60 * 24));

    if (diffDays === 0) return 'Today';
    if (diffDays === 1) return 'Yesterday';
    if (diffDays < 7) return `${diffDays} days ago`;
    return date.toLocaleDateString();
  };

  if (loading) {
    return (
      <Card className="p-8 text-center">
        <RefreshCw className="h-8 w-8 animate-spin text-theme-interactive-primary mx-auto mb-4" />
        <p className="text-theme-secondary">Loading validation history...</p>
      </Card>
    );
  }

  if (history.length === 0) {
    return (
      <Card className="p-8 text-center">
        <History className="h-12 w-12 text-theme-tertiary mx-auto mb-4 opacity-50" />
        <p className="text-theme-secondary mb-2">No validation history</p>
        <p className="text-theme-tertiary text-sm">
          Run a validation to start tracking workflow health
        </p>
      </Card>
    );
  }

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <History className="h-5 w-5 text-theme-primary" />
          <h3 className="text-lg font-semibold text-theme-primary">Validation History</h3>
          <Badge variant="secondary">{history.length} validations</Badge>
        </div>
        {selectedValidations.size === 2 && (
          <Button onClick={handleCompare} size="sm" className="flex items-center gap-2">
            <ExternalLink className="h-4 w-4" />
            Compare Selected
          </Button>
        )}
      </div>

      {/* Timeline */}
      <div className="space-y-3">
        {history.map((validation, index) => {
          const trend = calculateTrend(validation, history[index + 1]);
          const isSelected = selectedValidations.has(validation.id);

          return (
            <Card
              key={validation.id}
              className={`p-4 cursor-pointer transition-all hover:shadow-md ${
                isSelected ? 'ring-2 ring-theme-interactive-primary' : ''
              }`}
              onClick={() => toggleSelection(validation.id)}
            >
              <div className="flex items-center gap-4">
                {/* Health Score Circle */}
                <div className="flex-shrink-0">
                  <div className="relative w-16 h-16">
                    <svg className="transform -rotate-90 w-16 h-16">
                      <circle
                        cx="32"
                        cy="32"
                        r="28"
                        stroke="currentColor"
                        strokeWidth="4"
                        fill="none"
                        className="text-theme-surface-secondary"
                      />
                      <circle
                        cx="32"
                        cy="32"
                        r="28"
                        stroke="currentColor"
                        strokeWidth="4"
                        fill="none"
                        strokeDasharray={`${2 * Math.PI * 28}`}
                        strokeDashoffset={`${2 * Math.PI * 28 * (1 - validation.health_score / 100)}`}
                        className={getHealthScoreColor(validation.health_score)}
                        strokeLinecap="round"
                      />
                    </svg>
                    <div className="absolute inset-0 flex items-center justify-center">
                      <span className={`text-sm font-bold ${getHealthScoreColor(validation.health_score)}`}>
                        {validation.health_score}
                      </span>
                    </div>
                  </div>
                </div>

                {/* Validation Info */}
                <div className="flex-1">
                  <div className="flex items-center gap-2 mb-1">
                    <p className="text-sm text-theme-tertiary">
                      {formatDate(validation.validated_at)}
                    </p>
                    <Badge
                      variant={
                        validation.overall_status === 'valid'
                          ? 'success'
                          : validation.overall_status === 'invalid'
                          ? 'danger'
                          : 'warning'
                      }
                      size="sm"
                    >
                      {validation.overall_status}
                    </Badge>
                  </div>
                  <p className="text-sm text-theme-secondary">
                    {validation.issues_count} {validation.issues_count === 1 ? 'issue' : 'issues'} found
                  </p>
                </div>

                {/* Trend Indicator */}
                {trend && (
                  <div className="flex-shrink-0 text-right">
                    {trend.direction === 'up' && (
                      <div className="flex items-center gap-1 text-theme-success">
                        <TrendingUp className="h-4 w-4" />
                        <span className="text-sm font-medium">+{trend.value}</span>
                      </div>
                    )}
                    {trend.direction === 'down' && (
                      <div className="flex items-center gap-1 text-theme-error">
                        <TrendingDown className="h-4 w-4" />
                        <span className="text-sm font-medium">-{trend.value}</span>
                      </div>
                    )}
                    {trend.direction === 'stable' && (
                      <div className="text-theme-tertiary">
                        <span className="text-sm">No change</span>
                      </div>
                    )}
                  </div>
                )}
              </div>
            </Card>
          );
        })}
      </div>

      {/* Selection Help Text */}
      {selectedValidations.size > 0 && (
        <p className="text-xs text-theme-tertiary text-center">
          {selectedValidations.size === 1
            ? 'Select one more validation to compare'
            : 'Click "Compare Selected" to see differences'}
        </p>
      )}
    </div>
  );
};

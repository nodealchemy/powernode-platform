// Review Panel - Review findings, actions, and completeness checks
import React, { useState } from 'react';
import {
  CheckCircle, XCircle, AlertTriangle, Info, RefreshCw,
  Shield, Clock, BarChart3
} from 'lucide-react';
import teamsApi from '@/shared/services/ai/TeamsApiService';
import type { TaskReview } from '@/shared/services/ai/TeamsApiService';

interface ReviewPanelProps {
  review: TaskReview;
  taskTitle?: string;
  maxRevisions?: number;
  onReviewProcessed?: (review: TaskReview) => void;
}

const SEVERITY_CONFIG: Record<string, { icon: React.ReactNode; color: string; label: string }> = {
  error: {
    icon: <XCircle size={14} />,
    color: 'border-theme-danger/30 bg-theme-error/5 text-theme-danger',
    label: 'ERROR',
  },
  warning: {
    icon: <AlertTriangle size={14} />,
    color: 'border-theme-warning/30 bg-theme-warning/5 text-theme-warning',
    label: 'WARN',
  },
  info: {
    icon: <Info size={14} />,
    color: 'border-theme-info/30 bg-theme-info/5 text-theme-info',
    label: 'INFO',
  },
};

const STATUS_BADGES: Record<string, { color: string; label: string }> = {
  pending: { color: 'bg-theme-accent text-theme-secondary', label: 'Pending' },
  in_progress: { color: 'bg-theme-info/10 text-theme-info', label: 'In Review' },
  approved: { color: 'bg-theme-success/10 text-theme-success', label: 'Approved' },
  rejected: { color: 'bg-theme-error/10 text-theme-danger', label: 'Rejected' },
  revision_requested: { color: 'bg-theme-warning/10 text-theme-warning', label: 'Revision Requested' },
};

export const ReviewPanel: React.FC<ReviewPanelProps> = ({
  review,
  taskTitle,
  maxRevisions = 3,
  onReviewProcessed
}) => {
  const [notes, setNotes] = useState('');
  const [processing, setProcessing] = useState(false);

  const handleAction = async (action: 'approve' | 'reject' | 'revision') => {
    setProcessing(true);
    try {
      const updated = await teamsApi.processReview(review.review_id, action, notes || undefined);
      onReviewProcessed?.(updated);
    } catch {
      // Error handled by API service
    } finally {
      setProcessing(false);
    }
  };

  const isActionable = review.status === 'pending' || review.status === 'in_progress';
  const statusBadge = STATUS_BADGES[review.status] || STATUS_BADGES.pending;
  const qualityThreshold = 0.7;
  const qualityPercent = (review.quality_score || 0) * 100;

  // Sort findings by severity
  const sortedFindings = [...(review.findings || [])].sort((a, b) => {
    const order: Record<string, number> = { error: 0, warning: 1, info: 2 };
    return (order[a.severity] ?? 3) - (order[b.severity] ?? 3);
  });

  return (
    <div className="bg-theme-surface border border-theme rounded-lg" data-testid="review-panel">
      {/* Header */}
      <div className="p-4 border-b border-theme">
        <div className="flex items-center justify-between mb-2">
          <div className="flex items-center gap-2">
            <Shield size={18} className="text-theme-primary" />
            <h3 className="text-sm font-semibold text-theme-primary">
              Review{taskTitle ? `: ${taskTitle}` : ''}
            </h3>
          </div>
          <span className={`px-2 py-0.5 text-xs font-medium rounded-full ${statusBadge.color}`}>
            {statusBadge.label}
          </span>
        </div>

        <div className="flex items-center gap-4 text-xs text-theme-secondary">
          <span className={`px-1.5 py-0.5 rounded ${
            review.review_mode === 'blocking'
              ? 'bg-theme-danger/10 text-theme-danger'
              : 'bg-theme-info/10 text-theme-info'
          }`}>
            {review.review_mode === 'blocking' ? 'Blocking' : 'Shadow'}
          </span>

          {review.revision_count > 0 && (
            <span className="flex items-center gap-1">
              <RefreshCw size={10} />
              Revision {review.revision_count}/{maxRevisions}
            </span>
          )}

          {review.review_duration_ms && (
            <span className="flex items-center gap-1">
              <Clock size={10} />
              {Math.round(review.review_duration_ms / 1000)}s
            </span>
          )}
        </div>
      </div>

      {/* Quality Score */}
      <div className="px-4 py-3 border-b border-theme">
        <div className="flex items-center justify-between text-xs text-theme-secondary mb-1">
          <span className="flex items-center gap-1">
            <BarChart3 size={12} />
            Quality Score
          </span>
          <span className={qualityPercent >= qualityThreshold * 100 ? 'text-theme-success' : 'text-theme-danger'}>
            {review.quality_score !== null && review.quality_score !== undefined
              ? review.quality_score.toFixed(2)
              : 'N/A'}
          </span>
        </div>
        {review.quality_score !== null && review.quality_score !== undefined && (
          <div className="w-full bg-theme-accent rounded-full h-2 relative">
            {/* Threshold marker */}
            <div
              className="absolute top-0 bottom-0 w-0.5 bg-theme-secondary"
              style={{ left: `${qualityThreshold * 100}%` }}
            />
            <div
              className={`h-2 rounded-full transition-all ${
                qualityPercent >= qualityThreshold * 100 ? 'bg-theme-success' : 'bg-theme-danger-solid'
              }`}
              style={{ width: `${Math.min(qualityPercent, 100)}%` }}
            />
          </div>
        )}
      </div>

      {/* Completeness Checks */}
      {review.completeness_checks && Object.keys(review.completeness_checks).length > 0 && (
        <div className="px-4 py-3 border-b border-theme" data-testid="completeness-checks">
          <h4 className="text-xs font-medium text-theme-secondary mb-2">Completeness Checks</h4>
          <div className="space-y-1">
            {Object.entries(review.completeness_checks).map(([key, value]) => {
              if (key === 'completeness_score') return null;
              const passed = !value;
              const label = key.replace(/^has_/, '').replace(/_/g, ' ');
              return (
                <div key={key} className="flex items-center gap-2 text-xs">
                  {passed ? (
                    <CheckCircle size={14} className="text-theme-success" />
                  ) : (
                    <XCircle size={14} className="text-theme-danger" />
                  )}
                  <span className={passed ? 'text-theme-secondary' : 'text-theme-danger'}>
                    {passed ? `No ${label}` : `${label.charAt(0).toUpperCase() + label.slice(1)} found`}
                  </span>
                </div>
              );
            })}
          </div>
        </div>
      )}

      {/* Findings */}
      {sortedFindings.length > 0 && (
        <div className="px-4 py-3 border-b border-theme" data-testid="review-findings">
          <h4 className="text-xs font-medium text-theme-secondary mb-2">
            Findings ({sortedFindings.length})
          </h4>
          <div className="space-y-2">
            {sortedFindings.map((finding, idx) => {
              const config = SEVERITY_CONFIG[finding.severity] || SEVERITY_CONFIG.info;
              return (
                <div key={idx} className={`p-3 rounded-md border ${config.color}`}>
                  <div className="flex items-center gap-2 mb-1">
                    {config.icon}
                    <span className="text-xs font-medium">{config.label}: {finding.category}</span>
                  </div>
                  <p className="text-xs opacity-80">{finding.description}</p>
                  {finding.suggestion && (
                    <p className="text-xs opacity-60 mt-1 italic">
                      Suggestion: {finding.suggestion}
                    </p>
                  )}
                </div>
              );
            })}
          </div>
        </div>
      )}

      {/* Notes & Actions */}
      {isActionable && (
        <div className="p-4 space-y-3">
          <textarea
            value={notes}
            onChange={(e) => setNotes(e.target.value)}
            placeholder="Add review notes..."
            rows={2}
            className="w-full px-3 py-2 text-sm border border-theme rounded-md bg-theme-surface text-theme-primary placeholder-theme-secondary focus:outline-none focus:ring-2 focus:ring-theme-primary"
          />

          <div className="flex gap-2">
            <button
              type="button"
              onClick={() => handleAction('approve')}
              disabled={processing}
              className="flex items-center gap-1 px-3 py-2 text-sm font-medium text-theme-success bg-theme-success/10 rounded-md hover:bg-theme-success/20 transition-colors disabled:opacity-50"
            >
              <CheckCircle size={14} />
              Approve
            </button>

            <button
              type="button"
              onClick={() => handleAction('revision')}
              disabled={processing}
              className="flex items-center gap-1 px-3 py-2 text-sm font-medium text-theme-warning bg-theme-warning/10 rounded-md hover:bg-theme-warning/20 transition-colors disabled:opacity-50"
            >
              <RefreshCw size={14} />
              Request Revision
            </button>

            <button
              type="button"
              onClick={() => handleAction('reject')}
              disabled={processing}
              className="flex items-center gap-1 px-3 py-2 text-sm font-medium text-theme-danger bg-theme-error/10 rounded-md hover:bg-theme-error/20 transition-colors disabled:opacity-50"
            >
              <XCircle size={14} />
              Reject
            </button>
          </div>
        </div>
      )}

      {/* Approval/Rejection Notes */}
      {review.approval_notes && review.status === 'approved' && (
        <div className="px-4 pb-4">
          <p className="text-xs text-theme-success italic">Notes: {review.approval_notes}</p>
        </div>
      )}
      {review.rejection_reason && (review.status === 'rejected' || review.status === 'revision_requested') && (
        <div className="px-4 pb-4">
          <p className="text-xs text-theme-danger italic">Reason: {review.rejection_reason}</p>
        </div>
      )}
    </div>
  );
};

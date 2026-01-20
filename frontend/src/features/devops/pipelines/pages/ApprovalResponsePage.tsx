import React, { useState, useEffect } from 'react';
import { useParams, useNavigate, useSearchParams } from 'react-router-dom';
import { CheckCircle, XCircle, Clock, AlertTriangle, Loader2, ExternalLink, MessageSquare } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { apiClient } from '@/shared/services/apiClient';
import { useNotifications } from '@/shared/hooks/useNotifications';

interface ApprovalDetails {
  step_name: string;
  pipeline_name: string;
  run_number: string;
  trigger_type: string;
  trigger_context: Record<string, unknown>;
  status: string;
  expires_at: string;
  time_remaining_seconds: number;
  requires_comment: boolean;
  step_configuration: {
    step_type: string;
    description?: string;
  };
}

type ApprovalAction = 'approve' | 'reject' | null;

export const ApprovalResponsePage: React.FC = () => {
  const { token } = useParams<{ token: string }>();
  const [searchParams] = useSearchParams();
  const navigate = useNavigate();
  const { addNotification } = useNotifications();

  const [loading, setLoading] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  const [details, setDetails] = useState<ApprovalDetails | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [comment, setComment] = useState('');
  const [completed, setCompleted] = useState<ApprovalAction>(null);

  // Determine if this is a direct approve/reject link
  const action = searchParams.get('action') as ApprovalAction;

  useEffect(() => {
    fetchApprovalDetails();
  }, [token]);

  const fetchApprovalDetails = async () => {
    if (!token) {
      setError('Invalid approval link');
      setLoading(false);
      return;
    }

    try {
      const response = await apiClient.get<{ success: boolean; data?: ApprovalDetails; error?: string }>(
        `/api/v1/devops/step_approvals/${token}`
      );
      const result = response.data;

      if (result.success && result.data) {
        setDetails(result.data);

        // If direct action link and no comment required, auto-submit
        if (action && !result.data.requires_comment) {
          handleSubmit(action);
        }
      } else {
        setError(result.error || 'Failed to load approval details');
      }
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : 'Failed to load approval details';
      setError(errorMessage);
    } finally {
      setLoading(false);
    }
  };

  const handleSubmit = async (approvalAction: ApprovalAction) => {
    if (!token || !approvalAction) return;

    // Check if comment is required
    if (details?.requires_comment && !comment.trim()) {
      addNotification({
        type: 'error',
        title: 'Comment Required',
        message: 'Please provide a comment explaining your decision.',
      });
      return;
    }

    setSubmitting(true);

    try {
      const response = await apiClient.post<{ success: boolean; data?: { message?: string }; error?: string }>(
        `/api/v1/devops/step_approvals/${token}/${approvalAction}`,
        { comment: comment.trim() || undefined }
      );
      const result = response.data;

      if (result.success) {
        setCompleted(approvalAction);
        addNotification({
          type: 'success',
          title: approvalAction === 'approve' ? 'Step Approved' : 'Step Rejected',
          message: result.data?.message || `The step has been ${approvalAction}d.`,
        });
      } else {
        setError(result.error || `Failed to ${approvalAction} step`);
      }
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : `Failed to ${approvalAction} step`;
      setError(errorMessage);
    } finally {
      setSubmitting(false);
    }
  };

  const formatTimeRemaining = (seconds: number): string => {
    if (seconds <= 0) return 'Expired';

    const hours = Math.floor(seconds / 3600);
    const minutes = Math.floor((seconds % 3600) / 60);

    if (hours > 24) {
      const days = Math.floor(hours / 24);
      return `${days} day${days > 1 ? 's' : ''} remaining`;
    }

    if (hours > 0) {
      return `${hours}h ${minutes}m remaining`;
    }

    return `${minutes} minute${minutes !== 1 ? 's' : ''} remaining`;
  };

  const formatTriggerContext = (type: string, context: Record<string, unknown>): string => {
    switch (type) {
      case 'pull_request':
        return `Pull Request #${context.pull_request_number || context.pr_number}`;
      case 'push':
        return `Push to ${context.branch || context.ref}`;
      case 'manual':
        return 'Manual trigger';
      case 'schedule':
        return 'Scheduled run';
      default:
        return type.replace(/_/g, ' ');
    }
  };

  if (loading) {
    return (
      <div className="min-h-screen bg-theme-background flex items-center justify-center">
        <div className="text-center">
          <LoadingSpinner size="lg" />
          <p className="mt-4 text-theme-secondary">Loading approval details...</p>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="min-h-screen bg-theme-background flex items-center justify-center p-4">
        <div className="max-w-md w-full bg-theme-surface rounded-xl shadow-lg border border-theme p-8 text-center">
          <AlertTriangle className="w-16 h-16 text-theme-error mx-auto mb-4" />
          <h1 className="text-xl font-semibold text-theme-primary mb-2">
            Unable to Process Request
          </h1>
          <p className="text-theme-secondary mb-6">{error}</p>
          <Button onClick={() => navigate('/app/devops/pipelines')} variant="primary">
            Go to Dashboard
          </Button>
        </div>
      </div>
    );
  }

  if (completed) {
    return (
      <div className="min-h-screen bg-theme-background flex items-center justify-center p-4">
        <div className="max-w-md w-full bg-theme-surface rounded-xl shadow-lg border border-theme p-8 text-center">
          {completed === 'approve' ? (
            <CheckCircle className="w-16 h-16 text-theme-success mx-auto mb-4" />
          ) : (
            <XCircle className="w-16 h-16 text-theme-error mx-auto mb-4" />
          )}
          <h1 className="text-xl font-semibold text-theme-primary mb-2">
            {completed === 'approve' ? 'Step Approved' : 'Step Rejected'}
          </h1>
          <p className="text-theme-secondary mb-6">
            {completed === 'approve'
              ? 'The pipeline step has been approved and will continue execution.'
              : 'The pipeline step has been rejected and the pipeline will fail.'}
          </p>
          <Button onClick={() => navigate('/app/devops/pipelines')} variant="primary">
            View Pipeline Runs
          </Button>
        </div>
      </div>
    );
  }

  if (!details) return null;

  const isExpired = details.time_remaining_seconds <= 0;

  return (
    <div className="min-h-screen bg-theme-background flex items-center justify-center p-4">
      <div className="max-w-lg w-full bg-theme-surface rounded-xl shadow-lg border border-theme overflow-hidden">
        {/* Header */}
        <div className="bg-gradient-to-r from-indigo-600 to-purple-600 p-6 text-white">
          <h1 className="text-xl font-semibold mb-1">Pipeline Approval Required</h1>
          <p className="text-white/80 text-sm">
            Review and respond to this request
          </p>
        </div>

        {/* Details */}
        <div className="p-6 space-y-4">
          <div className="grid grid-cols-2 gap-4">
            <div>
              <p className="text-xs text-theme-tertiary uppercase tracking-wide">Pipeline</p>
              <p className="text-sm font-medium text-theme-primary">{details.pipeline_name}</p>
            </div>
            <div>
              <p className="text-xs text-theme-tertiary uppercase tracking-wide">Step</p>
              <p className="text-sm font-medium text-theme-primary">{details.step_name}</p>
            </div>
            <div>
              <p className="text-xs text-theme-tertiary uppercase tracking-wide">Run Number</p>
              <p className="text-sm font-medium text-theme-primary">{details.run_number}</p>
            </div>
            <div>
              <p className="text-xs text-theme-tertiary uppercase tracking-wide">Trigger</p>
              <p className="text-sm font-medium text-theme-primary">
                {formatTriggerContext(details.trigger_type, details.trigger_context)}
              </p>
            </div>
          </div>

          {details.step_configuration.description && (
            <div className="bg-theme-warning/10 border-l-4 border-theme-warning rounded-r px-4 py-3">
              <p className="text-sm text-theme-primary">
                <strong>Description:</strong> {details.step_configuration.description}
              </p>
            </div>
          )}

          {/* Time remaining */}
          <div className={`flex items-center gap-2 ${isExpired ? 'text-theme-error' : 'text-theme-secondary'}`}>
            <Clock className="w-4 h-4" />
            <span className="text-sm">
              {isExpired ? 'This approval request has expired' : formatTimeRemaining(details.time_remaining_seconds)}
            </span>
          </div>

          {/* Comment field */}
          {!isExpired && (
            <div>
              <label className="flex items-center gap-2 text-sm font-medium text-theme-secondary mb-2">
                <MessageSquare className="w-4 h-4" />
                Comment {details.requires_comment && <span className="text-theme-error">*</span>}
              </label>
              <textarea
                value={comment}
                onChange={(e) => setComment(e.target.value)}
                placeholder={details.requires_comment ? 'A comment is required...' : 'Add an optional comment...'}
                className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary text-sm focus:outline-none focus:ring-2 focus:ring-theme-primary resize-none"
                rows={3}
              />
            </div>
          )}

          {/* Action buttons */}
          {!isExpired && (
            <div className="flex gap-3 pt-2">
              <Button
                onClick={() => handleSubmit('approve')}
                variant="primary"
                className="flex-1 bg-theme-success hover:bg-theme-success/90"
                disabled={submitting}
              >
                {submitting ? (
                  <Loader2 className="w-4 h-4 mr-2 animate-spin" />
                ) : (
                  <CheckCircle className="w-4 h-4 mr-2" />
                )}
                Approve
              </Button>
              <Button
                onClick={() => handleSubmit('reject')}
                variant="primary"
                className="flex-1 bg-theme-error hover:bg-theme-error/90"
                disabled={submitting}
              >
                {submitting ? (
                  <Loader2 className="w-4 h-4 mr-2 animate-spin" />
                ) : (
                  <XCircle className="w-4 h-4 mr-2" />
                )}
                Reject
              </Button>
            </div>
          )}

          {isExpired && (
            <div className="pt-2">
              <Button
                onClick={() => navigate('/app/devops/pipelines')}
                variant="primary"
                className="w-full"
              >
                <ExternalLink className="w-4 h-4 mr-2" />
                View in Dashboard
              </Button>
            </div>
          )}
        </div>

        {/* Footer */}
        <div className="px-6 py-4 bg-theme-surface-elevated border-t border-theme text-center">
          <p className="text-xs text-theme-tertiary">
            Powernode Platform - DevOps Pipeline Approval
          </p>
        </div>
      </div>
    </div>
  );
};

export default ApprovalResponsePage;

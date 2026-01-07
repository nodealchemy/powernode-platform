import React, { useState, useEffect } from 'react';
import { useParams, useNavigate, useSearchParams } from 'react-router-dom';
import { CheckCircle, XCircle, Clock, AlertTriangle, Loader2, ExternalLink, MessageSquare, Workflow } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { apiClient } from '@/shared/services/apiClient';
import { useNotifications } from '@/shared/hooks/useNotifications';

interface ApprovalDetails {
  node_name: string;
  workflow_name: string;
  run_id: string;
  trigger_type: string;
  status: string;
  expires_at: string;
  time_remaining_seconds: number;
  requires_comment: boolean;
  approval_message?: string;
  node_configuration: {
    node_type: string;
  };
  workflow: {
    id: string;
    name: string;
  };
  workflow_run: {
    id: string;
    run_id: string;
    status: string;
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
        `/api/v1/ai_workflows/approval_tokens/${token}`
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
        `/api/v1/ai_workflows/approval_tokens/${token}/${approvalAction}`,
        { comment: comment.trim() || undefined }
      );
      const result = response.data;

      if (result.success) {
        setCompleted(approvalAction);
        addNotification({
          type: 'success',
          title: approvalAction === 'approve' ? 'Node Approved' : 'Node Rejected',
          message: result.data?.message || `The workflow step has been ${approvalAction}d.`,
        });
      } else {
        setError(result.error || `Failed to ${approvalAction} workflow step`);
      }
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : `Failed to ${approvalAction} workflow step`;
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

  const formatTriggerType = (type: string): string => {
    switch (type) {
      case 'manual':
        return 'Manual trigger';
      case 'schedule':
        return 'Scheduled run';
      case 'webhook':
        return 'Webhook trigger';
      case 'api':
        return 'API trigger';
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
          <Button onClick={() => navigate('/app/ai/workflows')} variant="primary">
            Go to Workflows
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
              ? 'The workflow step has been approved and will continue execution.'
              : 'The workflow step has been rejected and the workflow will fail.'}
          </p>
          {details?.workflow?.id && details?.workflow_run?.id && (
            <Button
              onClick={() => navigate(`/app/ai/workflows/${details.workflow.id}/runs/${details.workflow_run.id}`)}
              variant="primary"
            >
              View Workflow Run
            </Button>
          )}
        </div>
      </div>
    );
  }

  if (!details) return null;

  const isExpired = details.time_remaining_seconds <= 0;

  return (
    <div className="min-h-screen bg-theme-background flex items-center justify-center p-4">
      <div className="max-w-lg w-full bg-theme-surface rounded-xl shadow-lg border border-theme overflow-hidden">
        {/* Header - Purple gradient for AI Workflows */}
        <div className="bg-gradient-to-r from-purple-600 to-violet-600 p-6 text-white">
          <div className="flex items-center gap-3 mb-1">
            <Workflow className="w-6 h-6" />
            <h1 className="text-xl font-semibold">AI Workflow Approval Required</h1>
          </div>
          <p className="text-white/80 text-sm">
            Review and respond to this request
          </p>
        </div>

        {/* Details */}
        <div className="p-6 space-y-4">
          <div className="grid grid-cols-2 gap-4">
            <div>
              <p className="text-xs text-theme-tertiary uppercase tracking-wide">Workflow</p>
              <p className="text-sm font-medium text-theme-primary">{details.workflow_name}</p>
            </div>
            <div>
              <p className="text-xs text-theme-tertiary uppercase tracking-wide">Step</p>
              <p className="text-sm font-medium text-theme-primary">{details.node_name}</p>
            </div>
            <div>
              <p className="text-xs text-theme-tertiary uppercase tracking-wide">Run ID</p>
              <p className="text-sm font-medium text-theme-primary font-mono text-xs">{details.run_id}</p>
            </div>
            <div>
              <p className="text-xs text-theme-tertiary uppercase tracking-wide">Trigger</p>
              <p className="text-sm font-medium text-theme-primary">
                {formatTriggerType(details.trigger_type)}
              </p>
            </div>
          </div>

          {details.approval_message && (
            <div className="bg-purple-50 dark:bg-purple-900/20 border-l-4 border-theme-interactive-primary rounded-r px-4 py-3">
              <p className="text-sm text-theme-primary">
                <strong>Message:</strong> {details.approval_message}
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
                className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary text-sm focus:outline-none focus:ring-2 focus:ring-purple-500 resize-none"
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

          {isExpired && details?.workflow?.id && (
            <div className="pt-2">
              <Button
                onClick={() => navigate(`/app/ai/workflows/${details.workflow.id}`)}
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
            Powernode Platform - AI Workflow Approval
          </p>
        </div>
      </div>
    </div>
  );
};

export default ApprovalResponsePage;

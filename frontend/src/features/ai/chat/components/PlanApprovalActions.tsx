import React, { useState } from 'react';
import { Check, MessageSquareText, Clock } from 'lucide-react';
import type { MessageAction, ActionContext } from '@/shared/types/ai';

interface PlanApprovalActionsProps {
  actions: MessageAction[];
  actionContext: ActionContext;
  onAction: (actionType: string, executionId: string, feedback?: string) => Promise<void>;
}

export const PlanApprovalActions: React.FC<PlanApprovalActionsProps> = ({
  actions,
  actionContext,
  onAction,
}) => {
  const [loading, setLoading] = useState(false);
  const [showFeedback, setShowFeedback] = useState(false);
  const [feedback, setFeedback] = useState('');

  const isPending = actionContext.status === 'pending';
  const isApproved = actionContext.status === 'approved';
  const isChangesRequested = actionContext.status === 'changes_requested';

  const handleAction = async (actionType: string) => {
    if (actionType === 'request_changes') {
      setShowFeedback(true);
      return;
    }
    setLoading(true);
    try {
      await onAction(actionType, actionContext.execution_id);
    } finally {
      setLoading(false);
    }
  };

  const handleSubmitFeedback = async () => {
    if (!feedback.trim()) return;
    setLoading(true);
    try {
      await onAction('request_changes', actionContext.execution_id, feedback);
      setShowFeedback(false);
      setFeedback('');
    } finally {
      setLoading(false);
    }
  };

  if (!isPending) {
    return (
      <div className="mt-3 flex items-center gap-2">
        {isApproved && (
          <span className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-md text-xs font-medium bg-theme-success/10 text-theme-success">
            <Check className="h-3.5 w-3.5" />
            Plan Approved
            {actionContext.resolved_at && (
              <span className="text-theme-text-tertiary ml-1">
                {new Date(actionContext.resolved_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
              </span>
            )}
          </span>
        )}
        {isChangesRequested && (
          <span className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-md text-xs font-medium bg-theme-warning/10 text-theme-warning">
            <MessageSquareText className="h-3.5 w-3.5" />
            Changes Requested
            {actionContext.resolved_at && (
              <span className="text-theme-text-tertiary ml-1">
                {new Date(actionContext.resolved_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
              </span>
            )}
          </span>
        )}
      </div>
    );
  }

  return (
    <div className="mt-3">
      {!showFeedback ? (
        <div className="flex items-center gap-2">
          {actions.map((action) => (
            <button
              key={action.type}
              onClick={() => handleAction(action.type)}
              disabled={loading}
              className={`inline-flex items-center gap-1.5 px-4 py-2 rounded-md text-sm font-medium disabled:opacity-50 transition-all ${
                action.style === 'primary'
                  ? 'bg-theme-interactive-primary text-white hover:opacity-90'
                  : 'bg-theme-surface border border-theme text-theme-primary hover:bg-theme-surface-hover'
              }`}
            >
              {action.type === 'approve' ? <Check className="h-4 w-4" /> : <MessageSquareText className="h-4 w-4" />}
              {loading && action.type === 'approve' ? 'Approving...' : action.label}
            </button>
          ))}
          <span className="inline-flex items-center gap-1 text-xs text-theme-text-tertiary ml-2">
            <Clock className="h-3 w-3" />
            Awaiting review
          </span>
        </div>
      ) : (
        <div className="space-y-2">
          <textarea
            value={feedback}
            onChange={(e) => setFeedback(e.target.value)}
            placeholder="Describe what changes you'd like..."
            className="w-full px-3 py-2 text-sm bg-theme-background border border-theme rounded-md text-theme-primary placeholder:text-theme-text-tertiary focus:outline-none focus:ring-1 focus:ring-theme-interactive-primary resize-none"
            rows={3}
            autoFocus
          />
          <div className="flex items-center gap-2">
            <button
              onClick={handleSubmitFeedback}
              disabled={loading || !feedback.trim()}
              className="inline-flex items-center gap-1.5 px-4 py-1.5 rounded-md text-sm font-medium bg-theme-warning text-white hover:opacity-90 disabled:opacity-50 transition-opacity"
            >
              {loading ? 'Submitting...' : 'Submit Feedback'}
            </button>
            <button
              onClick={() => { setShowFeedback(false); setFeedback(''); }}
              disabled={loading}
              className="px-3 py-1.5 rounded-md text-sm text-theme-secondary hover:bg-theme-surface-hover transition-colors"
            >
              Cancel
            </button>
          </div>
        </div>
      )}
    </div>
  );
};

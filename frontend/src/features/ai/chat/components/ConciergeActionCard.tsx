import React, { useState } from 'react';
import { Check, Pencil, Clock, Rocket, GitBranch, Users, Code } from 'lucide-react';
import { chatApi } from '../services/chatApi';

interface ConciergeAction {
  type: string;
  label: string;
  style: string;
}

interface ConciergeActionContext {
  type: string;
  action_type: string;
  status: string;
  resolved_at?: string;
}

interface ConciergeActionCardProps {
  conversationId: string;
  actions: ConciergeAction[];
  actionContext: ConciergeActionContext;
  actionParams: Record<string, unknown>;
  onConfirmed?: () => void;
}

const actionIcons: Record<string, React.ElementType> = {
  create_mission: Rocket,
  delegate_to_team: Users,
  code_review: Code,
  deploy: GitBranch,
};

export const ConciergeActionCard: React.FC<ConciergeActionCardProps> = ({
  conversationId,
  actions,
  actionContext,
  actionParams,
  onConfirmed,
}) => {
  const [loading, setLoading] = useState(false);
  const [showModify, setShowModify] = useState(false);
  const [modifyText, setModifyText] = useState('');

  const isPending = actionContext.status === 'pending';
  const isConfirmed = actionContext.status === 'confirmed';
  const Icon = actionIcons[actionContext.action_type] || Rocket;

  const handleConfirm = async () => {
    setLoading(true);
    try {
      await chatApi.confirmConciergeAction(conversationId, actionContext.action_type, actionParams);
      onConfirmed?.();
    } finally {
      setLoading(false);
    }
  };

  const handleModifySubmit = async () => {
    if (!modifyText.trim()) return;
    setLoading(true);
    try {
      const modifiedParams = { ...actionParams, user_modification: modifyText };
      await chatApi.confirmConciergeAction(conversationId, actionContext.action_type, modifiedParams);
      setShowModify(false);
      setModifyText('');
      onConfirmed?.();
    } finally {
      setLoading(false);
    }
  };

  if (!isPending) {
    return (
      <div className="mt-3 flex items-center gap-2">
        {isConfirmed && (
          <span className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-md text-xs font-medium bg-theme-success/10 text-theme-success">
            <Check className="h-3.5 w-3.5" />
            Action Confirmed
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
      <div className="flex items-center gap-1.5 mb-2">
        <Icon className="h-3.5 w-3.5 text-theme-interactive-primary" />
        <span className="text-xs font-medium text-theme-secondary">
          {String(actionContext.action_type || '').replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase())}
        </span>
      </div>

      {!showModify ? (
        <div className="flex items-center gap-2">
          {actions.map((action) => (
            <button
              key={action.type}
              onClick={action.type === 'confirm' ? handleConfirm : () => setShowModify(true)}
              disabled={loading}
              className={`inline-flex items-center gap-1.5 px-4 py-2 rounded-md text-sm font-medium disabled:opacity-50 transition-all ${
                action.style === 'primary'
                  ? 'bg-theme-interactive-primary text-white hover:opacity-90'
                  : 'bg-theme-surface border border-theme text-theme-primary hover:bg-theme-surface-hover'
              }`}
            >
              {action.type === 'confirm' ? (
                <Check className="h-4 w-4" />
              ) : (
                <Pencil className="h-4 w-4" />
              )}
              {loading && action.type === 'confirm' ? 'Confirming...' : action.label}
            </button>
          ))}
          <span className="inline-flex items-center gap-1 text-xs text-theme-text-tertiary ml-2">
            <Clock className="h-3 w-3" />
            Awaiting confirmation
          </span>
        </div>
      ) : (
        <div className="space-y-2">
          <textarea
            value={modifyText}
            onChange={(e) => setModifyText(e.target.value)}
            placeholder="Describe what you'd like to change..."
            className="w-full px-3 py-2 text-sm bg-theme-background border border-theme rounded-md text-theme-primary placeholder:text-theme-text-tertiary focus:outline-none focus:ring-1 focus:ring-theme-interactive-primary resize-none"
            rows={3}
            autoFocus
          />
          <div className="flex items-center gap-2">
            <button
              onClick={handleModifySubmit}
              disabled={loading || !modifyText.trim()}
              className="inline-flex items-center gap-1.5 px-4 py-1.5 rounded-md text-sm font-medium bg-theme-interactive-primary text-white hover:opacity-90 disabled:opacity-50 transition-opacity"
            >
              {loading ? 'Submitting...' : 'Submit Changes'}
            </button>
            <button
              onClick={() => { setShowModify(false); setModifyText(''); }}
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

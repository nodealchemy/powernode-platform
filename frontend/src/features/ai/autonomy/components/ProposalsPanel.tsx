import React, { useState } from 'react';
import {
  FileText, CheckCircle, XCircle, Clock, AlertTriangle, ChevronDown, Undo2,
} from 'lucide-react';
import { Card, CardContent } from '@/shared/components/ui/Card';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useNotifications } from '@/shared/hooks/useNotifications';
import {
  useProposals, useApproveProposal, useRejectProposal,
  useWithdrawProposal, useBatchReviewProposals,
} from '../api/autonomyApi';
import type { AgentProposal, ProposalStatus } from '../types/autonomy';

function getStatusBadge(status: ProposalStatus) {
  switch (status) {
    case 'approved': return { class: 'text-theme-success bg-theme-success/10', icon: CheckCircle };
    case 'rejected': return { class: 'text-theme-error bg-theme-error/10', icon: XCircle };
    case 'pending_review': return { class: 'text-theme-warning bg-theme-warning/10', icon: Clock };
    case 'implemented': return { class: 'text-theme-info bg-theme-info/10', icon: CheckCircle };
    case 'withdrawn': return { class: 'text-theme-muted bg-theme-surface', icon: XCircle };
    default: return { class: 'text-theme-secondary bg-theme-surface', icon: Clock };
  }
}

function getPriorityColor(priority: string): string {
  switch (priority) {
    case 'critical': return 'text-theme-error';
    case 'high': return 'text-theme-warning';
    case 'medium': return 'text-theme-info';
    default: return 'text-theme-muted';
  }
}

const ProposalCard: React.FC<{
  proposal: AgentProposal;
  isExpanded: boolean;
  onToggle: () => void;
  selected: boolean;
  onSelectToggle: (id: string) => void;
  onApprove: (id: string) => void;
  onReject: (id: string) => void;
  onWithdraw: (id: string) => void;
  actionPending: boolean;
}> = ({ proposal, isExpanded, onToggle, selected, onSelectToggle, onApprove, onReject, onWithdraw, actionPending }) => {
  const badge = getStatusBadge(proposal.status);
  const BadgeIcon = badge.icon;
  const isOverdue = proposal.review_deadline && new Date(proposal.review_deadline) < new Date();
  const isPending = proposal.status === 'pending_review';

  return (
    <div className="bg-theme-surface border border-theme rounded-lg overflow-hidden">
      {/* Collapsed header */}
      <div className="flex items-center gap-3 p-4">
        {/* Batch checkbox for pending proposals */}
        {isPending && (
          <input
            type="checkbox"
            checked={selected}
            onChange={(e) => { e.stopPropagation(); onSelectToggle(proposal.id); }}
            onClick={(e) => e.stopPropagation()}
            className="h-4 w-4 rounded border-theme text-theme-primary shrink-0"
          />
        )}
        <div
          onClick={onToggle}
          className="flex items-center gap-3 flex-1 min-w-0 cursor-pointer hover:opacity-80 transition-opacity"
        >
          <FileText className="h-4 w-4 text-theme-info shrink-0" />
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-2">
              <h4 className="font-medium text-theme-primary truncate">{proposal.title}</h4>
              <span className={`px-2 py-0.5 text-xs rounded flex items-center gap-1 shrink-0 ${badge.class}`}>
                <BadgeIcon className="h-3 w-3" />
                {proposal.status.replace('_', ' ')}
              </span>
              <span className={`text-xs shrink-0 ${getPriorityColor(proposal.priority)}`}>{proposal.priority}</span>
            </div>
            <div className="flex items-center gap-3 text-xs text-theme-muted mt-0.5">
              <span>{proposal.proposal_type}</span>
              {proposal.agent?.name && <span>by {proposal.agent.name}</span>}
              <span>{new Date(proposal.created_at).toLocaleDateString()}</span>
              {isOverdue && isPending && (
                <span className="flex items-center gap-1 text-theme-error">
                  <AlertTriangle className="h-3 w-3" /> Overdue
                </span>
              )}
            </div>
          </div>
          <ChevronDown className={`h-4 w-4 text-theme-muted shrink-0 transition-transform ${isExpanded ? 'rotate-180' : ''}`} />
        </div>
      </div>

      {/* Expanded detail */}
      {isExpanded && (
        <div className="border-t border-theme p-4 space-y-4">
          <p className="text-sm text-theme-secondary">{proposal.description}</p>

          {proposal.rationale && (
            <div className="text-sm text-theme-secondary bg-theme-background rounded p-3">
              <span className="font-medium text-theme-primary">Rationale: </span>{proposal.rationale}
            </div>
          )}

          {/* Impact assessment */}
          {Object.keys(proposal.impact_assessment).length > 0 && (
            <div>
              <h4 className="text-sm font-medium text-theme-primary mb-1">Impact Assessment</h4>
              <div className="text-xs bg-theme-background border border-theme rounded p-3 space-y-1">
                {Object.entries(proposal.impact_assessment).map(([key, value]) => (
                  <p key={key} className="text-theme-secondary">
                    <span className="font-medium">{key}: </span>
                    {typeof value === 'string' ? value : JSON.stringify(value)}
                  </p>
                ))}
              </div>
            </div>
          )}

          {/* Proposed changes */}
          {Object.keys(proposal.proposed_changes).length > 0 && (
            <div>
              <h4 className="text-sm font-medium text-theme-primary mb-1">Proposed Changes</h4>
              <pre className="text-xs bg-theme-background border border-theme rounded p-3 overflow-auto text-theme-secondary">
                {JSON.stringify(proposal.proposed_changes, null, 2)}
              </pre>
            </div>
          )}

          {/* Metadata */}
          <div className="flex flex-wrap gap-4 text-xs text-theme-muted">
            {proposal.review_deadline && <span>Review deadline: {new Date(proposal.review_deadline).toLocaleString()}</span>}
            {proposal.reviewed_by?.email && <span>Reviewed by: {proposal.reviewed_by.email}</span>}
            {proposal.reviewed_at && <span>Reviewed: {new Date(proposal.reviewed_at).toLocaleString()}</span>}
            <span>Created {new Date(proposal.created_at).toLocaleString()}</span>
          </div>

          {/* Actions */}
          {isPending && (
            <div className="flex gap-2">
              <button
                onClick={() => onApprove(proposal.id)}
                disabled={actionPending}
                className="btn-theme btn-theme-success btn-theme-sm flex items-center gap-1"
              >
                <CheckCircle className="h-3 w-3" /> Approve
              </button>
              <button
                onClick={() => onReject(proposal.id)}
                disabled={actionPending}
                className="btn-theme btn-theme-danger btn-theme-sm flex items-center gap-1"
              >
                <XCircle className="h-3 w-3" /> Reject
              </button>
              <button
                onClick={() => onWithdraw(proposal.id)}
                disabled={actionPending}
                className="btn-theme btn-theme-secondary btn-theme-sm flex items-center gap-1"
              >
                <Undo2 className="h-3 w-3" /> Withdraw
              </button>
            </div>
          )}

          {!isPending && (
            <p className="text-xs text-theme-muted italic">
              {proposal.status === 'withdrawn' ? 'This proposal was withdrawn.' : `This proposal has been ${proposal.status}.`}
            </p>
          )}
        </div>
      )}
    </div>
  );
};

export const ProposalsPanel: React.FC = () => {
  const [statusFilter, setStatusFilter] = useState<string>('');
  const [expandedId, setExpandedId] = useState<string | null>(null);
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const { data: proposals, isLoading } = useProposals(statusFilter ? { status: statusFilter } : undefined);
  const approveMutation = useApproveProposal();
  const rejectMutation = useRejectProposal();
  const withdrawMutation = useWithdrawProposal();
  const batchReviewMutation = useBatchReviewProposals();
  const { addNotification } = useNotifications();

  const handleApprove = async (id: string) => {
    try {
      await approveMutation.mutateAsync({ id });
      addNotification({ type: 'success', message: 'Proposal approved' });
    } catch {
      addNotification({ type: 'error', message: 'Failed to approve proposal' });
    }
  };

  const handleReject = async (id: string) => {
    try {
      await rejectMutation.mutateAsync({ id });
      addNotification({ type: 'success', message: 'Proposal rejected' });
    } catch {
      addNotification({ type: 'error', message: 'Failed to reject proposal' });
    }
  };

  const handleWithdraw = async (id: string) => {
    try {
      await withdrawMutation.mutateAsync(id);
      addNotification({ type: 'success', message: 'Proposal withdrawn' });
    } catch {
      addNotification({ type: 'error', message: 'Failed to withdraw proposal' });
    }
  };

  const toggleSelect = (id: string) => {
    setSelectedIds(prev => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id); else next.add(id);
      return next;
    });
  };

  const handleBatchAction = async (action: 'approve' | 'reject') => {
    if (selectedIds.size === 0) return;
    try {
      await batchReviewMutation.mutateAsync({ proposal_ids: Array.from(selectedIds), action });
      addNotification({ type: 'success', message: `${selectedIds.size} proposal(s) ${action === 'approve' ? 'approved' : 'rejected'}` });
      setSelectedIds(new Set());
    } catch {
      addNotification({ type: 'error', message: `Failed to batch ${action} proposals` });
    }
  };

  if (isLoading) return <LoadingSpinner size="lg" className="py-12" message="Loading proposals..." />;

  const safeProposals = proposals ?? [];
  const pendingCount = safeProposals.filter(p => p.status === 'pending_review').length;
  const actionPending = approveMutation.isPending || rejectMutation.isPending || withdrawMutation.isPending;

  return (
    <div className="space-y-4">
      <div className="flex items-center gap-3">
        <select
          value={statusFilter}
          onChange={(e) => setStatusFilter(e.target.value)}
          className="px-3 py-1.5 text-sm rounded-md border border-theme bg-theme-surface text-theme-primary"
        >
          <option value="">All statuses</option>
          <option value="pending_review">Pending Review</option>
          <option value="approved">Approved</option>
          <option value="rejected">Rejected</option>
          <option value="implemented">Implemented</option>
          <option value="withdrawn">Withdrawn</option>
        </select>
        {pendingCount > 0 && (
          <span className="px-2 py-1 text-xs rounded bg-theme-warning/10 text-theme-warning">
            {pendingCount} pending review
          </span>
        )}
      </div>

      {/* Batch action bar */}
      {selectedIds.size >= 2 && (
        <div className="flex items-center gap-3 p-3 bg-theme-info/10 border border-theme-info/30 rounded-lg">
          <span className="text-sm text-theme-primary font-medium">{selectedIds.size} selected</span>
          <button
            onClick={() => handleBatchAction('approve')}
            disabled={batchReviewMutation.isPending}
            className="btn-theme btn-theme-success btn-theme-sm"
          >
            Approve All
          </button>
          <button
            onClick={() => handleBatchAction('reject')}
            disabled={batchReviewMutation.isPending}
            className="btn-theme btn-theme-danger btn-theme-sm"
          >
            Reject All
          </button>
          <button
            onClick={() => setSelectedIds(new Set())}
            className="btn-theme btn-theme-secondary btn-theme-sm"
          >
            Clear
          </button>
        </div>
      )}

      {safeProposals.length === 0 ? (
        <Card>
          <CardContent className="p-8 text-center text-theme-muted">
            <FileText className="w-12 h-12 mx-auto mb-3 opacity-30" />
            <p>No proposals found. Autonomous agents create proposals when they identify improvements.</p>
          </CardContent>
        </Card>
      ) : (
        <div className="space-y-3">
          {safeProposals.map((proposal) => (
            <ProposalCard
              key={proposal.id}
              proposal={proposal}
              isExpanded={expandedId === proposal.id}
              onToggle={() => setExpandedId(prev => prev === proposal.id ? null : proposal.id)}
              selected={selectedIds.has(proposal.id)}
              onSelectToggle={toggleSelect}
              onApprove={handleApprove}
              onReject={handleReject}
              onWithdraw={handleWithdraw}
              actionPending={actionPending}
            />
          ))}
        </div>
      )}
    </div>
  );
};

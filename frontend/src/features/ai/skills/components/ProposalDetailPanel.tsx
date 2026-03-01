import { useState, useEffect } from 'react';
import { X, CheckCircle, XCircle, ArrowRight, Bot, User, Clock, Tag } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { Card } from '@/shared/components/ui/Card';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { skillLifecycleApi } from '../services/skillLifecycleApi';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { ResearchResultsPanel } from './ResearchResultsPanel';
import type { SkillProposal, ProposalStatus } from '../types/lifecycle';

interface ProposalDetailPanelProps {
  proposalId: string;
  onClose: () => void;
  onUpdated: () => void;
}

const STATUS_VARIANTS: Record<ProposalStatus, 'default' | 'info' | 'warning' | 'success' | 'danger'> = {
  draft: 'default',
  proposed: 'info',
  approved: 'success',
  created: 'success',
  rejected: 'danger',
};

export function ProposalDetailPanel({ proposalId, onClose, onUpdated }: ProposalDetailPanelProps) {
  const { showNotification } = useNotifications();
  const [proposal, setProposal] = useState<SkillProposal | null>(null);
  const [loading, setLoading] = useState(true);
  const [rejectReason, setRejectReason] = useState('');
  const [showRejectInput, setShowRejectInput] = useState(false);
  const [acting, setActing] = useState(false);

  useEffect(() => {
    const load = async () => {
      setLoading(true);
      const response = await skillLifecycleApi.getProposal(proposalId);
      if (response.success && response.data) {
        setProposal(response.data.proposal);
      }
      setLoading(false);
    };
    load();
  }, [proposalId]);

  const handleApprove = async () => {
    setActing(true);
    const response = await skillLifecycleApi.approveProposal(proposalId);
    if (response.success) {
      showNotification('Proposal approved', 'success');
      onUpdated();
      onClose();
    } else {
      showNotification(response.error || 'Failed to approve', 'error');
    }
    setActing(false);
  };

  const handleReject = async () => {
    if (!rejectReason.trim()) return;
    setActing(true);
    const response = await skillLifecycleApi.rejectProposal(proposalId, rejectReason);
    if (response.success) {
      showNotification('Proposal rejected', 'success');
      onUpdated();
      onClose();
    } else {
      showNotification(response.error || 'Failed to reject', 'error');
    }
    setActing(false);
  };

  const handleCreateSkill = async () => {
    setActing(true);
    const response = await skillLifecycleApi.createSkillFromProposal(proposalId);
    if (response.success) {
      showNotification('Skill created from proposal', 'success');
      onUpdated();
      onClose();
    } else {
      showNotification(response.error || 'Failed to create skill', 'error');
    }
    setActing(false);
  };

  const handleSubmit = async () => {
    setActing(true);
    const response = await skillLifecycleApi.submitProposal(proposalId);
    if (response.success) {
      showNotification('Proposal submitted for review', 'success');
      onUpdated();
      onClose();
    } else {
      showNotification(response.error || 'Failed to submit', 'error');
    }
    setActing(false);
  };

  return (
    <div className="fixed inset-y-0 right-0 w-full max-w-xl bg-theme-surface border-l border-theme shadow-xl z-50 flex flex-col" data-testid="proposal-detail-panel">
      {/* Header */}
      <div className="flex items-center justify-between px-5 py-4 border-b border-theme">
        <h3 className="text-lg font-semibold text-theme-primary">Proposal Details</h3>
        <button onClick={onClose} className="text-theme-tertiary hover:text-theme-primary">
          <X className="w-5 h-5" />
        </button>
      </div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto p-5 space-y-5">
        {loading ? (
          <div className="flex justify-center py-12"><LoadingSpinner /></div>
        ) : proposal ? (
          <>
            {/* Title & Status */}
            <div>
              <div className="flex items-center gap-2 mb-1">
                <h4 className="text-lg font-medium text-theme-primary">{proposal.name}</h4>
                <Badge variant={STATUS_VARIANTS[proposal.status]} size="sm">
                  {proposal.status}
                </Badge>
              </div>
              {proposal.description && (
                <p className="text-sm text-theme-secondary">{proposal.description}</p>
              )}
            </div>

            {/* Metadata */}
            <Card variant="outlined" padding="sm">
              <div className="grid grid-cols-2 gap-3 text-sm">
                <div className="flex items-center gap-1.5 text-theme-tertiary">
                  {proposal.proposed_by_agent ? <Bot className="w-3.5 h-3.5" /> : <User className="w-3.5 h-3.5" />}
                  <span>{proposal.proposed_by_agent?.name || proposal.proposed_by_user?.name || 'Unknown'}</span>
                </div>
                {proposal.category && (
                  <div className="flex items-center gap-1.5 text-theme-tertiary">
                    <Tag className="w-3.5 h-3.5" />
                    <span className="capitalize">{proposal.category.replace(/_/g, ' ')}</span>
                  </div>
                )}
                <div className="flex items-center gap-1.5 text-theme-tertiary">
                  <Clock className="w-3.5 h-3.5" />
                  <span>{new Date(proposal.created_at).toLocaleString()}</span>
                </div>
                {proposal.confidence_score > 0 && (
                  <div className="text-theme-tertiary">
                    Confidence: {Math.round(proposal.confidence_score * 100)}%
                  </div>
                )}
              </div>
            </Card>

            {/* Tags */}
            {proposal.tags.length > 0 && (
              <div className="flex gap-1.5 flex-wrap">
                {proposal.tags.map((tag) => (
                  <Badge key={tag} variant="secondary" size="xs">{tag}</Badge>
                ))}
              </div>
            )}

            {/* System Prompt Preview */}
            {proposal.system_prompt && (
              <div>
                <h5 className="text-sm font-medium text-theme-primary mb-1">System Prompt</h5>
                <pre className="text-xs text-theme-secondary bg-theme-surface-secondary p-3 rounded-md overflow-x-auto max-h-40 whitespace-pre-wrap">
                  {proposal.system_prompt}
                </pre>
              </div>
            )}

            {/* Commands */}
            {proposal.commands.length > 0 && (
              <div>
                <h5 className="text-sm font-medium text-theme-primary mb-1">Commands ({proposal.commands.length})</h5>
                <div className="space-y-1">
                  {proposal.commands.map((cmd) => (
                    <div key={cmd.name} className="text-sm px-2 py-1 bg-theme-surface-secondary rounded">
                      <span className="font-mono text-theme-primary">{cmd.name}</span>
                      <span className="text-theme-tertiary ml-2">{cmd.description}</span>
                    </div>
                  ))}
                </div>
              </div>
            )}

            {/* Dependencies */}
            {proposal.suggested_dependencies.length > 0 && (
              <div>
                <h5 className="text-sm font-medium text-theme-primary mb-1">Suggested Dependencies</h5>
                <div className="space-y-1">
                  {proposal.suggested_dependencies.map((dep, i) => (
                    <div key={i} className="flex items-center gap-2 text-sm px-2 py-1 bg-theme-surface-secondary rounded">
                      <ArrowRight className="w-3 h-3 text-theme-tertiary" />
                      <span className="text-theme-primary">{dep.name}</span>
                      <span className="text-theme-tertiary">({dep.relation_type})</span>
                      <span className="text-theme-tertiary ml-auto">{Math.round(dep.confidence * 100)}%</span>
                    </div>
                  ))}
                </div>
              </div>
            )}

            {/* Research Report */}
            {proposal.research_report && Object.keys(proposal.research_report).length > 0 && (
              <div>
                <h5 className="text-sm font-medium text-theme-primary mb-2">Research Report</h5>
                <ResearchResultsPanel report={proposal.research_report} />
              </div>
            )}

            {/* Rejection Reason */}
            {proposal.rejection_reason && (
              <Card variant="outlined" padding="sm" className="border-theme-danger/30">
                <p className="text-sm text-theme-danger">
                  <span className="font-medium">Rejected:</span> {proposal.rejection_reason}
                </p>
              </Card>
            )}
          </>
        ) : (
          <div className="text-center py-12 text-theme-tertiary">Proposal not found</div>
        )}
      </div>

      {/* Actions */}
      {proposal && (
        <div className="border-t border-theme px-5 py-3 space-y-3">
          {showRejectInput && (
            <div className="flex gap-2">
              <input
                type="text"
                value={rejectReason}
                onChange={(e) => setRejectReason(e.target.value)}
                placeholder="Reason for rejection..."
                className="flex-1 px-3 py-1.5 text-sm bg-theme-surface border border-theme rounded-md text-theme-primary"
                onKeyDown={(e) => e.key === 'Enter' && handleReject()}
              />
              <Button size="sm" variant="danger" onClick={handleReject} disabled={acting || !rejectReason.trim()}>
                Confirm
              </Button>
              <Button size="sm" variant="ghost" onClick={() => setShowRejectInput(false)}>
                Cancel
              </Button>
            </div>
          )}

          <div className="flex justify-end gap-2">
            {proposal.status === 'draft' && (
              <Button variant="primary" size="sm" onClick={handleSubmit} disabled={acting}>
                Submit for Review
              </Button>
            )}
            {proposal.status === 'proposed' && (
              <>
                <Button variant="ghost" size="sm" onClick={() => setShowRejectInput(true)} disabled={acting}>
                  <XCircle className="w-3.5 h-3.5 mr-1" />
                  Reject
                </Button>
                <Button variant="primary" size="sm" onClick={handleApprove} disabled={acting}>
                  <CheckCircle className="w-3.5 h-3.5 mr-1" />
                  Approve
                </Button>
              </>
            )}
            {proposal.status === 'approved' && (
              <Button variant="primary" size="sm" onClick={handleCreateSkill} disabled={acting}>
                Create Skill
              </Button>
            )}
          </div>
        </div>
      )}
    </div>
  );
}

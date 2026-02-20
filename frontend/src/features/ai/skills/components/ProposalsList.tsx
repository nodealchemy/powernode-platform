import { useState, useEffect, useCallback } from 'react';
import { CheckCircle, XCircle } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { EmptyState } from '@/shared/components/ui/EmptyState';
import { skillLifecycleApi } from '../services/skillLifecycleApi';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { ProposalCard } from './ProposalCard';
import { ProposalDetailPanel } from './ProposalDetailPanel';
import type { SkillProposal, ProposalStatus } from '../types/lifecycle';

const STATUS_FILTERS: { value: string; label: string }[] = [
  { value: '', label: 'All' },
  { value: 'proposed', label: 'Pending' },
  { value: 'draft', label: 'Drafts' },
  { value: 'approved', label: 'Approved' },
  { value: 'created', label: 'Created' },
  { value: 'rejected', label: 'Rejected' },
];

export function ProposalsList() {
  const { showNotification } = useNotifications();
  const [proposals, setProposals] = useState<SkillProposal[]>([]);
  const [loading, setLoading] = useState(true);
  const [statusFilter, setStatusFilter] = useState('');
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [detailId, setDetailId] = useState<string | null>(null);

  const loadProposals = useCallback(async () => {
    setLoading(true);
    const response = await skillLifecycleApi.getProposals(1, statusFilter || undefined);
    if (response.success && response.data) {
      setProposals(response.data.proposals);
    } else {
      showNotification(response.error || 'Failed to load proposals', 'error');
    }
    setLoading(false);
  }, [statusFilter, showNotification]);

  useEffect(() => {
    loadProposals();
  }, [loadProposals]);

  const toggleSelect = (id: string) => {
    setSelectedIds((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  const handleBatchApprove = async () => {
    const pending = proposals.filter((p) => selectedIds.has(p.id) && p.status === 'proposed');
    let approved = 0;
    for (const p of pending) {
      const res = await skillLifecycleApi.approveProposal(p.id);
      if (res.success) approved++;
    }
    showNotification(`Approved ${approved} proposal(s)`, 'success');
    setSelectedIds(new Set());
    loadProposals();
  };

  const handleBatchReject = async () => {
    const pending = proposals.filter((p) => selectedIds.has(p.id) && p.status === 'proposed');
    let rejected = 0;
    for (const p of pending) {
      const res = await skillLifecycleApi.rejectProposal(p.id, 'Batch rejected');
      if (res.success) rejected++;
    }
    showNotification(`Rejected ${rejected} proposal(s)`, 'success');
    setSelectedIds(new Set());
    loadProposals();
  };

  const pendingSelected = proposals.filter(
    (p) => selectedIds.has(p.id) && p.status === ('proposed' as ProposalStatus)
  );

  return (
    <div className="space-y-4" data-testid="proposals-list">
      {/* Filter Bar */}
      <div className="flex items-center justify-between gap-4">
        <div className="flex gap-2">
          {STATUS_FILTERS.map((f) => (
            <button
              key={f.value}
              onClick={() => setStatusFilter(f.value)}
              className={`px-3 py-1.5 text-sm rounded-md border transition-colors ${
                statusFilter === f.value
                  ? 'bg-theme-interactive-primary text-theme-surface border-transparent'
                  : 'text-theme-secondary border-theme hover:bg-theme-surface-hover'
              }`}
            >
              {f.label}
            </button>
          ))}
        </div>

        {pendingSelected.length > 0 && (
          <div className="flex gap-2">
            <Button variant="primary" size="sm" onClick={handleBatchApprove}>
              <CheckCircle className="w-3.5 h-3.5 mr-1" />
              Approve ({pendingSelected.length})
            </Button>
            <Button variant="danger" size="sm" onClick={handleBatchReject}>
              <XCircle className="w-3.5 h-3.5 mr-1" />
              Reject ({pendingSelected.length})
            </Button>
          </div>
        )}
      </div>

      {/* List */}
      {loading ? (
        <div className="flex justify-center py-12">
          <LoadingSpinner />
        </div>
      ) : proposals.length === 0 ? (
        <EmptyState
          title="No proposals found"
          description={statusFilter ? 'Try a different filter' : 'Use the Research button to create your first proposal'}
        />
      ) : (
        <div className="space-y-2">
          {proposals.map((proposal) => (
            <ProposalCard
              key={proposal.id}
              proposal={proposal}
              selected={selectedIds.has(proposal.id)}
              onSelect={toggleSelect}
              onClick={setDetailId}
            />
          ))}
        </div>
      )}

      {/* Detail Panel */}
      {detailId && (
        <ProposalDetailPanel
          proposalId={detailId}
          onClose={() => setDetailId(null)}
          onUpdated={loadProposals}
        />
      )}
    </div>
  );
}

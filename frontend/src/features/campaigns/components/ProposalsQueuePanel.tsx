import React, { useEffect, useState } from 'react';
import { Lightbulb, Check, X, ListPlus, Rocket, RefreshCw } from 'lucide-react';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { useProposals } from '../hooks/useProposals';
import { PROPOSAL_STATUS_CONFIG, DRIVER_KIND_LABELS } from '../constants/campaign';
import type { CampaignProposal } from '../types/campaign';

interface ProposalsQueuePanelProps {
  canManage: boolean;
  // Open the spawned campaign's detail once a proposal is approved/spawned.
  onSpawned?: (campaignId: string) => void;
}

// Discovery/delegation control plane: the durable queue of proposed campaigns. Reviewers
// queue → approve → spawn (or reject) here; spawning hands off to the campaign + its loop,
// which is then delegated to a driver from the campaign detail.
export const ProposalsQueuePanel: React.FC<ProposalsQueuePanelProps> = ({ canManage, onSpawned }) => {
  const {
    proposals, loading, error, fetchProposals,
    queueProposal, approveProposal, rejectProposal, spawnProposal,
  } = useProposals();
  const { addNotification } = useNotifications();
  const [busy, setBusy] = useState<string | null>(null);

  useEffect(() => { fetchProposals(); }, [fetchProposals]);

  const run = async (key: string, fn: () => Promise<unknown>, successMsg: string) => {
    setBusy(key);
    try {
      const result = await fn();
      addNotification({ type: 'success', message: successMsg });
      return result;
    } catch (err) {
      addNotification({ type: 'error', message: err instanceof Error ? err.message : 'Action failed' });
      return undefined;
    } finally {
      setBusy(null);
    }
  };

  return (
    <div className="mb-6 rounded-md border border-theme bg-theme-surface">
      <div className="flex items-center justify-between border-b border-theme px-4 py-3">
        <h3 className="flex items-center gap-2 text-sm font-semibold text-theme-primary">
          <Lightbulb size={16} />
          Discovery Queue ({proposals.length})
        </h3>
        <Button variant="ghost" size="xs" onClick={() => fetchProposals()} loading={loading}>
          <RefreshCw size={14} className="mr-1" />
          Refresh
        </Button>
      </div>

      {error && <div className="px-4 py-3 text-sm text-theme-error-fg">{error}</div>}

      {loading && proposals.length === 0 ? (
        <div className="flex justify-center py-8"><LoadingSpinner /></div>
      ) : proposals.length === 0 ? (
        <p className="px-4 py-6 text-center text-sm text-theme-secondary">
          No proposed campaigns yet. Discovery and the concierge feed this queue.
        </p>
      ) : (
        <ul className="divide-y divide-theme">
          {proposals.map((p) => (
            <ProposalRow
              key={p.id}
              proposal={p}
              canManage={canManage}
              busy={busy}
              onQueue={() => run(`${p.id}:queue`, () => queueProposal(p.id), 'Proposal queued')}
              onApprove={() => run(`${p.id}:approve`, () => approveProposal(p.id), 'Proposal approved')}
              onReject={() => run(`${p.id}:reject`, () => rejectProposal(p.id), 'Proposal rejected')}
              onSpawn={async () => {
                const campaignId = await run(`${p.id}:spawn`, () => spawnProposal(p.id), 'Campaign spawned');
                if (typeof campaignId === 'string' && onSpawned) onSpawned(campaignId);
              }}
              onView={() => p.spawned_campaign_id && onSpawned?.(p.spawned_campaign_id)}
            />
          ))}
        </ul>
      )}
    </div>
  );
};

interface ProposalRowProps {
  proposal: CampaignProposal;
  canManage: boolean;
  busy: string | null;
  onQueue: () => void;
  onApprove: () => void;
  onReject: () => void;
  onSpawn: () => void;
  onView: () => void;
}

const ProposalRow: React.FC<ProposalRowProps> = ({
  proposal: p, canManage, busy, onQueue, onApprove, onReject, onSpawn, onView,
}) => {
  const statusConfig = PROPOSAL_STATUS_CONFIG[p.status] || { label: p.status, variant: 'outline' as const };
  const isBusy = (key: string) => busy === `${p.id}:${key}`;

  return (
    <li className="px-4 py-3">
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-2">
            <Badge variant={statusConfig.variant} size="xs">{statusConfig.label}</Badge>
            <Badge variant="outline" size="xs">{p.source}</Badge>
            <span className="text-sm font-medium text-theme-primary">{p.title}</span>
          </div>
          <p className="mt-1 line-clamp-2 text-xs text-theme-secondary">{p.objective}</p>
          <div className="mt-1 flex flex-wrap gap-x-3 gap-y-0.5 text-xs text-theme-tertiary">
            {p.scope && <span>scope: <span className="font-mono">{p.scope}</span></span>}
            <span>workload: {p.suggested_workload}</span>
            {p.suggested_driver && <span>driver: {DRIVER_KIND_LABELS[p.suggested_driver]}</span>}
          </div>
          {p.status === 'rejected' && p.rejection_reason && (
            <p className="mt-1 text-xs text-theme-error-fg">Rejected: {p.rejection_reason}</p>
          )}
        </div>

        {canManage && (
          <div className="flex shrink-0 flex-wrap items-center justify-end gap-1.5">
            {p.status === 'proposed' && (
              <Button variant="outline" size="xs" onClick={onQueue} loading={isBusy('queue')}>
                <ListPlus size={13} className="mr-1" />Queue
              </Button>
            )}
            {(p.status === 'proposed' || p.status === 'queued') && (
              <Button variant="success" size="xs" onClick={onApprove} loading={isBusy('approve')}>
                <Check size={13} className="mr-1" />Approve
              </Button>
            )}
            {(p.status === 'queued' || p.status === 'approved') && (
              <Button variant="primary" size="xs" onClick={onSpawn} loading={isBusy('spawn')}>
                <Rocket size={13} className="mr-1" />Spawn
              </Button>
            )}
            {p.status === 'spawned' && (
              <Button variant="ghost" size="xs" onClick={onView}>View campaign</Button>
            )}
            {p.status !== 'rejected' && p.status !== 'spawned' && (
              <Button variant="ghost" size="xs" onClick={onReject} loading={isBusy('reject')}>
                <X size={13} className="mr-1" />Reject
              </Button>
            )}
          </div>
        )}
      </div>
    </li>
  );
};

import React from 'react';
import { Megaphone, HelpCircle, Plus } from 'lucide-react';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { Progress } from '@/shared/components/ui/Progress';
import { EmptyState } from '@/shared/components/ui/EmptyState';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import type { CampaignSummary } from '../types/campaign';
import { STATUS_CONFIG, DECISION_AUTHORITY_LABELS } from '../constants/campaign';

interface CampaignsIndexTableProps {
  campaigns: CampaignSummary[];
  loading: boolean;
  onSelect: (id: string) => void;
  onNewCampaign?: () => void;
  canManage: boolean;
}

export const CampaignsIndexTable: React.FC<CampaignsIndexTableProps> = ({
  campaigns,
  loading,
  onSelect,
  onNewCampaign,
  canManage,
}) => {
  if (loading && campaigns.length === 0) {
    return (
      <div className="flex justify-center py-12">
        <LoadingSpinner />
      </div>
    );
  }

  if (campaigns.length === 0) {
    return (
      <EmptyState
        icon={Megaphone}
        title="No improvement campaigns yet"
        description={
          canManage
            ? 'Start a campaign to let an agent autonomously drive a backlog of improvements to a verified, committed outcome.'
            : 'No autonomous improvement campaigns have been started for this account.'
        }
        action={
          canManage && onNewCampaign ? (
            <Button variant="primary" onClick={onNewCampaign}>
              <Plus size={16} className="mr-1" />
              Start a Campaign
            </Button>
          ) : undefined
        }
      />
    );
  }

  return (
    <div className="overflow-x-auto rounded-lg border border-theme">
      <table className="min-w-full divide-y divide-theme">
        <thead className="bg-theme-surface-hover">
          <tr>
            <th className="px-4 py-3 text-left text-xs font-medium uppercase tracking-wider text-theme-secondary">Campaign</th>
            <th className="px-4 py-3 text-left text-xs font-medium uppercase tracking-wider text-theme-secondary">Status</th>
            <th className="px-4 py-3 text-left text-xs font-medium uppercase tracking-wider text-theme-secondary">Authority</th>
            <th className="px-4 py-3 text-left text-xs font-medium uppercase tracking-wider text-theme-secondary">Progress</th>
            <th className="px-4 py-3 text-left text-xs font-medium uppercase tracking-wider text-theme-secondary">Tasks</th>
            <th className="px-4 py-3 text-left text-xs font-medium uppercase tracking-wider text-theme-secondary">Questions</th>
          </tr>
        </thead>
        <tbody className="divide-y divide-theme bg-theme-surface">
          {campaigns.map((c) => {
            const statusConfig = STATUS_CONFIG[c.status] || { label: c.status, variant: 'outline' as const };
            return (
              <tr
                key={c.id}
                onClick={() => onSelect(c.id)}
                className="cursor-pointer transition-colors hover:bg-theme-surface-hover"
              >
                <td className="px-4 py-3">
                  <div className="font-medium text-theme-primary">{c.name}</div>
                  <div className="text-xs text-theme-tertiary">{c.loop_count} loop{c.loop_count === 1 ? '' : 's'}</div>
                </td>
                <td className="px-4 py-3">
                  <Badge variant={statusConfig.variant} size="sm">{statusConfig.label}</Badge>
                </td>
                <td className="px-4 py-3 text-sm text-theme-secondary">
                  {DECISION_AUTHORITY_LABELS[c.decision_authority] || c.decision_authority}
                </td>
                <td className="px-4 py-3 w-40">
                  <Progress value={c.completion_pct} size="sm" />
                  <div className="mt-1 text-xs text-theme-secondary">{c.completion_pct}%</div>
                </td>
                <td className="px-4 py-3 text-sm text-theme-secondary">
                  <span className="text-theme-success-fg">{c.completed_tasks}</span>
                  {' / '}
                  {c.total_tasks}
                  {c.failed_tasks > 0 && <span className="ml-1 text-theme-error-fg">({c.failed_tasks} failed)</span>}
                </td>
                <td className="px-4 py-3 text-sm">
                  {c.open_questions > 0 ? (
                    <span className="inline-flex items-center gap-1 text-theme-warning-fg">
                      <HelpCircle size={14} />
                      {c.open_questions}
                    </span>
                  ) : (
                    <span className="text-theme-tertiary">—</span>
                  )}
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
};

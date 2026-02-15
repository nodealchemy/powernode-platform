import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  Search,
  Filter,
  Megaphone,
  Eye,
  MousePointerClick,
  ArrowRightLeft,
  MoreVertical,
  Copy,
  Pause,
  Play,
  Archive,
  Trash2,
} from 'lucide-react';
import { useCampaigns } from '../hooks/useCampaigns';
import { CampaignStatusBadge } from './CampaignStatusBadge';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { campaignsApi } from '../services/campaignsApi';
import { logger } from '@/shared/utils/logger';
import type { CampaignStatus, CampaignType } from '../types';

const STATUS_OPTIONS: { value: CampaignStatus | ''; label: string }[] = [
  { value: '', label: 'All Statuses' },
  { value: 'draft', label: 'Draft' },
  { value: 'scheduled', label: 'Scheduled' },
  { value: 'active', label: 'Active' },
  { value: 'paused', label: 'Paused' },
  { value: 'completed', label: 'Completed' },
  { value: 'archived', label: 'Archived' },
];

const TYPE_OPTIONS: { value: CampaignType | ''; label: string }[] = [
  { value: '', label: 'All Types' },
  { value: 'email', label: 'Email' },
  { value: 'social', label: 'Social' },
  { value: 'multi_channel', label: 'Multi-Channel' },
  { value: 'sms', label: 'SMS' },
  { value: 'push', label: 'Push' },
];

export const CampaignDashboard: React.FC = () => {
  const navigate = useNavigate();
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState<CampaignStatus | ''>('');
  const [typeFilter, setTypeFilter] = useState<CampaignType | ''>('');
  const [page, setPage] = useState(1);
  const [openMenuId, setOpenMenuId] = useState<string | null>(null);

  const { campaigns, pagination, loading, error, refresh } = useCampaigns({
    page,
    perPage: 20,
    status: statusFilter || undefined,
    campaignType: typeFilter || undefined,
    search: search || undefined,
  });

  const handleAction = async (action: string, campaignId: string) => {
    try {
      switch (action) {
        case 'execute':
          await campaignsApi.execute(campaignId);
          break;
        case 'pause':
          await campaignsApi.pause(campaignId);
          break;
        case 'resume':
          await campaignsApi.resume(campaignId);
          break;
        case 'archive':
          await campaignsApi.archive(campaignId);
          break;
        case 'clone':
          await campaignsApi.clone(campaignId);
          break;
        case 'delete':
          await campaignsApi.delete(campaignId);
          break;
      }
      setOpenMenuId(null);
      refresh();
    } catch (err) {
      logger.error('Campaign action failed:', err);
    }
  };

  const formatCurrency = (cents: number): string => {
    return `$${(cents / 100).toLocaleString('en-US', { minimumFractionDigits: 2 })}`;
  };

  if (loading && campaigns.length === 0) {
    return (
      <div className="flex items-center justify-center py-12">
        <LoadingSpinner />
      </div>
    );
  }

  if (error) {
    return (
      <div className="card-theme p-6 text-center">
        <p className="text-theme-error">{error}</p>
        <button onClick={refresh} className="btn-theme btn-theme-secondary mt-4">
          Retry
        </button>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Stats Summary */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
        <div className="card-theme p-4">
          <div className="flex items-center space-x-3">
            <div className="p-2 rounded-lg bg-theme-info bg-opacity-10">
              <Megaphone className="w-5 h-5 text-theme-info" />
            </div>
            <div>
              <p className="text-sm text-theme-secondary">Total Campaigns</p>
              <p className="text-xl font-semibold text-theme-primary">{pagination?.total_count || 0}</p>
            </div>
          </div>
        </div>
        <div className="card-theme p-4">
          <div className="flex items-center space-x-3">
            <div className="p-2 rounded-lg bg-theme-success bg-opacity-10">
              <Eye className="w-5 h-5 text-theme-success" />
            </div>
            <div>
              <p className="text-sm text-theme-secondary">Active</p>
              <p className="text-xl font-semibold text-theme-primary">
                {campaigns.filter(c => c.status === 'active').length}
              </p>
            </div>
          </div>
        </div>
        <div className="card-theme p-4">
          <div className="flex items-center space-x-3">
            <div className="p-2 rounded-lg bg-theme-warning bg-opacity-10">
              <MousePointerClick className="w-5 h-5 text-theme-warning" />
            </div>
            <div>
              <p className="text-sm text-theme-secondary">Total Clicks</p>
              <p className="text-xl font-semibold text-theme-primary">
                {campaigns.reduce((sum, c) => sum + (c.metrics_summary?.clicks || 0), 0).toLocaleString()}
              </p>
            </div>
          </div>
        </div>
        <div className="card-theme p-4">
          <div className="flex items-center space-x-3">
            <div className="p-2 rounded-lg bg-theme-primary bg-opacity-10">
              <ArrowRightLeft className="w-5 h-5 text-theme-primary" />
            </div>
            <div>
              <p className="text-sm text-theme-secondary">Total Conversions</p>
              <p className="text-xl font-semibold text-theme-primary">
                {campaigns.reduce((sum, c) => sum + (c.metrics_summary?.conversions || 0), 0).toLocaleString()}
              </p>
            </div>
          </div>
        </div>
      </div>

      {/* Filters */}
      <div className="card-theme p-4">
        <div className="flex flex-col sm:flex-row gap-4">
          <div className="relative flex-1">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-theme-tertiary" />
            <input
              type="text"
              placeholder="Search campaigns..."
              value={search}
              onChange={(e) => { setSearch(e.target.value); setPage(1); }}
              className="input-theme pl-10 w-full"
            />
          </div>
          <div className="flex gap-3">
            <div className="relative">
              <Filter className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-theme-tertiary" />
              <select
                value={statusFilter}
                onChange={(e) => { setStatusFilter(e.target.value as CampaignStatus | ''); setPage(1); }}
                className="input-theme pl-10 pr-8"
              >
                {STATUS_OPTIONS.map(opt => (
                  <option key={opt.value} value={opt.value}>{opt.label}</option>
                ))}
              </select>
            </div>
            <select
              value={typeFilter}
              onChange={(e) => { setTypeFilter(e.target.value as CampaignType | ''); setPage(1); }}
              className="input-theme pr-8"
            >
              {TYPE_OPTIONS.map(opt => (
                <option key={opt.value} value={opt.value}>{opt.label}</option>
              ))}
            </select>
          </div>
        </div>
      </div>

      {/* Campaign List */}
      {campaigns.length === 0 ? (
        <div className="card-theme p-12 text-center">
          <Megaphone className="w-12 h-12 text-theme-tertiary mx-auto mb-4" />
          <h3 className="text-lg font-medium text-theme-primary mb-2">No campaigns yet</h3>
          <p className="text-theme-secondary">Create your first campaign to get started.</p>
        </div>
      ) : (
        <div className="card-theme overflow-hidden">
          <table className="w-full">
            <thead>
              <tr className="border-b border-theme-border">
                <th className="text-left px-4 py-3 text-xs font-medium text-theme-secondary uppercase">Name</th>
                <th className="text-left px-4 py-3 text-xs font-medium text-theme-secondary uppercase">Type</th>
                <th className="text-left px-4 py-3 text-xs font-medium text-theme-secondary uppercase">Status</th>
                <th className="text-left px-4 py-3 text-xs font-medium text-theme-secondary uppercase hidden lg:table-cell">Channels</th>
                <th className="text-right px-4 py-3 text-xs font-medium text-theme-secondary uppercase hidden md:table-cell">Budget</th>
                <th className="text-right px-4 py-3 text-xs font-medium text-theme-secondary uppercase hidden md:table-cell">Spent</th>
                <th className="text-right px-4 py-3 text-xs font-medium text-theme-secondary uppercase">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-theme-border">
              {campaigns.map(campaign => (
                <tr
                  key={campaign.id}
                  className="hover:bg-theme-surface-hover cursor-pointer"
                  onClick={() => navigate(`/app/marketing/campaigns/${campaign.id}`)}
                >
                  <td className="px-4 py-3">
                    <div>
                      <p className="text-sm font-medium text-theme-primary">{campaign.name}</p>
                      <p className="text-xs text-theme-tertiary truncate max-w-xs">{campaign.description}</p>
                    </div>
                  </td>
                  <td className="px-4 py-3">
                    <span className="text-sm text-theme-secondary capitalize">
                      {campaign.campaign_type.replace('_', ' ')}
                    </span>
                  </td>
                  <td className="px-4 py-3">
                    <CampaignStatusBadge status={campaign.status} />
                  </td>
                  <td className="px-4 py-3 hidden lg:table-cell">
                    <div className="flex gap-1 flex-wrap">
                      {campaign.channels.map(ch => (
                        <span
                          key={ch}
                          className="inline-flex items-center px-2 py-0.5 rounded text-xs bg-theme-surface text-theme-secondary"
                        >
                          {ch}
                        </span>
                      ))}
                    </div>
                  </td>
                  <td className="px-4 py-3 text-right text-sm text-theme-secondary hidden md:table-cell">
                    {formatCurrency(campaign.budget_cents)}
                  </td>
                  <td className="px-4 py-3 text-right text-sm text-theme-secondary hidden md:table-cell">
                    {formatCurrency(campaign.spent_cents)}
                  </td>
                  <td className="px-4 py-3 text-right">
                    <div className="relative" onClick={(e) => e.stopPropagation()}>
                      <button
                        onClick={() => setOpenMenuId(openMenuId === campaign.id ? null : campaign.id)}
                        className="p-1 rounded hover:bg-theme-surface-hover text-theme-secondary"
                      >
                        <MoreVertical className="w-4 h-4" />
                      </button>
                      {openMenuId === campaign.id && (
                        <div className="absolute right-0 top-8 z-10 w-40 card-theme-elevated shadow-lg rounded-md py-1">
                          {campaign.status === 'draft' && (
                            <button
                              onClick={() => handleAction('execute', campaign.id)}
                              className="w-full text-left px-3 py-2 text-sm text-theme-primary hover:bg-theme-surface-hover flex items-center gap-2"
                            >
                              <Play className="w-3.5 h-3.5" /> Launch
                            </button>
                          )}
                          {campaign.status === 'active' && (
                            <button
                              onClick={() => handleAction('pause', campaign.id)}
                              className="w-full text-left px-3 py-2 text-sm text-theme-primary hover:bg-theme-surface-hover flex items-center gap-2"
                            >
                              <Pause className="w-3.5 h-3.5" /> Pause
                            </button>
                          )}
                          {campaign.status === 'paused' && (
                            <button
                              onClick={() => handleAction('resume', campaign.id)}
                              className="w-full text-left px-3 py-2 text-sm text-theme-primary hover:bg-theme-surface-hover flex items-center gap-2"
                            >
                              <Play className="w-3.5 h-3.5" /> Resume
                            </button>
                          )}
                          <button
                            onClick={() => handleAction('clone', campaign.id)}
                            className="w-full text-left px-3 py-2 text-sm text-theme-primary hover:bg-theme-surface-hover flex items-center gap-2"
                          >
                            <Copy className="w-3.5 h-3.5" /> Clone
                          </button>
                          <button
                            onClick={() => handleAction('archive', campaign.id)}
                            className="w-full text-left px-3 py-2 text-sm text-theme-primary hover:bg-theme-surface-hover flex items-center gap-2"
                          >
                            <Archive className="w-3.5 h-3.5" /> Archive
                          </button>
                          <button
                            onClick={() => handleAction('delete', campaign.id)}
                            className="w-full text-left px-3 py-2 text-sm text-theme-error hover:bg-theme-surface-hover flex items-center gap-2"
                          >
                            <Trash2 className="w-3.5 h-3.5" /> Delete
                          </button>
                        </div>
                      )}
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {/* Pagination */}
      {pagination && pagination.total_pages > 1 && (
        <div className="flex items-center justify-between">
          <p className="text-sm text-theme-secondary">
            Showing {((page - 1) * (pagination.per_page)) + 1} to{' '}
            {Math.min(page * pagination.per_page, pagination.total_count)} of{' '}
            {pagination.total_count} campaigns
          </p>
          <div className="flex gap-2">
            <button
              disabled={page <= 1}
              onClick={() => setPage(p => p - 1)}
              className="btn-theme btn-theme-secondary btn-theme-sm disabled:opacity-50"
            >
              Previous
            </button>
            <button
              disabled={page >= pagination.total_pages}
              onClick={() => setPage(p => p + 1)}
              className="btn-theme btn-theme-secondary btn-theme-sm disabled:opacity-50"
            >
              Next
            </button>
          </div>
        </div>
      )}
    </div>
  );
};

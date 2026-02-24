import React, { useState } from 'react';
import { Eye, MousePointerClick, ArrowRightLeft, DollarSign, Trophy } from 'lucide-react';
import { useAnalyticsOverview, useChannelAnalytics, useRoiAnalytics, useTopPerformers } from '../hooks/useCampaignAnalytics';
import { CampaignROIChart } from './CampaignROIChart';
import { ChannelPerformanceChart } from './ChannelPerformanceChart';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';

export const CampaignAnalytics: React.FC = () => {
  const [periodDays, setPeriodDays] = useState(30);

  const periodEnd = new Date().toISOString().split('T')[0];
  const periodStart = new Date(Date.now() - periodDays * 86400000).toISOString().split('T')[0];

  const { overview, loading: overviewLoading } = useAnalyticsOverview({ periodStart, periodEnd });
  const { channels, loading: channelsLoading } = useChannelAnalytics({ periodStart, periodEnd });
  const { statistics, loading: roiLoading } = useRoiAnalytics({ periodStart, periodEnd });
  const { performers, loading: performersLoading } = useTopPerformers({ periodStart, periodEnd, limit: 5 });

  const formatCurrency = (cents: number): string => {
    return `$${(cents / 100).toLocaleString('en-US', { minimumFractionDigits: 2 })}`;
  };

  return (
    <div className="space-y-6">
      {/* Period Selector */}
      <div className="flex items-center gap-2">
        {[7, 14, 30, 90].map(days => (
          <button
            key={days}
            onClick={() => setPeriodDays(days)}
            className={`px-3 py-1.5 rounded-lg text-sm font-medium transition-colors ${
              periodDays === days
                ? 'bg-theme-primary text-theme-on-primary'
                : 'bg-theme-surface text-theme-secondary hover:bg-theme-surface-hover'
            }`}
          >
            {days}d
          </button>
        ))}
      </div>

      {/* Key Metrics */}
      {overviewLoading ? (
        <div className="flex items-center justify-center py-8"><LoadingSpinner /></div>
      ) : overview ? (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
          <div className="card-theme p-4">
            <div className="flex items-center gap-3">
              <div className="p-2 rounded-lg bg-theme-info bg-opacity-10">
                <Eye className="w-5 h-5 text-theme-info" />
              </div>
              <div>
                <p className="text-sm text-theme-secondary">Impressions</p>
                <p className="text-xl font-semibold text-theme-primary">
                  {overview.total_impressions.toLocaleString()}
                </p>
              </div>
            </div>
          </div>
          <div className="card-theme p-4">
            <div className="flex items-center gap-3">
              <div className="p-2 rounded-lg bg-theme-warning bg-opacity-10">
                <MousePointerClick className="w-5 h-5 text-theme-warning" />
              </div>
              <div>
                <p className="text-sm text-theme-secondary">Clicks</p>
                <p className="text-xl font-semibold text-theme-primary">
                  {overview.total_clicks.toLocaleString()}
                </p>
              </div>
            </div>
          </div>
          <div className="card-theme p-4">
            <div className="flex items-center gap-3">
              <div className="p-2 rounded-lg bg-theme-success bg-opacity-10">
                <ArrowRightLeft className="w-5 h-5 text-theme-success" />
              </div>
              <div>
                <p className="text-sm text-theme-secondary">Conversions</p>
                <p className="text-xl font-semibold text-theme-primary">
                  {overview.total_conversions.toLocaleString()}
                </p>
              </div>
            </div>
          </div>
          <div className="card-theme p-4">
            <div className="flex items-center gap-3">
              <div className="p-2 rounded-lg bg-theme-primary bg-opacity-10">
                <DollarSign className="w-5 h-5 text-theme-primary" />
              </div>
              <div>
                <p className="text-sm text-theme-secondary">Revenue</p>
                <p className="text-xl font-semibold text-theme-primary">
                  {formatCurrency(overview.total_revenue_cents)}
                </p>
              </div>
            </div>
          </div>
        </div>
      ) : null}

      {/* Charts Row */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <CampaignROIChart statistics={statistics} loading={roiLoading} />
        <ChannelPerformanceChart channels={channels} loading={channelsLoading} />
      </div>

      {/* Top Performers */}
      <div className="card-theme p-6">
        <h3 className="text-lg font-medium text-theme-primary mb-4 flex items-center gap-2">
          <Trophy className="w-5 h-5 text-theme-warning" />
          Top Performing Campaigns
        </h3>
        {performersLoading ? (
          <div className="flex justify-center py-8"><LoadingSpinner /></div>
        ) : performers.length === 0 ? (
          <p className="text-theme-secondary text-center py-8">No performance data available yet.</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead>
                <tr className="border-b border-theme-border">
                  <th className="text-left px-4 py-3 text-xs font-medium text-theme-secondary uppercase">Campaign</th>
                  <th className="text-left px-4 py-3 text-xs font-medium text-theme-secondary uppercase">Type</th>
                  <th className="text-right px-4 py-3 text-xs font-medium text-theme-secondary uppercase">Impressions</th>
                  <th className="text-right px-4 py-3 text-xs font-medium text-theme-secondary uppercase">Conversions</th>
                  <th className="text-right px-4 py-3 text-xs font-medium text-theme-secondary uppercase">Revenue</th>
                  <th className="text-right px-4 py-3 text-xs font-medium text-theme-secondary uppercase">ROI</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-theme-border">
                {performers.map(p => (
                  <tr key={p.campaign_id} className="hover:bg-theme-surface-hover">
                    <td className="px-4 py-3 text-sm font-medium text-theme-primary">{p.campaign_name}</td>
                    <td className="px-4 py-3 text-sm text-theme-secondary capitalize">{p.campaign_type.replace('_', ' ')}</td>
                    <td className="px-4 py-3 text-sm text-theme-primary text-right">{p.impressions.toLocaleString()}</td>
                    <td className="px-4 py-3 text-sm text-theme-primary text-right">{p.conversions.toLocaleString()}</td>
                    <td className="px-4 py-3 text-sm text-theme-primary text-right">{formatCurrency(p.revenue_cents)}</td>
                    <td className="px-4 py-3 text-sm text-right">
                      <span className={`font-medium ${p.roi_percentage >= 0 ? 'text-theme-success' : 'text-theme-error'}`}>
                        {p.roi_percentage >= 0 ? '+' : ''}{p.roi_percentage.toFixed(1)}%
                      </span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  );
};

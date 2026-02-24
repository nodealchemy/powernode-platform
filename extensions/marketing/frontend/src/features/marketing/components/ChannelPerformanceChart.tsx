import React from 'react';
import { BarChart3 } from 'lucide-react';
import type { ChannelAnalytics } from '../types';

interface ChannelPerformanceChartProps {
  channels: ChannelAnalytics[];
  loading?: boolean;
}

export const ChannelPerformanceChart: React.FC<ChannelPerformanceChartProps> = ({ channels, loading }) => {
  if (loading) {
    return (
      <div className="card-theme p-6">
        <h3 className="text-lg font-medium text-theme-primary mb-4">Channel Performance</h3>
        <div className="animate-pulse space-y-4">
          {[1, 2, 3].map(i => (
            <div key={i} className="h-12 bg-theme-surface rounded" />
          ))}
        </div>
      </div>
    );
  }

  if (channels.length === 0) {
    return (
      <div className="card-theme p-6">
        <h3 className="text-lg font-medium text-theme-primary mb-4">Channel Performance</h3>
        <div className="text-center py-8">
          <BarChart3 className="w-10 h-10 text-theme-tertiary mx-auto mb-3" />
          <p className="text-theme-secondary">No channel data available.</p>
        </div>
      </div>
    );
  }

  const maxImpressions = Math.max(...channels.map(c => c.impressions), 1);
  const formatCurrency = (cents: number): string => {
    return `$${(cents / 100).toLocaleString('en-US', { minimumFractionDigits: 2 })}`;
  };

  return (
    <div className="card-theme p-6">
      <h3 className="text-lg font-medium text-theme-primary mb-4">Channel Performance</h3>

      <div className="space-y-4">
        {channels.map(channel => (
          <div key={channel.channel} className="space-y-2">
            <div className="flex items-center justify-between">
              <span className="text-sm font-medium text-theme-primary capitalize">{channel.channel}</span>
              <span className="text-xs text-theme-secondary">
                {channel.impressions.toLocaleString()} impressions
              </span>
            </div>

            {/* Bar */}
            <div className="h-6 bg-theme-surface rounded-full overflow-hidden">
              <div
                className="h-full bg-theme-info rounded-full transition-all"
                style={{ width: `${(channel.impressions / maxImpressions) * 100}%` }}
              />
            </div>

            {/* Stats Row */}
            <div className="flex items-center gap-4 text-xs">
              <span className="text-theme-secondary">
                CTR: <span className="text-theme-primary font-medium">{channel.click_rate.toFixed(1)}%</span>
              </span>
              <span className="text-theme-secondary">
                Conv: <span className="text-theme-primary font-medium">{channel.conversion_rate.toFixed(1)}%</span>
              </span>
              <span className="text-theme-secondary">
                Revenue: <span className="text-theme-primary font-medium">{formatCurrency(channel.revenue_cents)}</span>
              </span>
              <span className="text-theme-secondary">
                ROI: <span className={`font-medium ${channel.roi_percentage >= 0 ? 'text-theme-success' : 'text-theme-error'}`}>
                  {channel.roi_percentage >= 0 ? '+' : ''}{channel.roi_percentage.toFixed(1)}%
                </span>
              </span>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
};

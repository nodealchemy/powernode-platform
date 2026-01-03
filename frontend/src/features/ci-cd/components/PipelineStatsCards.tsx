import React from 'react';
import { Play, Clock, TrendingUp, Activity } from 'lucide-react';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import type { PipelineStats } from '../types';

interface PipelineStatsCardsProps {
  stats: PipelineStats | null;
  loading?: boolean;
  className?: string;
}

export const PipelineStatsCards: React.FC<PipelineStatsCardsProps> = ({
  stats,
  loading = false,
  className = '',
}) => {
  const formatDuration = (seconds: number): string => {
    if (seconds < 60) return `${Math.round(seconds)}s`;
    if (seconds < 3600) return `${Math.round(seconds / 60)}m`;
    return `${Math.round(seconds / 3600)}h ${Math.round((seconds % 3600) / 60)}m`;
  };

  const cards = [
    {
      label: 'Total Runs',
      value: stats?.total_runs ?? 0,
      icon: Play,
      color: 'bg-theme-primary/10 text-theme-primary',
    },
    {
      label: 'Success Rate',
      value: `${stats?.success_rate ?? 0}%`,
      icon: TrendingUp,
      color: 'bg-theme-success/10 text-theme-success',
    },
    {
      label: 'Avg Duration',
      value: stats ? formatDuration(stats.avg_duration_seconds) : '-',
      icon: Clock,
      color: 'bg-theme-warning/10 text-theme-warning',
    },
    {
      label: 'Active Runs',
      value: stats?.active_runs ?? 0,
      icon: Activity,
      color: 'bg-theme-info/10 text-theme-info',
    },
  ];

  if (loading) {
    return (
      <div className={`flex items-center justify-center py-8 ${className}`}>
        <LoadingSpinner size="md" />
        <span className="ml-3 text-theme-secondary">Loading stats...</span>
      </div>
    );
  }

  return (
    <div className={`grid grid-cols-1 md:grid-cols-4 gap-4 ${className}`}>
      {cards.map((card) => (
        <div
          key={card.label}
          className="bg-theme-surface rounded-lg p-4 border border-theme"
        >
          <div className="flex items-center gap-3">
            <div className={`p-2 rounded-lg ${card.color}`}>
              <card.icon className="w-5 h-5" />
            </div>
            <div>
              <p className="text-sm text-theme-secondary">{card.label}</p>
              <p className="text-2xl font-semibold text-theme-primary">
                {card.value}
              </p>
            </div>
          </div>
        </div>
      ))}
    </div>
  );
};

export default PipelineStatsCards;

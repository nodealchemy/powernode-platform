import React from 'react';
import { Play, CheckCircle, TrendingUp, Activity } from 'lucide-react';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';

interface PipelineStats {
  total: number;
  active_count: number;
  total_runs: number;
}

interface PipelineStatsCardsProps {
  stats: PipelineStats | null;
  loading: boolean;
}

interface StatCardProps {
  title: string;
  value: number | string;
  icon: React.ElementType;
  iconColor: string;
  trend?: string;
}

const StatCard: React.FC<StatCardProps> = ({ title, value, icon: Icon, iconColor, trend }) => (
  <div className="bg-theme-surface rounded-lg border border-theme p-4">
    <div className="flex items-center justify-between">
      <div>
        <p className="text-sm text-theme-secondary">{title}</p>
        <p className="text-2xl font-semibold text-theme-primary mt-1">{value}</p>
        {trend && (
          <p className="text-xs text-theme-success mt-1 flex items-center gap-1">
            <TrendingUp className="w-3 h-3" />
            {trend}
          </p>
        )}
      </div>
      <div className={`p-3 rounded-lg ${iconColor}`}>
        <Icon className="w-6 h-6" />
      </div>
    </div>
  </div>
);

export const PipelineStatsCards: React.FC<PipelineStatsCardsProps> = ({ stats, loading }) => {
  if (loading) {
    return (
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        {[1, 2, 3, 4].map((i) => (
          <div key={i} className="bg-theme-surface rounded-lg border border-theme p-4 h-24 flex items-center justify-center">
            <LoadingSpinner size="sm" />
          </div>
        ))}
      </div>
    );
  }

  if (!stats) {
    return null;
  }

  return (
    <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
      <StatCard
        title="Total Pipelines"
        value={stats.total}
        icon={Play}
        iconColor="bg-theme-primary/10 text-theme-primary"
      />
      <StatCard
        title="Active Pipelines"
        value={stats.active_count}
        icon={Activity}
        iconColor="bg-theme-success/10 text-theme-success"
      />
      <StatCard
        title="Total Runs"
        value={stats.total_runs}
        icon={CheckCircle}
        iconColor="bg-theme-info/10 text-theme-info"
      />
      <StatCard
        title="Success Rate"
        value={stats.total_runs > 0 ? `${Math.round((stats.active_count / stats.total) * 100)}%` : '-'}
        icon={TrendingUp}
        iconColor="bg-theme-warning/10 text-theme-warning"
      />
    </div>
  );
};

export default PipelineStatsCards;

import React from 'react';
import { Shield, AlertTriangle, Activity, Clock } from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useSecurityReport } from '../api/securityExtApi';

export const SecurityScoreCard: React.FC = () => {
  const { data: report, isLoading } = useSecurityReport({ period_days: 30 });

  if (isLoading) {
    return <LoadingSpinner size="sm" className="py-4" />;
  }

  const stats = [
    {
      label: 'Active Quarantines',
      value: report?.active_quarantines ?? 0,
      icon: Shield,
      colorClass: 'text-theme-error',
      bgClass: 'bg-theme-error',
    },
    {
      label: 'Total Events (30d)',
      value: report?.total_events ?? 0,
      icon: Activity,
      colorClass: 'text-theme-warning',
      bgClass: 'bg-theme-warning',
    },
    {
      label: 'Restoration Rate',
      value: report?.restoration_rate != null ? `${Math.round(report.restoration_rate * 100)}%` : '--',
      icon: AlertTriangle,
      colorClass: 'text-theme-success',
      bgClass: 'bg-theme-success',
    },
    {
      label: 'Avg Duration (hrs)',
      value: report?.avg_quarantine_duration_hours != null
        ? report.avg_quarantine_duration_hours.toFixed(1)
        : '--',
      icon: Clock,
      colorClass: 'text-theme-info',
      bgClass: 'bg-theme-info',
    },
  ];

  return (
    <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-6">
      {stats.map((stat) => {
        const Icon = stat.icon;
        return (
          <Card key={stat.label} className="p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-theme-tertiary">{stat.label}</p>
                <p className="text-2xl font-semibold text-theme-primary">
                  {typeof stat.value === 'number' ? stat.value.toLocaleString() : stat.value}
                </p>
              </div>
              <div className={`h-10 w-10 ${stat.bgClass} bg-opacity-10 rounded-lg flex items-center justify-center`}>
                <Icon className={`h-5 w-5 ${stat.colorClass}`} />
              </div>
            </div>
          </Card>
        );
      })}
    </div>
  );
};

import React, { useState, useEffect, useCallback } from 'react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { LoadingSpinner, Card, Button } from '@/shared/components/ui';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { usageApi } from '../services/usageApi';
import { QuotaProgress } from '../components/QuotaProgress';
import { UsageChart } from '../components/UsageChart';
import { UsageHistory } from '../components/UsageHistory';
import type { UsageDashboardData, MeterUsageSummary } from '../types';

export const UsageDashboard: React.FC = () => {
  const { addNotification } = useNotifications();
  const [loading, setLoading] = useState(true);
  const [dashboardData, setDashboardData] = useState<UsageDashboardData | null>(null);
  const [error, setError] = useState<string | null>(null);

  const loadData = useCallback(async () => {
    setLoading(true);
    setError(null);

    try {
      const result = await usageApi.getDashboard();

      if (result.success && result.data) {
        setDashboardData(result.data);
      } else {
        setError(result.error || 'Failed to load usage data');
      }
    } catch (_error) {
      setError('An error occurred while loading data');
      addNotification({ type: 'error', message: 'Failed to load usage data' });
    } finally {
      setLoading(false);
    }
  }, [addNotification]);

  useEffect(() => {
    loadData();
  }, [loadData]);

  const handleExport = async () => {
    if (!dashboardData) return;

    try {
      const result = await usageApi.exportUsage({
        start_date: dashboardData.period.start,
        end_date: dashboardData.period.end,
        format: 'csv',
      });

      if (result instanceof Blob) {
        const url = URL.createObjectURL(result);
        const a = document.createElement('a');
        a.href = url;
        a.download = `usage_export_${dashboardData.period.start}_${dashboardData.period.end}.csv`;
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        URL.revokeObjectURL(url);
        addNotification({ type: 'success', message: 'Export downloaded successfully' });
      }
    } catch (_error) {
      addNotification({ type: 'error', message: 'Failed to export data' });
    }
  };

  const formatCurrency = (amount: number) => {
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: 'USD',
    }).format(amount);
  };

  const formatNumber = (num: number) => {
    return new Intl.NumberFormat('en-US').format(num);
  };

  const formatPeriod = (start: string, end: string) => {
    const startDate = new Date(start);
    const endDate = new Date(end);
    return `${startDate.toLocaleDateString('en-US', { month: 'short', day: 'numeric' })} - ${endDate.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })}`;
  };

  if (loading) {
    return (
      <PageContainer title="Usage Dashboard">
        <div className="flex items-center justify-center h-64">
          <LoadingSpinner size="lg" />
        </div>
      </PageContainer>
    );
  }

  if (error) {
    return (
      <PageContainer title="Usage Dashboard">
        <Card className="p-8 text-center">
          <h3 className="text-lg font-semibold text-theme-primary mb-2">Error Loading Data</h3>
          <p className="text-theme-secondary mb-4">{error}</p>
          <Button onClick={loadData}>Retry</Button>
        </Card>
      </PageContainer>
    );
  }

  if (!dashboardData) {
    return (
      <PageContainer title="Usage Dashboard">
        <Card className="p-8 text-center">
          <h3 className="text-lg font-semibold text-theme-primary mb-2">No Usage Data</h3>
          <p className="text-theme-secondary">Start tracking usage events to see your dashboard.</p>
        </Card>
      </PageContainer>
    );
  }

  const totalUsage = dashboardData.meters.reduce((sum, m) => sum + m.total_usage, 0);
  const totalCost = dashboardData.meters.reduce((sum, m) => sum + m.calculated_cost, 0);
  const totalEvents = dashboardData.meters.reduce((sum, m) => sum + m.event_count, 0);
  const metersExceeded = dashboardData.quotas.filter((q) => q.exceeded).length;

  return (
    <PageContainer
      title="Usage Dashboard"
      description={`Current billing period: ${formatPeriod(dashboardData.period.start, dashboardData.period.end)}`}
      actions={[
        {
          label: 'Export Usage',
          onClick: handleExport,
          variant: 'secondary',
        },
      ]}
    >
      {/* Summary Cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mb-6">
        <Card className="p-6">
          <p className="text-sm text-theme-tertiary mb-1">Total Usage</p>
          <p className="text-3xl font-bold text-theme-primary">{formatNumber(totalUsage)}</p>
          <p className="text-sm text-theme-tertiary">units</p>
        </Card>
        <Card className="p-6">
          <p className="text-sm text-theme-tertiary mb-1">Calculated Cost</p>
          <p className="text-3xl font-bold text-theme-primary">{formatCurrency(totalCost)}</p>
          <p className="text-sm text-theme-tertiary">this period</p>
        </Card>
        <Card className="p-6">
          <p className="text-sm text-theme-tertiary mb-1">Events Tracked</p>
          <p className="text-3xl font-bold text-theme-primary">{formatNumber(totalEvents)}</p>
          <p className="text-sm text-theme-tertiary">total events</p>
        </Card>
        <Card className="p-6">
          <p className="text-sm text-theme-tertiary mb-1">Quota Status</p>
          <p className={`text-3xl font-bold ${metersExceeded > 0 ? 'text-theme-error' : 'text-theme-success'}`}>
            {metersExceeded > 0 ? `${metersExceeded} Exceeded` : 'All OK'}
          </p>
          <p className="text-sm text-theme-tertiary">{dashboardData.quotas.length} quotas configured</p>
        </Card>
      </div>

      {/* Main Content */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-6">
        <UsageChart trends={dashboardData.trends} />
        <QuotaProgress quotas={dashboardData.quotas} />
      </div>

      {/* Meters Summary */}
      <Card className="p-6 mb-6">
        <h3 className="text-lg font-semibold text-theme-primary mb-4">Usage by Meter</h3>
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {dashboardData.meters.map((meter: MeterUsageSummary) => (
            <div
              key={meter.id}
              className="p-4 rounded-lg bg-theme-surface border border-theme"
            >
              <div className="flex items-center justify-between mb-2">
                <span className="font-medium text-theme-primary">{meter.name}</span>
                {meter.quota_exceeded && (
                  <span className="px-2 py-1 text-xs font-medium rounded bg-theme-error-background text-theme-error">
                    Exceeded
                  </span>
                )}
              </div>
              <p className="text-2xl font-bold text-theme-primary">
                {formatNumber(meter.total_usage)}
                <span className="text-sm font-normal text-theme-tertiary ml-1">{meter.unit_name}</span>
              </p>
              <div className="flex items-center justify-between mt-2 text-sm text-theme-tertiary">
                <span>{formatNumber(meter.event_count)} events</span>
                {meter.is_billable && (
                  <span className="text-theme-primary">{formatCurrency(meter.calculated_cost)}</span>
                )}
              </div>
              {meter.quota_limit && (
                <div className="mt-2">
                  <div className="w-full bg-theme-tertiary rounded-full h-1.5">
                    <div
                      className={`h-1.5 rounded-full ${meter.quota_exceeded ? 'bg-theme-error' : 'bg-theme-interactive-primary'}`}
                      style={{ width: `${Math.min(meter.quota_percent, 100)}%` }}
                    />
                  </div>
                </div>
              )}
            </div>
          ))}
        </div>
      </Card>

      {/* Recent Events */}
      <UsageHistory events={dashboardData.recent_events} onExport={handleExport} />
    </PageContainer>
  );
};

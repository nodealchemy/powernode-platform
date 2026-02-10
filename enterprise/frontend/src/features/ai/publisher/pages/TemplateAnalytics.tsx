import React, { useState, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { useNotifications } from '@/shared/hooks/useNotifications';
import publisherApi from '../services/publisherApi';
import { EarningsChart } from '../components/EarningsChart';
import { TemplatePerformance } from '../components/TemplatePerformance';
import type { PublisherAnalytics } from '../types';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';

const formatCurrency = (value: number): string => {
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
  }).format(value);
};

const formatNumber = (value: number): string => {
  return new Intl.NumberFormat('en-US').format(value);
};

export const TemplateAnalyticsPage: React.FC = () => {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { showNotification } = useNotifications();
  const [analytics, setAnalytics] = useState<PublisherAnalytics | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [period, setPeriod] = useState<number>(30);

  useEffect(() => {
    const fetchAnalytics = async () => {
      if (!id) return;

      setIsLoading(true);
      try {
        const response = await publisherApi.getPublisherAnalytics(id, { period });
        setAnalytics(response.data);
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Failed to load analytics';
        showNotification(message, 'error');
      } finally {
        setIsLoading(false);
      }
    };

    fetchAnalytics();
  }, [id, period, showNotification]);

  const StatCard: React.FC<{
    label: string;
    value: string | number;
    subValue?: string;
    trend?: { value: number; isPositive: boolean };
  }> = ({ label, value, subValue, trend }) => (
    <div className="bg-theme-bg-primary rounded-lg p-6 border border-theme-border">
      <p className="text-sm font-medium text-theme-text-secondary">{label}</p>
      <p className="mt-2 text-3xl font-bold text-theme-text-primary">{value}</p>
      {subValue && (
        <p className="mt-1 text-sm text-theme-text-secondary">{subValue}</p>
      )}
      {trend && (
        <div className={`mt-2 flex items-center text-sm ${trend.isPositive ? 'text-theme-success' : 'text-theme-error'}`}>
          <svg
            className={`w-4 h-4 mr-1 ${trend.isPositive ? '' : 'transform rotate-180'}`}
            fill="currentColor"
            viewBox="0 0 20 20"
          >
            <path fillRule="evenodd" d="M5.293 9.707a1 1 0 010-1.414l4-4a1 1 0 011.414 0l4 4a1 1 0 01-1.414 1.414L11 7.414V15a1 1 0 11-2 0V7.414L6.707 9.707a1 1 0 01-1.414 0z" clipRule="evenodd" />
          </svg>
          {trend.value}%
        </div>
      )}
    </div>
  );

  if (isLoading) {
    return (
      <PageContainer title="Template Analytics">
        <LoadingSpinner className="h-64" />
      </PageContainer>
    );
  }

  if (!analytics) {
    return (
      <PageContainer title="Template Analytics">
        <div className="text-center py-16">
          <p className="text-theme-text-secondary">No analytics data available</p>
        </div>
      </PageContainer>
    );
  }

  return (
    <PageContainer
      title="Publisher Analytics"
      actions={[
        {
          label: 'Back to Dashboard',
          onClick: () => navigate('/ai/publisher/dashboard'),
          variant: 'outline',
        },
      ]}
    >
      {/* Period Selector */}
      <div className="mb-6">
        <select
          value={period}
          onChange={(e) => setPeriod(Number(e.target.value))}
          className="bg-theme-bg-secondary border border-theme-border rounded-lg px-4 py-2 text-theme-text-primary"
        >
          <option value={7}>Last 7 days</option>
          <option value={30}>Last 30 days</option>
          <option value={90}>Last 90 days</option>
          <option value={365}>Last year</option>
        </select>
      </div>

      {/* Period Info */}
      <div className="bg-theme-bg-secondary rounded-lg p-4 mb-6">
        <p className="text-theme-text-secondary">
          Analytics for{' '}
          <span className="font-medium text-theme-text-primary">
            {new Date(analytics.period.start).toLocaleDateString()} -{' '}
            {new Date(analytics.period.end).toLocaleDateString()}
          </span>
        </p>
      </div>

      {/* Summary Stats */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
        <StatCard
          label="Total Revenue"
          value={formatCurrency(analytics.summary.total_revenue)}
          subValue={`Publisher: ${formatCurrency(analytics.summary.publisher_revenue)}`}
        />
        <StatCard
          label="Net Installations"
          value={formatNumber(analytics.summary.net_installations)}
          subValue={`+${formatNumber(analytics.summary.total_installations)} / -${formatNumber(analytics.summary.total_uninstallations)}`}
        />
        <StatCard
          label="Total Executions"
          value={formatNumber(analytics.summary.total_executions)}
        />
        <StatCard
          label="Page Views"
          value={formatNumber(analytics.summary.page_views)}
          subValue={`${formatNumber(analytics.summary.unique_visitors)} unique visitors`}
        />
      </div>

      {/* Revenue Chart */}
      <div className="mb-6">
        <EarningsChart data={analytics.daily_metrics} type="revenue" height={400} />
      </div>

      {/* Platform Commission */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
        <div className="bg-theme-bg-primary rounded-lg p-6 border border-theme-border">
          <p className="text-sm font-medium text-theme-text-secondary">Gross Revenue</p>
          <p className="mt-2 text-2xl font-bold text-theme-text-primary">
            {formatCurrency(analytics.summary.total_revenue)}
          </p>
        </div>
        <div className="bg-theme-bg-primary rounded-lg p-6 border border-theme-border">
          <p className="text-sm font-medium text-theme-text-secondary">Platform Commission</p>
          <p className="mt-2 text-2xl font-bold text-theme-error">
            -{formatCurrency(analytics.summary.platform_commission)}
          </p>
        </div>
        <div className="bg-theme-bg-primary rounded-lg p-6 border border-theme-border">
          <p className="text-sm font-medium text-theme-text-secondary">Your Earnings</p>
          <p className="mt-2 text-2xl font-bold text-theme-success">
            {formatCurrency(analytics.summary.publisher_revenue)}
          </p>
        </div>
      </div>

      {/* Template Breakdown */}
      <div>
        <h3 className="text-lg font-semibold text-theme-text-primary mb-4">
          Template Performance
        </h3>
        <TemplatePerformance templates={analytics.template_breakdown} showChart={true} />
      </div>
    </PageContainer>
  );
};

export default TemplateAnalyticsPage;

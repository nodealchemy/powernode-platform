import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { Button } from '@/shared/components/ui/Button';
import { useNotifications } from '@/shared/hooks/useNotifications';
import publisherApi from '../services/publisherApi';
import { EarningsChart } from '../components/EarningsChart';
import { PayoutManager } from '../components/PayoutManager';
import { TemplatePerformance } from '../components/TemplatePerformance';
import type {
  Publisher,
  PublisherDashboardStats,
  PublisherEarnings,
  Transaction,
} from '../types';

const formatCurrency = (value: number): string => {
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
  }).format(value);
};

const formatNumber = (value: number): string => {
  return new Intl.NumberFormat('en-US').format(value);
};

export const PublisherDashboard: React.FC = () => {
  const navigate = useNavigate();
  const { showNotification } = useNotifications();
  const [publisher, setPublisher] = useState<Publisher | null>(null);
  const [dashboardStats, setDashboardStats] = useState<PublisherDashboardStats | null>(null);
  const [earnings, setEarnings] = useState<PublisherEarnings | null>(null);
  const [payouts, setPayouts] = useState<Transaction[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [activeTab, setActiveTab] = useState<'overview' | 'templates' | 'earnings' | 'payouts'>('overview');

  const fetchData = async () => {
    setIsLoading(true);
    try {
      // First get the publisher profile
      const publisherResponse = await publisherApi.getMyPublisher();
      setPublisher(publisherResponse.data);

      // Then fetch dashboard data
      const [dashboardResponse, earningsResponse, payoutsResponse] = await Promise.all([
        publisherApi.getPublisherDashboard(publisherResponse.data.id),
        publisherApi.getPublisherEarnings(publisherResponse.data.id),
        publisherApi.getPublisherPayouts(publisherResponse.data.id),
      ]);

      setDashboardStats(dashboardResponse.data);
      setEarnings(earningsResponse.data);
      setPayouts(payoutsResponse.data);
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to load publisher data';
      if (message.includes('not found') || message.includes('404')) {
        // No publisher profile - could redirect to setup
        showNotification('No publisher profile found. Create one to get started.', 'info');
      } else {
        showNotification(message, 'error');
      }
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    fetchData();
  }, []);

  const StatCard: React.FC<{
    label: string;
    value: string | number;
    subValue?: string;
    trend?: { value: number; isPositive: boolean };
    icon?: React.ReactNode;
  }> = ({ label, value, subValue, trend, icon }) => (
    <div className="bg-theme-bg-primary rounded-lg p-6 border border-theme-border">
      <div className="flex items-center justify-between">
        <p className="text-sm font-medium text-theme-text-secondary">{label}</p>
        {icon}
      </div>
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
      <PageContainer title="Publisher Dashboard">
        <div className="flex items-center justify-center h-64">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-theme-primary" />
        </div>
      </PageContainer>
    );
  }

  if (!publisher) {
    return (
      <PageContainer
        title="Become a Publisher"
        actions={[
          {
            label: 'Create Publisher Profile',
            onClick: () => navigate('/ai/publisher/setup'),
            variant: 'primary',
          },
        ]}
      >
        <div className="text-center py-16 bg-theme-bg-primary rounded-lg border border-theme-border">
          <svg
            className="mx-auto h-16 w-16 text-theme-text-secondary"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor"
          >
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              strokeWidth={2}
              d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10"
            />
          </svg>
          <h3 className="mt-4 text-lg font-medium text-theme-text-primary">
            Start Selling Your AI Templates
          </h3>
          <p className="mt-2 text-theme-text-secondary max-w-md mx-auto">
            Create a publisher profile to list your AI agent templates in the marketplace
            and earn revenue from every sale.
          </p>
          <Button
            variant="primary"
            className="mt-6"
            onClick={() => navigate('/ai/publisher/setup')}
          >
            Get Started
          </Button>
        </div>
      </PageContainer>
    );
  }

  const tabs = [
    { id: 'overview', label: 'Overview' },
    { id: 'templates', label: 'Templates' },
    { id: 'earnings', label: 'Earnings' },
    { id: 'payouts', label: 'Payouts' },
  ];

  return (
    <PageContainer
      title="Publisher Dashboard"
      actions={[
        {
          label: 'View Analytics',
          onClick: () => navigate('/ai/publisher/analytics'),
          variant: 'outline',
        },
        {
          label: 'Create Template',
          onClick: () => navigate('/ai/workflows?action=create'),
          variant: 'primary',
        },
      ]}
    >
      {/* Publisher Header */}
      <div className="bg-theme-bg-primary rounded-lg p-6 border border-theme-border mb-6">
        <div className="flex items-center gap-4">
          <div className="w-16 h-16 rounded-full bg-theme-primary/10 flex items-center justify-center">
            <span className="text-2xl font-bold text-theme-primary">
              {publisher.publisher_name.charAt(0).toUpperCase()}
            </span>
          </div>
          <div className="flex-1">
            <h2 className="text-xl font-bold text-theme-text-primary">
              {publisher.publisher_name}
            </h2>
            <p className="text-theme-text-secondary">@{publisher.publisher_slug}</p>
          </div>
          <div className="flex items-center gap-2">
            <span className={`px-3 py-1 rounded-full text-sm font-medium ${
              publisher.status === 'active'
                ? 'bg-theme-success-background text-theme-success'
                : 'bg-theme-warning-background text-theme-warning'
            }`}>
              {publisher.status.charAt(0).toUpperCase() + publisher.status.slice(1)}
            </span>
            {publisher.verification_status === 'verified' && (
              <span className="flex items-center text-theme-interactive-primary">
                <svg className="w-5 h-5" fill="currentColor" viewBox="0 0 20 20">
                  <path fillRule="evenodd" d="M6.267 3.455a3.066 3.066 0 001.745-.723 3.066 3.066 0 013.976 0 3.066 3.066 0 001.745.723 3.066 3.066 0 012.812 2.812c.051.643.304 1.254.723 1.745a3.066 3.066 0 010 3.976 3.066 3.066 0 00-.723 1.745 3.066 3.066 0 01-2.812 2.812 3.066 3.066 0 00-1.745.723 3.066 3.066 0 01-3.976 0 3.066 3.066 0 00-1.745-.723 3.066 3.066 0 01-2.812-2.812 3.066 3.066 0 00-.723-1.745 3.066 3.066 0 010-3.976 3.066 3.066 0 00.723-1.745 3.066 3.066 0 012.812-2.812zm7.44 5.252a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clipRule="evenodd" />
                </svg>
              </span>
            )}
          </div>
        </div>
      </div>

      {/* Tabs */}
      <div className="border-b border-theme-border mb-6">
        <nav className="-mb-px flex space-x-8">
          {tabs.map((tab) => (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id as typeof activeTab)}
              className={`py-4 px-1 border-b-2 font-medium text-sm ${
                activeTab === tab.id
                  ? 'border-theme-primary text-theme-primary'
                  : 'border-transparent text-theme-text-secondary hover:text-theme-text-primary hover:border-theme-border'
              }`}
            >
              {tab.label}
            </button>
          ))}
        </nav>
      </div>

      {/* Overview Tab */}
      {activeTab === 'overview' && dashboardStats && (
        <div className="space-y-6">
          {/* Stats Grid */}
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
            <StatCard
              label="Total Templates"
              value={dashboardStats.overview.total_templates}
              subValue={`${dashboardStats.overview.active_templates} active`}
            />
            <StatCard
              label="Total Installations"
              value={formatNumber(dashboardStats.overview.total_installations)}
              subValue={`${formatNumber(dashboardStats.overview.active_installations)} active`}
            />
            <StatCard
              label="Lifetime Earnings"
              value={formatCurrency(dashboardStats.earnings.lifetime_earnings)}
              subValue={`${dashboardStats.earnings.revenue_share}% revenue share`}
            />
            <StatCard
              label="Average Rating"
              value={dashboardStats.overview.average_rating?.toFixed(1) || '-'}
              subValue={`${formatNumber(dashboardStats.overview.total_reviews)} reviews`}
            />
          </div>

          {/* Charts Row */}
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
            {earnings && (
              <EarningsChart data={earnings.history} type="earnings" />
            )}
            <div className="bg-theme-bg-primary rounded-lg p-6 border border-theme-border">
              <h3 className="text-lg font-semibold text-theme-text-primary mb-4">
                Quick Stats
              </h3>
              <div className="space-y-4">
                <div className="flex justify-between items-center">
                  <span className="text-theme-text-secondary">Pending Payout</span>
                  <span className="font-medium text-theme-text-primary">
                    {formatCurrency(dashboardStats.earnings.pending_payout)}
                  </span>
                </div>
                <div className="flex justify-between items-center">
                  <span className="text-theme-text-secondary">Pending Templates</span>
                  <span className="font-medium text-theme-text-primary">
                    {dashboardStats.overview.pending_templates}
                  </span>
                </div>
                <div className="flex justify-between items-center">
                  <span className="text-theme-text-secondary">Active Installations</span>
                  <span className="font-medium text-theme-text-primary">
                    {formatNumber(dashboardStats.overview.active_installations)}
                  </span>
                </div>
              </div>
            </div>
          </div>

          {/* Top Templates */}
          {dashboardStats.top_templates.length > 0 && (
            <div>
              <h3 className="text-lg font-semibold text-theme-text-primary mb-4">
                Top Performing Templates
              </h3>
              <TemplatePerformance templates={dashboardStats.top_templates} showChart={false} />
            </div>
          )}

          {/* Recent Sales */}
          {dashboardStats.recent_sales.length > 0 && (
            <div className="bg-theme-bg-primary rounded-lg p-6 border border-theme-border">
              <h3 className="text-lg font-semibold text-theme-text-primary mb-4">
                Recent Sales
              </h3>
              <div className="space-y-3">
                {dashboardStats.recent_sales.map((sale) => (
                  <div
                    key={sale.id}
                    className="flex items-center justify-between p-4 bg-theme-bg-secondary rounded-lg"
                  >
                    <div>
                      <p className="font-medium text-theme-text-primary">
                        {sale.template_name}
                      </p>
                      <p className="text-sm text-theme-text-secondary">
                        {new Date(sale.created_at).toLocaleDateString()}
                      </p>
                    </div>
                    <p className="font-medium text-theme-success">
                      +{formatCurrency(sale.publisher_amount)}
                    </p>
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>
      )}

      {/* Templates Tab */}
      {activeTab === 'templates' && dashboardStats && (
        <TemplatePerformance templates={dashboardStats.top_templates} showChart={true} />
      )}

      {/* Earnings Tab */}
      {activeTab === 'earnings' && earnings && (
        <div className="space-y-6">
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
            <StatCard
              label="Lifetime Earnings"
              value={formatCurrency(earnings.current.lifetime_earnings)}
            />
            <StatCard
              label="Pending Payout"
              value={formatCurrency(earnings.current.pending_payout)}
            />
            <StatCard
              label="Revenue Share"
              value={`${earnings.current.revenue_share_percentage}%`}
            />
          </div>
          <EarningsChart data={earnings.history} type="earnings" height={400} />
        </div>
      )}

      {/* Payouts Tab */}
      {activeTab === 'payouts' && publisher && earnings && (
        <PayoutManager
          publisherId={publisher.id}
          pendingPayout={earnings.current.pending_payout}
          payoutEnabled={earnings.current.payout_enabled}
          payouts={payouts}
          onPayoutRequested={fetchData}
        />
      )}
    </PageContainer>
  );
};

export default PublisherDashboard;

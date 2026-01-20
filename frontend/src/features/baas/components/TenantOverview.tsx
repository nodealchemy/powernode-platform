import React from 'react';
import type { BaaSDashboardStats, BaaSTenant } from '../types';

interface TenantOverviewProps {
  tenant: BaaSTenant;
  stats: BaaSDashboardStats;
}

const formatCurrency = (cents: number): string => {
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
  }).format(cents);
};

const formatNumber = (value: number): string => {
  return new Intl.NumberFormat('en-US').format(value);
};

export const TenantOverview: React.FC<TenantOverviewProps> = ({ tenant, stats }) => {
  const getTierBadge = (tier: string) => {
    const styles: Record<string, string> = {
      free: 'bg-gray-100 text-gray-800',
      starter: 'bg-blue-100 text-blue-800',
      pro: 'bg-purple-100 text-purple-800',
      enterprise: 'bg-yellow-100 text-yellow-800',
    };
    return (
      <span className={`px-3 py-1 rounded-full text-sm font-medium ${styles[tier] || styles.free}`}>
        {tier.charAt(0).toUpperCase() + tier.slice(1)}
      </span>
    );
  };

  const getUsagePercentage = (used: number, max: number | null): number => {
    if (max === null) return 0;
    return Math.min((used / max) * 100, 100);
  };

  const getUsageColor = (percentage: number): string => {
    if (percentage >= 90) return 'bg-red-500';
    if (percentage >= 75) return 'bg-yellow-500';
    return 'bg-green-500';
  };

  return (
    <div className="space-y-6">
      {/* Tenant Header */}
      <div className="bg-theme-bg-primary rounded-lg p-6 border border-theme-border">
        <div className="flex items-center justify-between">
          <div>
            <h2 className="text-xl font-bold text-theme-text-primary">{tenant.name}</h2>
            <p className="text-theme-text-secondary">@{tenant.slug}</p>
          </div>
          <div className="flex items-center gap-3">
            {getTierBadge(tenant.tier)}
            <span className={`px-3 py-1 rounded-full text-sm font-medium ${
              tenant.status === 'active' ? 'bg-green-100 text-green-800' : 'bg-red-100 text-red-800'
            }`}>
              {tenant.status.charAt(0).toUpperCase() + tenant.status.slice(1)}
            </span>
          </div>
        </div>
      </div>

      {/* Overview Stats */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        <div className="bg-theme-bg-primary rounded-lg p-6 border border-theme-border">
          <p className="text-sm font-medium text-theme-text-secondary">Total Customers</p>
          <p className="mt-2 text-3xl font-bold text-theme-text-primary">
            {formatNumber(stats.overview.total_customers)}
          </p>
          <p className="mt-1 text-sm text-theme-text-secondary">
            +{formatNumber(stats.recent_activity.new_customers_30d)} last 30 days
          </p>
        </div>

        <div className="bg-theme-bg-primary rounded-lg p-6 border border-theme-border">
          <p className="text-sm font-medium text-theme-text-secondary">Active Subscriptions</p>
          <p className="mt-2 text-3xl font-bold text-theme-text-primary">
            {formatNumber(stats.overview.active_subscriptions)}
          </p>
          <p className="mt-1 text-sm text-theme-text-secondary">
            +{formatNumber(stats.recent_activity.new_subscriptions_30d)} last 30 days
          </p>
        </div>

        <div className="bg-theme-bg-primary rounded-lg p-6 border border-theme-border">
          <p className="text-sm font-medium text-theme-text-secondary">Total Revenue</p>
          <p className="mt-2 text-3xl font-bold text-theme-text-primary">
            {formatCurrency(stats.overview.total_revenue)}
          </p>
          <p className="mt-1 text-sm text-green-600">
            +{formatCurrency(stats.recent_activity.revenue_30d)} last 30 days
          </p>
        </div>

        <div className="bg-theme-bg-primary rounded-lg p-6 border border-theme-border">
          <p className="text-sm font-medium text-theme-text-secondary">Total Invoices</p>
          <p className="mt-2 text-3xl font-bold text-theme-text-primary">
            {formatNumber(stats.overview.total_invoices)}
          </p>
          <p className="mt-1 text-sm text-theme-text-secondary">
            +{formatNumber(stats.recent_activity.invoices_30d)} last 30 days
          </p>
        </div>
      </div>

      {/* Usage Limits */}
      <div className="bg-theme-bg-primary rounded-lg p-6 border border-theme-border">
        <h3 className="text-lg font-semibold text-theme-text-primary mb-4">Usage Limits</h3>
        <div className="space-y-4">
          {/* Customers Limit */}
          <div>
            <div className="flex justify-between text-sm mb-1">
              <span className="text-theme-text-secondary">Customers</span>
              <span className="text-theme-text-primary">
                {formatNumber(stats.limits.customers_used)} / {stats.limits.max_customers ?? 'Unlimited'}
              </span>
            </div>
            {stats.limits.max_customers && (
              <div className="w-full bg-theme-bg-secondary rounded-full h-2">
                <div
                  className={`h-2 rounded-full ${getUsageColor(getUsagePercentage(stats.limits.customers_used, stats.limits.max_customers))}`}
                  style={{ width: `${getUsagePercentage(stats.limits.customers_used, stats.limits.max_customers)}%` }}
                />
              </div>
            )}
          </div>

          {/* Subscriptions Limit */}
          <div>
            <div className="flex justify-between text-sm mb-1">
              <span className="text-theme-text-secondary">Subscriptions</span>
              <span className="text-theme-text-primary">
                {formatNumber(stats.limits.subscriptions_used)} / {stats.limits.max_subscriptions ?? 'Unlimited'}
              </span>
            </div>
            {stats.limits.max_subscriptions && (
              <div className="w-full bg-theme-bg-secondary rounded-full h-2">
                <div
                  className={`h-2 rounded-full ${getUsageColor(getUsagePercentage(stats.limits.subscriptions_used, stats.limits.max_subscriptions))}`}
                  style={{ width: `${getUsagePercentage(stats.limits.subscriptions_used, stats.limits.max_subscriptions)}%` }}
                />
              </div>
            )}
          </div>

          {/* API Requests Limit */}
          <div>
            <div className="flex justify-between text-sm mb-1">
              <span className="text-theme-text-secondary">API Requests Today</span>
              <span className="text-theme-text-primary">
                {formatNumber(stats.limits.api_requests_today)} / {stats.limits.max_api_requests ?? 'Unlimited'}
              </span>
            </div>
            {stats.limits.max_api_requests && (
              <div className="w-full bg-theme-bg-secondary rounded-full h-2">
                <div
                  className={`h-2 rounded-full ${getUsageColor(getUsagePercentage(stats.limits.api_requests_today, stats.limits.max_api_requests))}`}
                  style={{ width: `${getUsagePercentage(stats.limits.api_requests_today, stats.limits.max_api_requests)}%` }}
                />
              </div>
            )}
          </div>
        </div>
      </div>

      {/* Billing Configuration Status */}
      {stats.billing_config && (
        <div className="bg-theme-bg-primary rounded-lg p-6 border border-theme-border">
          <h3 className="text-lg font-semibold text-theme-text-primary mb-4">Billing Configuration</h3>
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
            <div className="flex items-center gap-2">
              <div className={`w-3 h-3 rounded-full ${stats.billing_config.stripe_connected ? 'bg-green-500' : 'bg-gray-300'}`} />
              <span className="text-sm text-theme-text-secondary">Stripe</span>
            </div>
            <div className="flex items-center gap-2">
              <div className={`w-3 h-3 rounded-full ${stats.billing_config.paypal_connected ? 'bg-green-500' : 'bg-gray-300'}`} />
              <span className="text-sm text-theme-text-secondary">PayPal</span>
            </div>
            <div className="flex items-center gap-2">
              <div className={`w-3 h-3 rounded-full ${stats.billing_config.auto_invoice ? 'bg-green-500' : 'bg-gray-300'}`} />
              <span className="text-sm text-theme-text-secondary">Auto Invoice</span>
            </div>
            <div className="flex items-center gap-2">
              <div className={`w-3 h-3 rounded-full ${stats.billing_config.dunning_enabled ? 'bg-green-500' : 'bg-gray-300'}`} />
              <span className="text-sm text-theme-text-secondary">Dunning</span>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default TenantOverview;

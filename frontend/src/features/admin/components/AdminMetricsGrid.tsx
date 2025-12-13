import React from 'react';
import {
  Users,
  Building2,
  CreditCard,
  DollarSign,
  TrendingUp,
  TrendingDown,
  AlertTriangle,
  CheckCircle,
} from 'lucide-react';

interface AdminMetric {
  label: string;
  value: number | string;
  previousValue?: number;
  icon: React.ElementType;
  trend?: 'up' | 'down' | 'neutral';
  trendValue?: number;
  status?: 'good' | 'warning' | 'critical';
  format?: 'number' | 'currency' | 'percentage';
}

interface AdminMetricsGridProps {
  metrics: {
    total_users: number;
    total_accounts: number;
    active_accounts: number;
    total_subscriptions: number;
    active_subscriptions: number;
    trial_subscriptions: number;
    total_revenue: number;
    monthly_revenue: number;
    failed_payments: number;
    system_health: 'healthy' | 'warning' | 'error';
  };
  loading?: boolean;
  className?: string;
}

const formatCurrency = (cents: number): string => {
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
    minimumFractionDigits: 0,
    maximumFractionDigits: 0,
  }).format(cents / 100);
};

const formatNumber = (num: number): string => {
  return new Intl.NumberFormat('en-US').format(num);
};

export const AdminMetricsGrid: React.FC<AdminMetricsGridProps> = ({
  metrics,
  loading = false,
  className = '',
}) => {
  const metricsData: AdminMetric[] = [
    {
      label: 'Total Users',
      value: metrics.total_users,
      icon: Users,
      status: 'good',
      format: 'number',
    },
    {
      label: 'Active Accounts',
      value: `${metrics.active_accounts} / ${metrics.total_accounts}`,
      icon: Building2,
      status: metrics.active_accounts / metrics.total_accounts > 0.8 ? 'good' : 'warning',
    },
    {
      label: 'Active Subscriptions',
      value: metrics.active_subscriptions,
      icon: CreditCard,
      status: 'good',
      format: 'number',
    },
    {
      label: 'Trial Subscriptions',
      value: metrics.trial_subscriptions,
      icon: CreditCard,
      status: 'good',
      format: 'number',
    },
    {
      label: 'Total Revenue',
      value: metrics.total_revenue,
      icon: DollarSign,
      status: 'good',
      format: 'currency',
    },
    {
      label: 'Monthly Revenue',
      value: metrics.monthly_revenue,
      icon: TrendingUp,
      status: 'good',
      format: 'currency',
    },
    {
      label: 'Failed Payments (30d)',
      value: metrics.failed_payments,
      icon: AlertTriangle,
      status: metrics.failed_payments > 10 ? 'critical' : metrics.failed_payments > 5 ? 'warning' : 'good',
      format: 'number',
    },
    {
      label: 'System Health',
      value: metrics.system_health.charAt(0).toUpperCase() + metrics.system_health.slice(1),
      icon: metrics.system_health === 'healthy' ? CheckCircle : AlertTriangle,
      status: metrics.system_health === 'healthy' ? 'good' : metrics.system_health === 'warning' ? 'warning' : 'critical',
    },
  ];

  const getStatusStyles = (status?: 'good' | 'warning' | 'critical') => {
    switch (status) {
      case 'critical':
        return {
          bg: 'bg-theme-error-background',
          border: 'border-theme-error',
          text: 'text-theme-error',
          iconBg: 'bg-theme-error bg-opacity-20',
        };
      case 'warning':
        return {
          bg: 'bg-theme-warning-background',
          border: 'border-theme-warning',
          text: 'text-theme-warning',
          iconBg: 'bg-theme-warning bg-opacity-20',
        };
      default:
        return {
          bg: 'bg-theme-surface',
          border: 'border-theme',
          text: 'text-theme-primary',
          iconBg: 'bg-theme-interactive-primary bg-opacity-10',
        };
    }
  };

  const formatValue = (metric: AdminMetric): string => {
    if (typeof metric.value === 'string') return metric.value;
    switch (metric.format) {
      case 'currency':
        return formatCurrency(metric.value);
      case 'percentage':
        return `${metric.value}%`;
      default:
        return formatNumber(metric.value);
    }
  };

  if (loading) {
    return (
      <div className={`grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 ${className}`}>
        {[1, 2, 3, 4, 5, 6, 7, 8].map((i) => (
          <div key={i} className="bg-theme-surface rounded-lg border border-theme p-4 animate-pulse">
            <div className="flex items-center gap-4">
              <div className="w-12 h-12 bg-theme-background rounded-lg" />
              <div className="flex-1">
                <div className="h-4 bg-theme-background rounded w-24 mb-2" />
                <div className="h-6 bg-theme-background rounded w-16" />
              </div>
            </div>
          </div>
        ))}
      </div>
    );
  }

  return (
    <div className={`grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 ${className}`}>
      {metricsData.map((metric, index) => {
        const styles = getStatusStyles(metric.status);
        const Icon = metric.icon;

        return (
          <div
            key={index}
            className={`rounded-lg border-2 p-4 transition-all hover:shadow-md ${styles.bg} ${styles.border}`}
          >
            <div className="flex items-center gap-4">
              <div className={`p-3 rounded-lg ${styles.iconBg}`}>
                <Icon className={`w-6 h-6 ${styles.text}`} />
              </div>
              <div className="flex-1 min-w-0">
                <p className="text-sm font-medium text-theme-secondary truncate">
                  {metric.label}
                </p>
                <p className={`text-2xl font-bold ${styles.text}`}>
                  {formatValue(metric)}
                </p>
              </div>
              {metric.trend && (
                <div
                  className={`flex items-center gap-1 px-2 py-1 rounded-full text-xs font-medium ${
                    metric.trend === 'up'
                      ? 'bg-theme-success bg-opacity-10 text-theme-success'
                      : metric.trend === 'down'
                      ? 'bg-theme-error bg-opacity-10 text-theme-error'
                      : 'bg-theme-secondary bg-opacity-10 text-theme-secondary'
                  }`}
                >
                  {metric.trend === 'up' ? (
                    <TrendingUp className="w-3 h-3" />
                  ) : metric.trend === 'down' ? (
                    <TrendingDown className="w-3 h-3" />
                  ) : null}
                  {metric.trendValue !== undefined && (
                    <span>{Math.abs(metric.trendValue)}%</span>
                  )}
                </div>
              )}
            </div>
          </div>
        );
      })}
    </div>
  );
};

export default AdminMetricsGrid;

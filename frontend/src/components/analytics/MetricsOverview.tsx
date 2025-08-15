import React from 'react';
import { AnalyticsData } from '../../pages/analytics/AnalyticsPage';

interface MetricsOverviewProps {
  data: AnalyticsData;
}

export const MetricsOverview: React.FC<MetricsOverviewProps> = ({ data }) => {
  const formatCurrency = (amount: number) => {
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: 'USD',
      minimumFractionDigits: 0,
      maximumFractionDigits: 0
    }).format(amount);
  };

  const formatPercentage = (percentage: number, decimals = 1) => {
    return `${percentage.toFixed(decimals)}%`;
  };

  const getGrowthColor = (growth: number) => {
    if (growth > 0) return 'text-theme-success';
    if (growth < 0) return 'text-theme-error';
    return 'text-theme-secondary';
  };

  const getGrowthIcon = (growth: number) => {
    if (growth > 0) return '↗️';
    if (growth < 0) return '↘️';
    return '→';
  };

  const getRiskColor = (level: string) => {
    switch (level) {
      case 'low': return 'text-theme-success bg-theme-success bg-opacity-10';
      case 'medium': return 'text-theme-warning bg-theme-warning bg-opacity-10';
      case 'high': return 'text-theme-error bg-theme-error bg-opacity-10';
      default: return 'text-theme-secondary bg-theme-surface';
    }
  };

  const metrics = [
    {
      title: 'Monthly Recurring Revenue',
      value: data.revenue?.current_metrics ? formatCurrency(data.revenue.current_metrics.mrr) : '$0',
      change: data.revenue?.current_metrics?.growth_rate || 0,
      icon: '💰',
      description: 'MRR from active subscriptions'
    },
    {
      title: 'Annual Recurring Revenue',
      value: data.revenue?.current_metrics ? formatCurrency(data.revenue.current_metrics.arr) : '$0',
      change: data.revenue?.current_metrics ? data.revenue.current_metrics.growth_rate * 12 : 0,
      icon: '📈',
      description: 'Projected annual revenue'
    },
    {
      title: 'Active Customers',
      value: data.customers?.current_metrics?.total_customers?.toLocaleString() || '0',
      change: null,
      icon: '👥',
      description: 'Total active customers'
    },
    {
      title: 'Average Revenue Per User',
      value: data.customers?.current_metrics ? formatCurrency(data.customers.current_metrics.arpu) : '$0',
      change: null,
      icon: '💵',
      description: 'Monthly ARPU'
    },
    {
      title: 'Customer Lifetime Value',
      value: data.customers?.current_metrics ? formatCurrency(data.customers.current_metrics.ltv) : '$0',
      change: null,
      icon: '⭐',
      description: 'Average customer LTV'
    },
    {
      title: 'Customer Churn Rate',
      value: data.churn?.current_metrics ? formatPercentage(data.churn.current_metrics.customer_churn_rate) : '0%',
      change: null,
      icon: '📉',
      description: 'Monthly customer churn',
      risk: data.churn?.insights?.churn_risk_level || 'low'
    },
    {
      title: 'Revenue Retention',
      value: data.churn?.current_metrics ? formatPercentage(data.churn.current_metrics.customer_retention_rate) : '0%',
      change: null,
      icon: '🔒',
      description: 'Customer retention rate'
    },
    {
      title: 'Growth Rate',
      value: data.growth ? formatPercentage(data.growth.compound_monthly_growth_rate) : '0%',
      change: null,
      icon: '🚀',
      description: 'Compound monthly growth'
    }
  ];

  return (
    <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
      {metrics.map((metric, index) => (
        <div key={index} className="card-theme rounded-lg shadow-sm border-theme p-6">
          <div className="flex items-center justify-between">
            <div className="flex items-center">
              <span className="text-2xl mr-3">{metric.icon}</span>
              <div className="flex-1">
                <p className="text-sm font-medium text-theme-secondary">{metric.title}</p>
                <p className="text-2xl font-bold text-theme-primary mt-1">{metric.value}</p>
              </div>
            </div>
            {metric.risk && (
              <div className={`px-2 py-1 rounded-full text-xs font-medium ${getRiskColor(metric.risk)}`}>
                {metric.risk.toUpperCase()}
              </div>
            )}
          </div>
          
          <div className="mt-4">
            {metric.change !== null && (
              <div className="flex items-center">
                <span className="text-lg mr-1">{getGrowthIcon(metric.change)}</span>
                <span className={`text-sm font-medium ${getGrowthColor(metric.change)}`}>
                  {formatPercentage(Math.abs(metric.change))} vs last period
                </span>
              </div>
            )}
            <p className="text-xs text-theme-tertiary mt-1">{metric.description}</p>
          </div>
        </div>
      ))}
    </div>
  );
};
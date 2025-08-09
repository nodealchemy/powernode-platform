import React from 'react';
import { AnalyticsData } from '../../pages/dashboard/AnalyticsPage';

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
    if (growth > 0) return 'text-green-600';
    if (growth < 0) return 'text-red-600';
    return 'text-gray-600';
  };

  const getGrowthIcon = (growth: number) => {
    if (growth > 0) return '↗️';
    if (growth < 0) return '↘️';
    return '→';
  };

  const getRiskColor = (level: string) => {
    switch (level) {
      case 'low': return 'text-green-600 bg-green-50';
      case 'medium': return 'text-yellow-600 bg-yellow-50';
      case 'high': return 'text-red-600 bg-red-50';
      default: return 'text-gray-600 bg-gray-50';
    }
  };

  const metrics = [
    {
      title: 'Monthly Recurring Revenue',
      value: formatCurrency(data.revenue.current_metrics.mrr),
      change: data.revenue.current_metrics.growth_rate,
      icon: '💰',
      description: 'MRR from active subscriptions'
    },
    {
      title: 'Annual Recurring Revenue',
      value: formatCurrency(data.revenue.current_metrics.arr),
      change: data.revenue.current_metrics.growth_rate * 12,
      icon: '📈',
      description: 'Projected annual revenue'
    },
    {
      title: 'Active Customers',
      value: data.customers.current_metrics.total_customers.toLocaleString(),
      change: null,
      icon: '👥',
      description: 'Total active customers'
    },
    {
      title: 'Average Revenue Per User',
      value: formatCurrency(data.customers.current_metrics.arpu),
      change: null,
      icon: '💵',
      description: 'Monthly ARPU'
    },
    {
      title: 'Customer Lifetime Value',
      value: formatCurrency(data.customers.current_metrics.ltv),
      change: null,
      icon: '⭐',
      description: 'Average customer LTV'
    },
    {
      title: 'Customer Churn Rate',
      value: formatPercentage(data.churn.current_metrics.customer_churn_rate),
      change: null,
      icon: '📉',
      description: 'Monthly customer churn',
      risk: data.churn.insights.churn_risk_level
    },
    {
      title: 'Revenue Retention',
      value: formatPercentage(data.churn.current_metrics.customer_retention_rate),
      change: null,
      icon: '🔒',
      description: 'Customer retention rate'
    },
    {
      title: 'Growth Rate',
      value: formatPercentage(data.growth.compound_monthly_growth_rate),
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
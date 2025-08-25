import React from 'react';
import { AnalyticsData } from '@/pages/app/business/AnalyticsPage';
import { MetricCard } from '@/shared/components/ui/Card';

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
        <MetricCard
          key={index}
          title={metric.title}
          value={metric.value}
          icon={metric.icon}
          change={metric.change}
          description={metric.description}
          className={metric.risk ? `border-l-4 ${
            metric.risk === 'high' ? 'border-l-theme-error' :
            metric.risk === 'medium' ? 'border-l-theme-warning' :
            'border-l-theme-success'
          }` : ''}
        />
      ))}
    </div>
  );
};
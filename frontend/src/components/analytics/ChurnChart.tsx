import React from 'react';
import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  Legend,
  ResponsiveContainer,
  BarChart,
  Bar,
  ComposedChart,
  Area,
  AreaChart
} from 'recharts';
import { format, parseISO } from 'date-fns';

interface ChurnChartProps {
  data: Array<{
    date: string;
    customer_churn_rate: number;
    revenue_churn_rate: number;
    churned_customers: number;
    churned_subscriptions: number;
  }>;
  currentMetrics?: {
    customer_churn_rate: number;
    average_customer_churn_rate: number;
    average_revenue_churn_rate: number;
    customer_retention_rate: number;
  };
  insights?: {
    churn_risk_level: 'low' | 'medium' | 'high';
    recommended_actions: string[];
  };
  title: string;
  compact?: boolean;
}

export const ChurnChart: React.FC<ChurnChartProps> = ({ 
  data, 
  currentMetrics,
  insights,
  title, 
  compact = false 
}) => {
  const formatPercentage = (value: number) => {
    return `${value.toFixed(1)}%`;
  };

  const formatDate = (dateString: string) => {
    try {
      return format(parseISO(dateString), 'MMM yyyy');
    } catch {
      return dateString;
    }
  };

  const getChurnColor = (churnRate: number) => {
    if (churnRate < 2) return '#10b981'; // Green for low churn
    if (churnRate < 5) return '#f59e0b'; // Yellow for moderate churn
    return '#ef4444'; // Red for high churn
  };

  const getRiskColor = (level: string) => {
    switch (level) {
      case 'low': return 'text-green-600 bg-green-50 border-green-200';
      case 'medium': return 'text-yellow-600 bg-yellow-50 border-yellow-200';
      case 'high': return 'text-red-600 bg-red-50 border-red-200';
      default: return 'text-gray-600 bg-gray-50 border-gray-200';
    }
  };

  const CustomTooltip = ({ active, payload, label }: any) => {
    if (active && payload && payload.length) {
      return (
        <div className="bg-white p-4 border border-gray-200 rounded-lg shadow-lg">
          <p className="font-semibold text-gray-900">{formatDate(label)}</p>
          {payload.map((entry: any, index: number) => (
            <p key={index} className="text-sm" style={{ color: entry.color }}>
              {entry.name}: {
                entry.name.includes('Rate') || entry.name.includes('%') 
                  ? formatPercentage(entry.value)
                  : entry.value.toLocaleString()
              }
            </p>
          ))}
        </div>
      );
    }
    return null;
  };

  if (compact) {
    return (
      <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
        <h3 className="text-lg font-semibold text-gray-900 mb-4">{title}</h3>
        <div className="h-64">
          <ResponsiveContainer width="100%" height="100%">
            <AreaChart data={data}>
              <defs>
                <linearGradient id="churnGradient" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor="#ef4444" stopOpacity={0.8}/>
                  <stop offset="95%" stopColor="#ef4444" stopOpacity={0.1}/>
                </linearGradient>
              </defs>
              <CartesianGrid strokeDasharray="3 3" stroke="#f0f0f0" />
              <XAxis 
                dataKey="date" 
                tickFormatter={formatDate}
                tick={{ fontSize: 12 }}
              />
              <YAxis 
                tickFormatter={formatPercentage}
                tick={{ fontSize: 12 }}
              />
              <Tooltip content={<CustomTooltip />} />
              <Area
                type="monotone"
                dataKey="customer_churn_rate"
                stroke="#ef4444"
                strokeWidth={2}
                fill="url(#churnGradient)"
              />
            </AreaChart>
          </ResponsiveContainer>
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Churn Metrics Summary */}
      {currentMetrics && (
        <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
          <h3 className="text-lg font-semibold text-gray-900 mb-4">Churn Metrics</h3>
          <div className="grid grid-cols-1 md:grid-cols-4 gap-6">
            <div>
              <p className="text-sm text-gray-500">Current Customer Churn</p>
              <p className="text-2xl font-bold text-red-600">
                {formatPercentage(currentMetrics.customer_churn_rate)}
              </p>
            </div>
            <div>
              <p className="text-sm text-gray-500">Average Customer Churn</p>
              <p className="text-2xl font-bold text-orange-600">
                {formatPercentage(currentMetrics.average_customer_churn_rate)}
              </p>
            </div>
            <div>
              <p className="text-sm text-gray-500">Revenue Churn Rate</p>
              <p className="text-2xl font-bold text-red-700">
                {formatPercentage(currentMetrics.average_revenue_churn_rate)}
              </p>
            </div>
            <div>
              <p className="text-sm text-gray-500">Customer Retention</p>
              <p className="text-2xl font-bold text-green-600">
                {formatPercentage(currentMetrics.customer_retention_rate)}
              </p>
            </div>
          </div>
        </div>
      )}

      {/* Risk Assessment */}
      {insights && (
        <div className={`rounded-lg border p-6 ${getRiskColor(insights.churn_risk_level)}`}>
          <div className="flex items-center justify-between mb-4">
            <h3 className="text-lg font-semibold">Churn Risk Assessment</h3>
            <span className={`px-3 py-1 rounded-full text-sm font-medium ${getRiskColor(insights.churn_risk_level)}`}>
              {insights.churn_risk_level.toUpperCase()} RISK
            </span>
          </div>
          <div>
            <h4 className="font-medium mb-2">Recommended Actions:</h4>
            <ul className="space-y-1">
              {insights.recommended_actions.map((action, index) => (
                <li key={index} className="text-sm flex items-start">
                  <span className="text-lg mr-2">•</span>
                  {action}
                </li>
              ))}
            </ul>
          </div>
        </div>
      )}

      {/* Churn Rate Trends */}
      <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
        <h3 className="text-lg font-semibold text-gray-900 mb-4">Churn Rate Trends</h3>
        <div className="h-96">
          <ResponsiveContainer width="100%" height="100%">
            <ComposedChart data={data}>
              <defs>
                <linearGradient id="customerChurnGradient" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor="#ef4444" stopOpacity={0.8}/>
                  <stop offset="95%" stopColor="#ef4444" stopOpacity={0.1}/>
                </linearGradient>
                <linearGradient id="revenueChurnGradient" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor="#f59e0b" stopOpacity={0.8}/>
                  <stop offset="95%" stopColor="#f59e0b" stopOpacity={0.1}/>
                </linearGradient>
              </defs>
              <CartesianGrid strokeDasharray="3 3" stroke="#f0f0f0" />
              <XAxis 
                dataKey="date" 
                tickFormatter={formatDate}
              />
              <YAxis 
                tickFormatter={formatPercentage}
              />
              <Tooltip content={<CustomTooltip />} />
              <Legend />
              <Area
                type="monotone"
                dataKey="customer_churn_rate"
                stackId="1"
                stroke="#ef4444"
                fill="url(#customerChurnGradient)"
                name="Customer Churn Rate"
              />
              <Area
                type="monotone"
                dataKey="revenue_churn_rate"
                stackId="2"
                stroke="#f59e0b"
                fill="url(#revenueChurnGradient)"
                name="Revenue Churn Rate"
              />
            </ComposedChart>
          </ResponsiveContainer>
        </div>
      </div>

      {/* Churned Volumes */}
      <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
        <h3 className="text-lg font-semibold text-gray-900 mb-4">Churned Volume Analysis</h3>
        <div className="h-96">
          <ResponsiveContainer width="100%" height="100%">
            <ComposedChart data={data}>
              <CartesianGrid strokeDasharray="3 3" stroke="#f0f0f0" />
              <XAxis 
                dataKey="date" 
                tickFormatter={formatDate}
              />
              <YAxis yAxisId="left" />
              <YAxis yAxisId="right" orientation="right" tickFormatter={formatPercentage} />
              <Tooltip content={<CustomTooltip />} />
              <Legend />
              <Bar
                yAxisId="left"
                dataKey="churned_customers"
                fill="#ef4444"
                name="Churned Customers"
                opacity={0.8}
              />
              <Bar
                yAxisId="left"
                dataKey="churned_subscriptions"
                fill="#dc2626"
                name="Churned Subscriptions"
                opacity={0.8}
              />
              <Line
                yAxisId="right"
                type="monotone"
                dataKey="customer_churn_rate"
                stroke="#7c3aed"
                strokeWidth={3}
                name="Churn Rate %"
                dot={{ fill: '#7c3aed', strokeWidth: 0, r: 4 }}
              />
            </ComposedChart>
          </ResponsiveContainer>
        </div>
      </div>

      {/* Churn Rate Distribution */}
      <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
        <h3 className="text-lg font-semibold text-gray-900 mb-4">Churn Rate Distribution</h3>
        <div className="grid grid-cols-6 md:grid-cols-12 gap-2">
          {data.map((item, index) => {
            const color = getChurnColor(item.customer_churn_rate);
            return (
              <div key={index} className="text-center">
                <div
                  className="w-full h-16 rounded-md flex items-center justify-center text-white font-semibold text-xs"
                  style={{ backgroundColor: color }}
                  title={`${formatDate(item.date)}: ${formatPercentage(item.customer_churn_rate)}`}
                >
                  {formatPercentage(item.customer_churn_rate)}
                </div>
                <p className="text-xs text-gray-500 mt-1 truncate">
                  {formatDate(item.date)}
                </p>
              </div>
            );
          })}
        </div>
        
        {/* Legend */}
        <div className="flex items-center justify-center space-x-6 mt-4 text-xs">
          <div className="flex items-center space-x-2">
            <div className="w-3 h-3 rounded bg-green-500"></div>
            <span>Low Churn (&lt;2%)</span>
          </div>
          <div className="flex items-center space-x-2">
            <div className="w-3 h-3 rounded bg-yellow-500"></div>
            <span>Moderate Churn (2-5%)</span>
          </div>
          <div className="flex items-center space-x-2">
            <div className="w-3 h-3 rounded bg-red-500"></div>
            <span>High Churn (&gt;5%)</span>
          </div>
        </div>
      </div>
    </div>
  );
};
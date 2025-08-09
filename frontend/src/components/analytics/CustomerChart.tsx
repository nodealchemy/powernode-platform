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
  PieChart,
  Pie,
  Cell
} from 'recharts';
import { format, parseISO } from 'date-fns';

interface CustomerChartProps {
  data: Array<{
    date: string;
    total_customers: number;
    new_customers: number;
    churned_customers: number;
    net_growth: number;
    arpu: number;
    ltv: number;
  }>;
  currentMetrics?: {
    total_customers: number;
    arpu: number;
    ltv: number;
    ltv_to_cac_ratio: number;
  };
  segmentation?: {
    by_plan: Array<{
      plan: string;
      customers: number;
    }>;
    by_tenure: Array<{
      segment: string;
      customers: number;
    }>;
  };
  title: string;
  compact?: boolean;
}

export const CustomerChart: React.FC<CustomerChartProps> = ({ 
  data, 
  currentMetrics,
  segmentation,
  title, 
  compact = false 
}) => {
  const formatCurrency = (value: number) => {
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: 'USD',
      minimumFractionDigits: 0,
      maximumFractionDigits: 0
    }).format(value);
  };

  const formatDate = (dateString: string) => {
    try {
      return format(parseISO(dateString), 'MMM yyyy');
    } catch {
      return dateString;
    }
  };

  // Colors for pie charts
  const COLORS = [
    '#3b82f6', '#10b981', '#f59e0b', '#ef4444', '#8b5cf6', 
    '#06b6d4', '#84cc16', '#f97316', '#ec4899', '#6b7280'
  ];

  const CustomTooltip = ({ active, payload, label }: any) => {
    if (active && payload && payload.length) {
      return (
        <div className="bg-white p-4 border border-gray-200 rounded-lg shadow-lg">
          <p className="font-semibold text-gray-900">{label ? formatDate(label) : ''}</p>
          {payload.map((entry: any, index: number) => (
            <p key={index} className="text-sm" style={{ color: entry.color }}>
              {entry.name}: {
                entry.name.includes('ARPU') || entry.name.includes('LTV') || entry.name.includes('$')
                  ? formatCurrency(entry.value)
                  : entry.value.toLocaleString()
              }
            </p>
          ))}
        </div>
      );
    }
    return null;
  };

  const PieTooltip = ({ active, payload }: any) => {
    if (active && payload && payload.length) {
      const data = payload[0];
      return (
        <div className="bg-white p-3 border border-gray-200 rounded-lg shadow-lg">
          <p className="font-semibold text-gray-900">{data.name}</p>
          <p className="text-sm text-gray-600">
            {data.value.toLocaleString()} customers ({((data.value / data.payload.total) * 100).toFixed(1)}%)
          </p>
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
            <LineChart data={data}>
              <CartesianGrid strokeDasharray="3 3" stroke="#f0f0f0" />
              <XAxis 
                dataKey="date" 
                tickFormatter={formatDate}
                tick={{ fontSize: 12 }}
              />
              <YAxis tick={{ fontSize: 12 }} />
              <Tooltip content={<CustomTooltip />} />
              <Line
                type="monotone"
                dataKey="total_customers"
                stroke="#3b82f6"
                strokeWidth={2}
                dot={{ fill: '#3b82f6', strokeWidth: 0, r: 4 }}
                activeDot={{ r: 6, stroke: '#3b82f6', strokeWidth: 2 }}
              />
            </LineChart>
          </ResponsiveContainer>
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Customer Metrics Summary */}
      {currentMetrics && (
        <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
          <h3 className="text-lg font-semibold text-gray-900 mb-4">Customer Metrics</h3>
          <div className="grid grid-cols-1 md:grid-cols-4 gap-6">
            <div>
              <p className="text-sm text-gray-500">Total Customers</p>
              <p className="text-2xl font-bold text-blue-600">
                {currentMetrics.total_customers.toLocaleString()}
              </p>
            </div>
            <div>
              <p className="text-sm text-gray-500">Average Revenue Per User</p>
              <p className="text-2xl font-bold text-green-600">
                {formatCurrency(currentMetrics.arpu)}
              </p>
            </div>
            <div>
              <p className="text-sm text-gray-500">Customer Lifetime Value</p>
              <p className="text-2xl font-bold text-purple-600">
                {formatCurrency(currentMetrics.ltv)}
              </p>
            </div>
            <div>
              <p className="text-sm text-gray-500">LTV:CAC Ratio</p>
              <p className="text-2xl font-bold text-orange-600">
                {currentMetrics.ltv_to_cac_ratio.toFixed(1)}:1
              </p>
            </div>
          </div>
        </div>
      )}

      {/* Customer Growth Trend */}
      <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
        <h3 className="text-lg font-semibold text-gray-900 mb-4">Customer Growth Trend</h3>
        <div className="h-96">
          <ResponsiveContainer width="100%" height="100%">
            <ComposedChart data={data}>
              <CartesianGrid strokeDasharray="3 3" stroke="#f0f0f0" />
              <XAxis 
                dataKey="date" 
                tickFormatter={formatDate}
              />
              <YAxis yAxisId="left" />
              <YAxis yAxisId="right" orientation="right" />
              <Tooltip content={<CustomTooltip />} />
              <Legend />
              <Bar
                yAxisId="left"
                dataKey="new_customers"
                fill="#10b981"
                name="New Customers"
                opacity={0.8}
              />
              <Bar
                yAxisId="left"
                dataKey="churned_customers"
                fill="#ef4444"
                name="Churned Customers"
                opacity={0.8}
              />
              <Line
                yAxisId="right"
                type="monotone"
                dataKey="total_customers"
                stroke="#3b82f6"
                strokeWidth={3}
                name="Total Customers"
                dot={{ fill: '#3b82f6', strokeWidth: 0, r: 4 }}
              />
              <Line
                yAxisId="left"
                type="monotone"
                dataKey="net_growth"
                stroke="#7c3aed"
                strokeWidth={2}
                name="Net Growth"
                dot={{ fill: '#7c3aed', strokeWidth: 0, r: 3 }}
              />
            </ComposedChart>
          </ResponsiveContainer>
        </div>
      </div>

      {/* ARPU and LTV Trends */}
      <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
        <h3 className="text-lg font-semibold text-gray-900 mb-4">ARPU and LTV Trends</h3>
        <div className="h-96">
          <ResponsiveContainer width="100%" height="100%">
            <ComposedChart data={data}>
              <CartesianGrid strokeDasharray="3 3" stroke="#f0f0f0" />
              <XAxis 
                dataKey="date" 
                tickFormatter={formatDate}
              />
              <YAxis yAxisId="arpu" tickFormatter={(value) => formatCurrency(value)} />
              <YAxis yAxisId="ltv" orientation="right" tickFormatter={(value) => formatCurrency(value)} />
              <Tooltip content={<CustomTooltip />} />
              <Legend />
              <Line
                yAxisId="arpu"
                type="monotone"
                dataKey="arpu"
                stroke="#10b981"
                strokeWidth={3}
                name="ARPU"
                dot={{ fill: '#10b981', strokeWidth: 0, r: 4 }}
              />
              <Line
                yAxisId="ltv"
                type="monotone"
                dataKey="ltv"
                stroke="#8b5cf6"
                strokeWidth={3}
                name="LTV"
                dot={{ fill: '#8b5cf6', strokeWidth: 0, r: 4 }}
              />
            </ComposedChart>
          </ResponsiveContainer>
        </div>
      </div>

      {/* Customer Segmentation */}
      {segmentation && (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          {/* By Plan */}
          <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
            <h3 className="text-lg font-semibold text-gray-900 mb-4">Customers by Plan</h3>
            <div className="h-80">
              <ResponsiveContainer width="100%" height="100%">
                <PieChart>
                  <Pie
                    data={segmentation.by_plan.map(item => ({
                      name: item.plan,
                      value: item.customers,
                      total: segmentation.by_plan.reduce((sum, p) => sum + p.customers, 0)
                    }))}
                    cx="50%"
                    cy="50%"
                    labelLine={false}
                    label={({ name, percent }) => `${name} (${percent ? (percent * 100).toFixed(0) : 0}%)`}
                    outerRadius={80}
                    fill="#8884d8"
                    dataKey="value"
                  >
                    {segmentation.by_plan.map((entry, index) => (
                      <Cell key={`cell-${index}`} fill={COLORS[index % COLORS.length]} />
                    ))}
                  </Pie>
                  <Tooltip content={<PieTooltip />} />
                </PieChart>
              </ResponsiveContainer>
            </div>
            <div className="mt-4 space-y-2">
              {segmentation.by_plan.map((item, index) => (
                <div key={index} className="flex items-center justify-between text-sm">
                  <div className="flex items-center">
                    <div 
                      className="w-3 h-3 rounded-full mr-2"
                      style={{ backgroundColor: COLORS[index % COLORS.length] }}
                    ></div>
                    <span>{item.plan}</span>
                  </div>
                  <span className="font-medium">{item.customers.toLocaleString()}</span>
                </div>
              ))}
            </div>
          </div>

          {/* By Tenure */}
          <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
            <h3 className="text-lg font-semibold text-gray-900 mb-4">Customers by Tenure</h3>
            <div className="h-80">
              <ResponsiveContainer width="100%" height="100%">
                <BarChart data={segmentation.by_tenure}>
                  <CartesianGrid strokeDasharray="3 3" stroke="#f0f0f0" />
                  <XAxis dataKey="segment" />
                  <YAxis />
                  <Tooltip 
                    formatter={(value: any) => [value.toLocaleString(), 'Customers']}
                    labelStyle={{ color: '#374151' }}
                  />
                  <Bar dataKey="customers" fill="#3b82f6" opacity={0.8} />
                </BarChart>
              </ResponsiveContainer>
            </div>
            <div className="mt-4 space-y-2">
              {segmentation.by_tenure.map((item, index) => (
                <div key={index} className="flex items-center justify-between text-sm">
                  <span>{item.segment}</span>
                  <span className="font-medium">{item.customers.toLocaleString()} customers</span>
                </div>
              ))}
            </div>
          </div>
        </div>
      )}

      {/* Net Growth Analysis */}
      <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
        <h3 className="text-lg font-semibold text-gray-900 mb-4">Net Customer Growth Analysis</h3>
        <div className="h-64">
          <ResponsiveContainer width="100%" height="100%">
            <BarChart data={data}>
              <CartesianGrid strokeDasharray="3 3" stroke="#f0f0f0" />
              <XAxis 
                dataKey="date" 
                tickFormatter={formatDate}
              />
              <YAxis />
              <Tooltip content={<CustomTooltip />} />
              <Bar
                dataKey="net_growth"
                fill="#3b82f6"
                name="Net Customer Growth"
              />
            </BarChart>
          </ResponsiveContainer>
        </div>
        
        {/* Growth Summary */}
        <div className="mt-4 grid grid-cols-1 md:grid-cols-3 gap-4 text-sm">
          <div className="text-center p-3 bg-green-50 rounded-lg">
            <p className="text-green-600 font-medium">Total New Customers</p>
            <p className="text-xl font-bold text-green-700">
              {data.reduce((sum, item) => sum + item.new_customers, 0).toLocaleString()}
            </p>
          </div>
          <div className="text-center p-3 bg-red-50 rounded-lg">
            <p className="text-red-600 font-medium">Total Churned Customers</p>
            <p className="text-xl font-bold text-red-700">
              {data.reduce((sum, item) => sum + item.churned_customers, 0).toLocaleString()}
            </p>
          </div>
          <div className="text-center p-3 bg-blue-50 rounded-lg">
            <p className="text-blue-600 font-medium">Net Growth</p>
            <p className="text-xl font-bold text-blue-700">
              {data.reduce((sum, item) => sum + item.net_growth, 0).toLocaleString()}
            </p>
          </div>
        </div>
      </div>
    </div>
  );
};
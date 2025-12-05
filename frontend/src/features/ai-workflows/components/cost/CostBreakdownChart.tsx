import React, { useMemo } from 'react';
import { PieChart, Pie, Cell, ResponsiveContainer, Legend, Tooltip, BarChart, Bar, XAxis, YAxis, CartesianGrid } from 'recharts';
import { Card } from '@/shared/components/ui/Card';
import { Select } from '@/shared/components/ui/Select';
import type { CostMetrics } from './CostOptimizationDashboard';

interface CostBreakdownChartProps {
  metrics: CostMetrics;
  chartType?: 'pie' | 'bar';
  breakdownBy?: 'provider' | 'model' | 'workflow';
  onChartTypeChange?: (type: 'pie' | 'bar') => void;
  onBreakdownChange?: (breakdown: 'provider' | 'model' | 'workflow') => void;
}

const COLORS = [
  '#3b82f6', // blue
  '#10b981', // green
  '#f59e0b', // amber
  '#ef4444', // red
  '#8b5cf6', // purple
  '#ec4899', // pink
  '#06b6d4', // cyan
  '#f97316'  // orange
];

export const CostBreakdownChart: React.FC<CostBreakdownChartProps> = ({
  metrics,
  chartType: initialChartType = 'pie',
  breakdownBy: initialBreakdown = 'provider',
  onChartTypeChange,
  onBreakdownChange
}) => {
  const [chartType, setChartType] = React.useState<'pie' | 'bar'>(initialChartType);
  const [breakdownBy, setBreakdownBy] = React.useState<'provider' | 'model' | 'workflow'>(initialBreakdown);

  const handleChartTypeChange = (type: 'pie' | 'bar') => {
    setChartType(type);
    onChartTypeChange?.(type);
  };

  const handleBreakdownChange = (breakdown: 'provider' | 'model' | 'workflow') => {
    setBreakdownBy(breakdown);
    onBreakdownChange?.(breakdown);
  };

  const chartData = useMemo(() => {
    let sourceData: Record<string, number> = {};

    switch (breakdownBy) {
      case 'provider':
        sourceData = metrics.cost_by_provider;
        break;
      case 'model':
        sourceData = metrics.cost_by_model;
        break;
      case 'workflow':
        sourceData = Object.entries(metrics.cost_by_workflow).reduce((acc, [key, value]) => {
          acc[key] = value.cost;
          return acc;
        }, {} as Record<string, number>);
        break;
    }

    return Object.entries(sourceData)
      .map(([name, value]) => ({
        name: name.charAt(0).toUpperCase() + name.slice(1),
        value: typeof value === 'number' ? value : 0,
        percentage: ((typeof value === 'number' ? value : 0) / metrics.total_cost * 100).toFixed(1)
      }))
      .sort((a, b) => b.value - a.value);
  }, [metrics, breakdownBy]);

  interface TooltipProps {
    active?: boolean;
    payload?: Array<{
      name: string;
      value: number;
      payload: {
        percentage: string;
      };
    }>;
  }

  const CustomTooltip = ({ active, payload }: TooltipProps) => {
    if (active && payload && payload.length) {
      return (
        <div className="bg-theme-surface border border-theme p-3 rounded-lg shadow-lg">
          <p className="font-medium text-theme-primary">{payload[0].name}</p>
          <p className="text-theme-secondary">
            Cost: <span className="font-semibold text-theme-primary">${payload[0].value.toFixed(2)}</span>
          </p>
          <p className="text-theme-tertiary text-sm">
            {payload[0].payload.percentage}% of total
          </p>
        </div>
      );
    }
    return null;
  };

  interface LabelProps {
    cx: number;
    cy: number;
    midAngle: number;
    innerRadius: number;
    outerRadius: number;
    percent: number;
  }

  const CustomLabel = ({ cx, cy, midAngle, innerRadius, outerRadius, percent }: LabelProps) => {
    const RADIAN = Math.PI / 180;
    const radius = innerRadius + (outerRadius - innerRadius) * 0.5;
    const x = cx + radius * Math.cos(-midAngle * RADIAN);
    const y = cy + radius * Math.sin(-midAngle * RADIAN);

    if (percent < 0.05) return null; // Don't show label for slices < 5%

    return (
      <text
        x={x}
        y={y}
        fill="white"
        textAnchor={x > cx ? 'start' : 'end'}
        dominantBaseline="central"
        className="text-xs font-medium"
      >
        {`${(percent * 100).toFixed(0)}%`}
      </text>
    );
  };

  return (
    <Card className="p-6">
      <div className="flex items-center justify-between mb-6">
        <h3 className="text-lg font-semibold text-theme-primary">Cost Breakdown</h3>
        <div className="flex items-center gap-2">
          <Select
            value={breakdownBy}
            onChange={(value) => handleBreakdownChange(value as any)}
            className="w-32"
          >
            <option value="provider">By Provider</option>
            <option value="model">By Model</option>
            <option value="workflow">By Workflow</option>
          </Select>
          <Select
            value={chartType}
            onChange={(value) => handleChartTypeChange(value as any)}
            className="w-28"
          >
            <option value="pie">Pie Chart</option>
            <option value="bar">Bar Chart</option>
          </Select>
        </div>
      </div>

      {chartData.length === 0 ? (
        <div className="text-center py-12 text-theme-tertiary">
          <p>No cost data available for this breakdown</p>
        </div>
      ) : chartType === 'pie' ? (
        <ResponsiveContainer width="100%" height={400}>
          <PieChart>
            <Pie
              data={chartData}
              cx="50%"
              cy="50%"
              labelLine={false}
              label={CustomLabel as any}
              outerRadius={120}
              fill="#8884d8"
              dataKey="value"
            >
              {chartData.map((_entry, index) => (
                <Cell key={`cell-${index}`} fill={COLORS[index % COLORS.length]} />
              ))}
            </Pie>
            <Tooltip content={<CustomTooltip />} />
            <Legend
              verticalAlign="bottom"
              height={36}
              formatter={((value: any, _entry: any) => (
                <span className="text-theme-primary text-sm">
                  {value} - ${(_entry?.payload?.value ?? 0).toFixed(2)}
                </span>
              )) as any}
            />
          </PieChart>
        </ResponsiveContainer>
      ) : (
        <ResponsiveContainer width="100%" height={400}>
          <BarChart data={chartData} margin={{ top: 20, right: 30, left: 20, bottom: 60 }}>
            <CartesianGrid strokeDasharray="3 3" stroke="var(--theme-border)" />
            <XAxis
              dataKey="name"
              angle={-45}
              textAnchor="end"
              height={100}
              tick={{ fill: 'var(--theme-text-secondary)', fontSize: 12 }}
            />
            <YAxis
              tick={{ fill: 'var(--theme-text-secondary)', fontSize: 12 }}
              label={{
                value: 'Cost ($)',
                angle: -90,
                position: 'insideLeft',
                style: { fill: 'var(--theme-text-secondary)', fontSize: 12 }
              }}
            />
            <Tooltip content={<CustomTooltip />} />
            <Bar dataKey="value" fill="#3b82f6" radius={[8, 8, 0, 0]}>
              {chartData.map((_entry, index) => (
                <Cell key={`cell-${index}`} fill={COLORS[index % COLORS.length]} />
              ))}
            </Bar>
          </BarChart>
        </ResponsiveContainer>
      )}

      {/* Summary Table */}
      <div className="mt-6 pt-6 border-t border-theme">
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div>
            <h4 className="text-sm font-medium text-theme-primary mb-2">Top 3 by Cost</h4>
            <div className="space-y-2">
              {chartData.slice(0, 3).map((item, index) => (
                <div key={item.name} className="flex items-center justify-between text-sm">
                  <div className="flex items-center gap-2">
                    <div
                      className="w-3 h-3 rounded-full"
                      style={{ backgroundColor: COLORS[index % COLORS.length] }}
                    />
                    <span className="text-theme-primary">{item.name}</span>
                  </div>
                  <span className="font-semibold text-theme-primary">${item.value.toFixed(2)}</span>
                </div>
              ))}
            </div>
          </div>

          <div>
            <h4 className="text-sm font-medium text-theme-primary mb-2">Cost Statistics</h4>
            <div className="space-y-2 text-sm">
              <div className="flex justify-between">
                <span className="text-theme-secondary">Total Items:</span>
                <span className="font-medium text-theme-primary">{chartData.length}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-theme-secondary">Highest Cost:</span>
                <span className="font-medium text-theme-primary">${chartData[0]?.value.toFixed(2)}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-theme-secondary">Average Cost:</span>
                <span className="font-medium text-theme-primary">
                  ${(chartData.reduce((sum, item) => sum + item.value, 0) / chartData.length).toFixed(2)}
                </span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Card>
  );
};

import React from 'react';
import type { PieLabelRenderProps } from 'recharts';

export const PERIOD_OPTIONS = [7, 14, 30, 90];

export const CHART_COLORS = [
  'var(--color-success, #10B981)',
  'var(--color-info, #3B82F6)',
  'var(--color-warning, #F59E0B)',
  'var(--color-interactive-primary, #8B5CF6)',
  'var(--color-danger, #EF4444)',
  '#06B6D4', '#EC4899', '#84CC16', '#F97316', '#6366F1',
];

export const tooltipStyle = {
  backgroundColor: 'var(--theme-bg-secondary)',
  border: '1px solid var(--theme-border)',
  borderRadius: '8px',
  fontSize: '12px',
};

export const formatCurrency = (v: number): string =>
  new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD', minimumFractionDigits: 2, maximumFractionDigits: 4 }).format(v);

export const formatDuration = (ms: number | null | undefined): string => {
  if (ms == null) return '—';
  if (ms < 1000) return `${Math.round(ms)}ms`;
  if (ms < 60000) return `${(ms / 1000).toFixed(1)}s`;
  return `${(ms / 60000).toFixed(1)}m`;
};

export const formatNumber = (n: number | null | undefined): string => {
  if (n == null) return '—';
  return n.toLocaleString();
};

export const mapToChartData = (record: Record<string, number>): Array<{ name: string; value: number }> =>
  Object.entries(record).map(([name, value]) => ({ name, value: Number(value) || 0 }));

export const mapTimeSeriesData = (primary: Record<string, number>, secondary?: Record<string, number>, primaryKey = 'value', secondaryKey = 'value2') =>
  Object.entries(primary).map(([date, val]) => ({
    date: new Date(date).toLocaleDateString('en-US', { month: 'short', day: 'numeric' }),
    [primaryKey]: Number(val) || 0,
    ...(secondary ? { [secondaryKey]: Number(secondary[date]) || 0 } : {}),
  }));

export const KpiCard: React.FC<{ label: string; value: string | number; subtext?: string }> = ({ label, value, subtext }) => (
  <div className="bg-theme-surface border border-theme rounded-lg p-4">
    <p className="text-xs text-theme-secondary truncate">{label}</p>
    <p className="text-xl font-bold text-theme-primary mt-1">{value}</p>
    {subtext && <p className="text-xs text-theme-secondary mt-1">{subtext}</p>}
  </div>
);

export const renderPieLabel = (props: PieLabelRenderProps) => {
  const name = props.name ?? '';
  const percent = typeof props.percent === 'number' ? props.percent : 0;
  return percent > 0.05 ? `${name} (${(percent * 100).toFixed(0)}%)` : '';
};

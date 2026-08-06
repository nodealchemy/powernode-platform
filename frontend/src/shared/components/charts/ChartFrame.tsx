import React from 'react';

export interface ChartFrameProps {
  /** Names the chart. For a single-series chart this replaces a legend. */
  title: string;
  /** Optional one-line context (period, unit, source). */
  subtitle?: string;
  /** Fixed plot height in px. Charts need a resolved height to size against. */
  height?: number;
  /** Optional controls rendered on the title row (filters, range switch). */
  actions?: React.ReactNode;
  className?: string;
  children: React.ReactNode;
}

/**
 * Titled, fixed-height container for any chart.
 *
 * Deliberately renderer-agnostic — it knows nothing about recharts or SVG, so a
 * recharts `ResponsiveContainer`, a `Sparkline`, or a plain table can all sit
 * inside it and pick up the same surface, border and title treatment.
 */
export const ChartFrame: React.FC<ChartFrameProps> = ({
  title,
  subtitle,
  height = 260,
  actions,
  className = '',
  children
}) => (
  <div
    data-testid="chart-frame"
    className={`bg-theme-surface border border-theme rounded-lg p-4 ${className}`}
  >
    <div className="flex items-start justify-between gap-3 mb-3">
      <div className="min-w-0">
        <h4 className="text-sm font-medium text-theme-primary truncate">{title}</h4>
        {subtitle && <p className="text-xs text-theme-tertiary mt-0.5 truncate">{subtitle}</p>}
      </div>
      {actions && <div className="flex items-center gap-2 shrink-0">{actions}</div>}
    </div>
    <div className="w-full" style={{ height }} data-testid="chart-frame-body">
      {children}
    </div>
  </div>
);

export default ChartFrame;

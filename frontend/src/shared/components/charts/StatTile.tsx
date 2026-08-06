import React from 'react';
import { Card } from '@/shared/components/ui/Card';

export interface StatTileProps {
  /** Eyebrow label — what is being measured. Sentence case, no trailing colon. */
  label: string;
  /** The headline figure. Numbers are locale-formatted. */
  value: string | number;
  /** Unit or suffix rendered beside the value ("ms", "%", "nodes"). */
  unit?: string;
  /** Supporting line under the figure — comparison, period, or context. */
  sub?: React.ReactNode;
  /** Optional glyph on the label row. */
  icon?: string | React.ReactNode;
  onClick?: () => void;
  className?: string;
  /**
   * Chart slot: a `Sparkline`, `MeterBar`, or any small mark that qualifies the
   * figure. Rendered under the value so the number stays the entry point.
   */
  children?: React.ReactNode;
}

/**
 * Headline figure with an optional inline chart.
 *
 * Shares `Card` and the type scale with `MetricCard`, so a dashboard can mix
 * the two, but adds a slot for a mark. Note that the value stays in text ink,
 * never a series colour — the mark in the slot carries identity.
 */
export const StatTile: React.FC<StatTileProps> = ({
  label,
  value,
  unit,
  sub,
  icon,
  onClick,
  className = '',
  children
}) => (
  <Card
    variant="elevated"
    padding="lg"
    hoverable={!!onClick}
    clickable={!!onClick}
    onClick={onClick}
    className={className}
    data-testid="stat-tile"
  >
    <div className="space-y-3">
      <div className="flex items-center justify-between gap-2">
        <h3 className="text-xs font-medium uppercase tracking-wide text-theme-secondary truncate">
          {label}
        </h3>
        {icon && (
          <div className="w-6 h-6 flex items-center justify-center shrink-0">
            {typeof icon === 'string' ? <span className="text-base">{icon}</span> : icon}
          </div>
        )}
      </div>

      <div className="space-y-1">
        <div className="flex items-baseline gap-1">
          <span data-testid="stat-tile-value" className="text-2xl font-bold text-theme-primary">
            {typeof value === 'number' ? value.toLocaleString() : value}
          </span>
          {unit && (
            <span data-testid="stat-tile-unit" className="text-sm font-medium text-theme-secondary">
              {unit}
            </span>
          )}
        </div>
        {sub && (
          <div data-testid="stat-tile-sub" className="text-xs text-theme-tertiary">
            {sub}
          </div>
        )}
      </div>

      {children && <div data-testid="stat-tile-chart">{children}</div>}
    </div>
  </Card>
);

export default StatTile;

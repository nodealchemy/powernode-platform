import React from 'react';
import { ChartTone, useChartTone } from '@/shared/components/charts/tones';

export interface MeterBarProps {
  /** Current value. Clamped to `[0, max]` for display. */
  value: number;
  /** Full-scale value. Non-positive values render an empty meter. */
  max: number;
  /**
   * Optional threshold rule drawn across the track, as a fraction of `max`
   * (0–1) — a quota, budget cap or SLO line.
   */
  capMarker?: number;
  tone?: ChartTone;
  /** Track thickness in px. */
  height?: number;
  /** Screen-reader description of what is being measured. */
  ariaLabel?: string;
  className?: string;
}

const clamp = (n: number, lower: number, upper: number): number =>
  Math.min(Math.max(n, lower), upper);

/** Percentages are rounded so the rendered width is stable across re-renders. */
const round = (n: number): number => Math.round(n * 100) / 100;

/**
 * Horizontal utilisation meter: one value against a known ceiling.
 *
 * Use for bounded ratios (disk used / capacity, spend / budget). For an
 * unbounded quantity use a bar chart or a `StatTile` instead — a meter implies
 * the maximum is meaningful.
 */
export const MeterBar: React.FC<MeterBarProps> = ({
  value,
  max,
  capMarker,
  tone = 'primary',
  height = 8,
  ariaLabel,
  className = ''
}) => {
  const { color, track, muted } = useChartTone(tone);

  const safeMax = Number.isFinite(max) && max > 0 ? max : 0;
  const safeValue = Number.isFinite(value) ? clamp(value, 0, safeMax) : 0;
  const fraction = safeMax > 0 ? safeValue / safeMax : 0;

  const hasCap = typeof capMarker === 'number' && Number.isFinite(capMarker);
  const capFraction = hasCap ? clamp(capMarker, 0, 1) : 0;

  return (
    <div
      data-testid="meter-bar"
      role="progressbar"
      aria-label={ariaLabel}
      aria-valuenow={safeValue}
      aria-valuemin={0}
      aria-valuemax={safeMax}
      className={`relative w-full rounded-full overflow-hidden ${className}`}
      style={{ height, backgroundColor: track }}
    >
      <div
        data-testid="meter-bar-fill"
        className="h-full rounded-full transition-all duration-300 ease-out"
        style={{ width: `${round(fraction * 100)}%`, backgroundColor: color }}
      />
      {hasCap && (
        <div
          data-testid="meter-bar-cap"
          aria-hidden="true"
          className="absolute top-0 h-full"
          style={{ left: `calc(${round(capFraction * 100)}% - 1px)`, width: 2, backgroundColor: muted }}
        />
      )}
    </div>
  );
};

export default MeterBar;

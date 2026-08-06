import React from 'react';
import { ChartTone, useChartTone } from '@/shared/components/charts/tones';

export interface SparklineProps {
  /** Single series, oldest → newest. Non-finite entries are dropped. */
  data: number[];
  width?: number;
  height?: number;
  tone?: ChartTone;
  /** Short direct label pinned to the endpoint (e.g. "42/s"). */
  endLabel?: string;
  /** Screen-reader description; falls back to a generic trend summary. */
  ariaLabel?: string;
  className?: string;
}

/** 2px stroke per the chart-kit mark spec — thin marks, recessive chrome. */
const STROKE_WIDTH = 2;
/** Endpoint dot radius. */
const DOT_RADIUS = 3;
/** Inset so the dot and its surface ring never clip at the viewBox edge. */
const PADDING = DOT_RADIUS + STROKE_WIDTH / 2;

/** Two decimals keeps the emitted geometry stable and diffable. */
const round = (n: number): number => Math.round(n * 100) / 100;

/**
 * Single-series trend line in pure SVG — no charting library.
 *
 * Sized for inline use inside a `StatTile` or a table cell: no axes, no grid,
 * no tooltip. When a reader needs values, pair it with the tile's number or
 * promote the series to a full `ChartFrame` chart instead.
 */
export const Sparkline: React.FC<SparklineProps> = ({
  data,
  width = 160,
  height = 34,
  tone = 'primary',
  endLabel,
  ariaLabel,
  className = ''
}) => {
  const { color, surface } = useChartTone(tone);

  const series = data.filter((value) => Number.isFinite(value));
  if (series.length === 0) return null;

  const min = Math.min(...series);
  const max = Math.max(...series);
  const span = max - min;

  const innerWidth = Math.max(width - PADDING * 2, 1);
  const innerHeight = Math.max(height - PADDING * 2, 1);

  const x = (index: number): number =>
    series.length === 1
      ? round(PADDING + innerWidth)
      : round(PADDING + (index * innerWidth) / (series.length - 1));

  // SVG y grows downward, so the largest value maps to the smallest y.
  const y = (value: number): number =>
    span === 0
      ? round(PADDING + innerHeight / 2)
      : round(PADDING + innerHeight - ((value - min) / span) * innerHeight);

  const points = series.map((value, index) => `${x(index)},${y(value)}`);
  const endX = x(series.length - 1);
  const endY = y(series[series.length - 1]);

  const label =
    ariaLabel ??
    `Trend over ${series.length} points, from ${series[0]} to ${series[series.length - 1]}`;

  return (
    <svg
      data-testid="sparkline"
      role="img"
      aria-label={label}
      className={`overflow-visible ${className}`}
      width={width}
      height={height}
      viewBox={`0 0 ${width} ${height}`}
    >
      <polyline
        data-testid="sparkline-line"
        points={points.join(' ')}
        fill="none"
        stroke={color}
        strokeWidth={STROKE_WIDTH}
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      {/* Emphasised endpoint: the current value, ringed in the surface colour so
          it stays legible where it overlaps the line. */}
      <circle
        data-testid="sparkline-endpoint"
        cx={endX}
        cy={endY}
        r={DOT_RADIUS}
        fill={color}
        stroke={surface}
        strokeWidth={STROKE_WIDTH}
      />
      {endLabel && (
        <text
          data-testid="sparkline-end-label"
          x={endX + DOT_RADIUS + 3}
          y={endY}
          dominantBaseline="middle"
          className="fill-current text-theme-secondary"
          style={{ fontSize: 10 }}
        >
          {endLabel}
        </text>
      )}
    </svg>
  );
};

export default Sparkline;

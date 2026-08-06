// Shared chart kit — theme-aware primitives for dashboards.
// Colour flows through `useChartTone` (backed by `useChartColors`); components
// must never hardcode a hue.
export { ChartFrame } from '@/shared/components/charts/ChartFrame';
export type { ChartFrameProps } from '@/shared/components/charts/ChartFrame';

export { Sparkline } from '@/shared/components/charts/Sparkline';
export type { SparklineProps } from '@/shared/components/charts/Sparkline';

export { StatTile } from '@/shared/components/charts/StatTile';
export type { StatTileProps } from '@/shared/components/charts/StatTile';

export { MeterBar } from '@/shared/components/charts/MeterBar';
export type { MeterBarProps } from '@/shared/components/charts/MeterBar';

export { useChartTone } from '@/shared/components/charts/tones';
export type { ChartTone, ChartToneColors } from '@/shared/components/charts/tones';

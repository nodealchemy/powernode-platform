import { useChartColors } from '@/shared/hooks/useThemeColors';

/**
 * Semantic tone slots for the shared chart kit.
 *
 * Tones are *roles*, not hues: callers say what a mark means and the theme
 * decides what colour that is in the current mode. This is the only place the
 * kit knows about colour, so a theme change is a one-file change.
 */
export type ChartTone = 'primary' | 'success' | 'warning' | 'error' | 'info' | 'neutral';

export interface ChartToneColors {
  /** Colour of the data mark itself (line, fill, dot). */
  color: string;
  /** Recessive backing for the same mark (meter track, area wash). */
  track: string;
  /** Current chart surface — used for the 2px ring that separates overlapping marks. */
  surface: string;
  /** De-emphasised ink for markers, rules and captions drawn inside a chart. */
  muted: string;
}

/**
 * CSS-variable fallbacks, used until `useChartColors` has read the computed
 * styles (first paint) and in environments where the stylesheet is absent
 * (jsdom). They resolve through the same theme tokens the hook reads, so the
 * fallback path stays theme-aware rather than freezing a light-mode hue.
 *
 * Status tones deliberately use the *semantic* tokens (`--color-success`, …)
 * rather than a fixed `-500` step: the theme picks a darker step on light
 * surfaces and a lighter one on dark surfaces.
 */
const TONE_FALLBACKS: Record<ChartTone, { color: string; track: string }> = {
  primary: { color: 'var(--color-primary-500)', track: 'var(--color-surface-selected)' },
  success: { color: 'var(--color-success)', track: 'var(--color-success-background)' },
  warning: { color: 'var(--color-warning)', track: 'var(--color-warning-background)' },
  error: { color: 'var(--color-error)', track: 'var(--color-error-background)' },
  info: { color: 'var(--color-info)', track: 'var(--color-info-background)' },
  neutral: { color: 'var(--color-text-secondary)', track: 'var(--color-border)' }
};

const SURFACE_FALLBACK = 'var(--color-surface)';
const MUTED_FALLBACK = 'var(--color-text-secondary)';

/** First non-empty value wins; keeps the kit safe when a token is undefined. */
const firstDefined = (...candidates: string[]): string => {
  for (const candidate of candidates) {
    if (candidate) return candidate;
  }
  return '';
};

/**
 * Resolves a tone to concrete colours for the current theme.
 *
 * This is the chart kit's single consumer of `useChartColors`, which reads the
 * theme's CSS custom properties and re-reads them whenever the document theme
 * flips. Components must never hardcode a hue.
 */
export const useChartTone = (tone: ChartTone = 'primary'): ChartToneColors => {
  const colors = useChartColors();
  const fallback = TONE_FALLBACKS[tone] ?? TONE_FALLBACKS.primary;

  const byTone: Record<ChartTone, { color: string; track: string }> = {
    primary: { color: colors.primary, track: colors.primaryLight },
    success: { color: colors.success, track: colors.successLight },
    warning: { color: colors.warning, track: colors.warningLight },
    error: { color: colors.error, track: colors.errorLight },
    info: { color: colors.info, track: colors.infoLight },
    neutral: { color: colors.textSecondary, track: colors.border }
  };

  const resolved = byTone[tone] ?? byTone.primary;

  return {
    color: firstDefined(resolved.color, fallback.color),
    track: firstDefined(resolved.track, fallback.track),
    surface: firstDefined(colors.surface, SURFACE_FALLBACK),
    muted: firstDefined(colors.textSecondary, MUTED_FALLBACK)
  };
};

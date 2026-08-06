import { useEffect, useState } from 'react';

interface ThemeColors {
  primary: string;
  success: string;
  warning: string;
  error: string;
  info: string;
  border: string;
  textPrimary: string;
  textSecondary: string;
  surface: string;
  background: string;
  // Light variants for backgrounds
  primaryLight: string;
  successLight: string;
  warningLight: string;
  errorLight: string;
  infoLight: string;
}

/** Returns the first CSS custom property that resolves to a non-empty value. */
const readVar = (styles: CSSStyleDeclaration, ...names: string[]): string => {
  for (const name of names) {
    const value = styles.getPropertyValue(name).trim();
    if (value) return value;
  }
  return '';
};

/**
 * Resolves theme colours to concrete values, for consumers that need a colour
 * string rather than a CSS class (SVG attributes, canvas, chart libraries).
 *
 * Reads the document's computed custom properties and re-reads them when the
 * theme flips. It deliberately does NOT depend on `ThemeContext`: it tracks the
 * `class`/`data-theme` attributes that `ThemeProvider` writes onto the document
 * element, so a component using it renders correctly anywhere — including in
 * tests, which mount a stub theme provider.
 */
export const useThemeColors = (): ThemeColors => {
  const [colors, setColors] = useState<ThemeColors>({
    primary: '',
    success: '',
    warning: '',
    error: '',
    info: '',
    border: '',
    textPrimary: '',
    textSecondary: '',
    surface: '',
    background: '',
    primaryLight: '',
    successLight: '',
    warningLight: '',
    errorLight: '',
    infoLight: ''
  });

  useEffect(() => {
    const updateColors = () => {
      // Get computed styles from the document root
      const rootStyles = getComputedStyle(document.documentElement);
      
      // Prefer the semantic tokens: the theme picks a darker step of each ramp
      // on light surfaces and a lighter one on dark, so a mark stays legible in
      // both modes. The raw `-500` steps are the fallback — they are fixed hues
      // and do not respond to the theme.
      setColors({
        primary: readVar(rootStyles, '--color-primary-500'),
        success: readVar(rootStyles, '--color-success', '--color-success-500'),
        warning: readVar(rootStyles, '--color-warning', '--color-warning-500'),
        error: readVar(rootStyles, '--color-error', '--color-error-500'),
        info: readVar(rootStyles, '--color-info', '--color-info-500'),
        border: readVar(rootStyles, '--color-border', '--color-neutral-200'),
        textPrimary: readVar(rootStyles, '--color-text-primary'),
        textSecondary: readVar(rootStyles, '--color-text-secondary'),
        surface: readVar(rootStyles, '--color-surface'),
        background: readVar(rootStyles, '--color-background'),
        // Light variants (tinted backgrounds behind a mark of the same hue)
        primaryLight: readVar(rootStyles, '--color-surface-selected', '--color-primary-50'),
        successLight: readVar(rootStyles, '--color-success-background', '--color-success-50'),
        warningLight: readVar(rootStyles, '--color-warning-background', '--color-warning-50'),
        errorLight: readVar(rootStyles, '--color-error-background', '--color-error-50'),
        infoLight: readVar(rootStyles, '--color-info-background', '--color-info-50')
      });
    };

    // Update colors immediately
    updateColors();

    // ThemeProvider swaps both the `light`/`dark` class and `data-theme` on the
    // document element; either one means the custom properties have changed.
    const observer = new MutationObserver(updateColors);

    observer.observe(document.documentElement, {
      attributes: true,
      attributeFilter: ['class', 'data-theme']
    });

    return () => observer.disconnect();
  }, []);

  return colors;
};

/**
 * Chart-specific colour palette.
 *
 * Consumed by the shared chart kit (`@/shared/components/charts`) via
 * `useChartTone`, which is the seam every chart primitive uses to resolve a
 * semantic tone to a theme-aware colour. Chart code should go through the kit
 * rather than reading tokens directly.
 */
export const useChartColors = () => {
  const colors = useThemeColors();
  
  return {
    ...colors,
    // Chart-specific color arrays
    chartPalette: [
      colors.primary,
      colors.success,
      colors.info,
      colors.warning,
      colors.error,
    ],
    // Growth-based colors
    getGrowthColor: (value: number) => {
      if (value > 5) return colors.success;
      if (value > 0) return colors.info;
      if (value > -5) return colors.warning;
      return colors.error;
    },
    // Churn-based colors
    getChurnColor: (rate: number) => {
      if (rate < 2) return colors.success;
      if (rate < 5) return colors.warning;
      return colors.error;
    }
  };
};
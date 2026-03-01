import { useEffect, useState } from 'react';
import { useTheme } from '@/shared/hooks/ThemeContext';

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

export const useThemeColors = (): ThemeColors => {
  const { theme } = useTheme();
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
      
      setColors({
        primary: rootStyles.getPropertyValue('--color-primary-500').trim(),
        success: rootStyles.getPropertyValue('--color-success-500').trim(),
        warning: rootStyles.getPropertyValue('--color-warning-500').trim(),
        error: rootStyles.getPropertyValue('--color-error-500').trim(),
        info: rootStyles.getPropertyValue('--color-info-500').trim(),
        border: rootStyles.getPropertyValue('--color-neutral-200').trim(),
        textPrimary: rootStyles.getPropertyValue('--color-text-primary').trim(),
        textSecondary: rootStyles.getPropertyValue('--color-text-secondary').trim(),
        surface: rootStyles.getPropertyValue('--color-surface').trim(),
        background: rootStyles.getPropertyValue('--color-background').trim(),
        // Light variants
        primaryLight: rootStyles.getPropertyValue('--color-primary-50').trim(),
        successLight: rootStyles.getPropertyValue('--color-success-50').trim(),
        warningLight: rootStyles.getPropertyValue('--color-warning-50').trim(),
        errorLight: rootStyles.getPropertyValue('--color-error-50').trim(),
        infoLight: rootStyles.getPropertyValue('--color-info-50').trim()
      });
    };

    // Update colors immediately
    updateColors();

    // Also update when theme changes or when DOM is ready
    const observer = new MutationObserver((mutations) => {
      mutations.forEach((mutation) => {
        if (mutation.type === 'attributes' && mutation.attributeName === 'class') {
          updateColors();
        }
      });
    });

    observer.observe(document.documentElement, {
      attributes: true,
      attributeFilter: ['class']
    });

    return () => observer.disconnect();
  }, [theme]);

  return colors;
};

// Chart-specific color palette hook
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
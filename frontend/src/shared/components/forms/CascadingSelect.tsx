import React, { useState, useCallback } from 'react';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';

interface CascadingOption {
  value: string;
  label: string;
  disabled?: boolean;
}

interface CascadingLevel {
  name: string;
  label: string;
  placeholder?: string;
  required?: boolean;
  options: CascadingOption[];
  loading?: boolean;
}

interface CascadingSelectProps {
  /** Array of select levels in cascade order (e.g., [provider, region, zone]) */
  levels: CascadingLevel[];
  /** Current values for each level by name */
  values: Record<string, string>;
  /** Callback when any value changes, receives updated values and the level that changed */
  onChange: (values: Record<string, string>, changedLevel: string) => void;
  /** Optional callback to fetch options for a level when parent value changes */
  onLevelChange?: (level: string, parentValue: string) => Promise<CascadingOption[]>;
  /** Optional class name */
  className?: string;
  /** Whether the entire component is disabled */
  disabled?: boolean;
  /** Errors for each field by name */
  errors?: Record<string, string>;
  /** Help text for each field by name */
  helpTexts?: Record<string, string>;
}

/**
 * CascadingSelect - A series of dependent dropdown selects
 * When a parent select changes, child selects reset and can fetch new options.
 *
 * Common use cases:
 * - Provider → Region → Availability Zone
 * - Country → State → City
 * - Category → Subcategory → Item
 */
export const CascadingSelect: React.FC<CascadingSelectProps> = ({
  levels,
  values,
  onChange,
  onLevelChange,
  className = '',
  disabled = false,
  errors = {},
  helpTexts = {}
}) => {
  const [loadingLevels, setLoadingLevels] = useState<Record<string, boolean>>({});

  // Handle selection change at a specific level
  const handleChange = useCallback(async (levelIndex: number, newValue: string) => {
    const level = levels[levelIndex];
    const newValues = { ...values };

    // Set the new value for this level
    newValues[level.name] = newValue;

    // Reset all child levels (levels after this one)
    for (let i = levelIndex + 1; i < levels.length; i++) {
      newValues[levels[i].name] = '';
    }

    // Notify parent of changes
    onChange(newValues, level.name);

    // If there's a next level and a callback to fetch options, trigger it
    if (newValue && onLevelChange && levelIndex + 1 < levels.length) {
      const nextLevel = levels[levelIndex + 1];
      setLoadingLevels(prev => ({ ...prev, [nextLevel.name]: true }));

      try {
        await onLevelChange(nextLevel.name, newValue);
      } finally {
        setLoadingLevels(prev => ({ ...prev, [nextLevel.name]: false }));
      }
    }
  }, [levels, values, onChange, onLevelChange]);

  // Check if a level should be disabled (parent not selected)
  const isLevelDisabled = useCallback((levelIndex: number): boolean => {
    if (disabled) return true;
    if (levelIndex === 0) return false;

    // Check if all parent levels have values
    for (let i = 0; i < levelIndex; i++) {
      if (!values[levels[i].name]) return true;
    }
    return false;
  }, [disabled, levels, values]);

  return (
    <div className={`space-y-4 ${className}`}>
      {levels.map((level, index) => {
        const levelDisabled = isLevelDisabled(index);
        const isLoading = loadingLevels[level.name] || level.loading;
        const hasError = !!errors[level.name];
        const value = values[level.name] || '';

        return (
          <div key={level.name}>
            <label
              htmlFor={level.name}
              className="block text-sm font-semibold text-theme-primary mb-2"
            >
              {level.label}
              {level.required && <span className="text-theme-error ml-1">*</span>}
            </label>

            <div className="relative">
              <select
                id={level.name}
                name={level.name}
                value={value}
                onChange={(e) => handleChange(index, e.target.value)}
                disabled={levelDisabled || isLoading}
                className={`w-full px-4 py-3 border rounded-lg bg-theme-surface focus:ring-2 focus:ring-theme-focus focus:border-transparent transition-colors ${
                  hasError
                    ? 'border-theme-error focus:ring-theme-error-focus'
                    : 'border-theme'
                } ${
                  levelDisabled || isLoading
                    ? 'opacity-60 cursor-not-allowed'
                    : ''
                }`}
                aria-invalid={hasError}
                aria-describedby={hasError ? `${level.name}-error` : undefined}
              >
                <option value="" disabled={level.required}>
                  {isLoading ? 'Loading...' : (level.placeholder || `Select ${level.label}...`)}
                </option>
                {level.options.map(option => (
                  <option
                    key={option.value}
                    value={option.value}
                    disabled={option.disabled}
                  >
                    {option.label}
                  </option>
                ))}
              </select>

              {isLoading && (
                <div className="absolute right-3 top-1/2 -translate-y-1/2">
                  <LoadingSpinner size="sm" />
                </div>
              )}
            </div>

            {hasError && (
              <p
                id={`${level.name}-error`}
                className="mt-1 text-sm text-theme-error flex items-center space-x-1"
                role="alert"
              >
                <svg className="w-4 h-4 flex-shrink-0" fill="currentColor" viewBox="0 0 20 20">
                  <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7 4a1 1 0 11-2 0 1 1 0 012 0zm-1-9a1 1 0 00-1 1v4a1 1 0 102 0V6a1 1 0 00-1-1z" clipRule="evenodd" />
                </svg>
                <span>{errors[level.name]}</span>
              </p>
            )}

            {helpTexts[level.name] && !hasError && (
              <p className="mt-1 text-sm text-theme-tertiary">
                {helpTexts[level.name]}
              </p>
            )}
          </div>
        );
      })}
    </div>
  );
};

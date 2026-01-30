import React, { useState, useEffect } from 'react';
import { BranchFilterType } from '../types';

interface BranchFilterFormProps {
  initialFilterType?: BranchFilterType;
  initialFilterPattern?: string;
  onSave: (filterType: BranchFilterType, filterPattern?: string) => Promise<void>;
  onCancel?: () => void;
  disabled?: boolean;
}

const FILTER_TYPE_OPTIONS: { value: BranchFilterType; label: string; description: string }[] = [
  {
    value: 'none',
    label: 'No Filter',
    description: 'Process webhooks from all branches',
  },
  {
    value: 'exact',
    label: 'Exact Match',
    description: 'Only process webhooks from a specific branch name',
  },
  {
    value: 'wildcard',
    label: 'Wildcard Pattern',
    description: 'Use * for any characters, ** for any path (e.g., feature/*, release/**)',
  },
  {
    value: 'regex',
    label: 'Regular Expression',
    description: 'Use full regex patterns for complex matching',
  },
];

const PATTERN_EXAMPLES: Record<BranchFilterType, string[]> = {
  none: [],
  exact: ['main', 'master', 'develop', 'production'],
  wildcard: ['feature/*', 'release/**', 'hotfix/*', 'bugfix/*'],
  regex: ['^(main|master|develop)$', '^release/\\d+\\.\\d+$', '^feature/JIRA-\\d+'],
};

export const BranchFilterForm: React.FC<BranchFilterFormProps> = ({
  initialFilterType = 'none',
  initialFilterPattern = '',
  onSave,
  onCancel,
  disabled = false,
}) => {
  const [filterType, setFilterType] = useState<BranchFilterType>(initialFilterType);
  const [filterPattern, setFilterPattern] = useState(initialFilterPattern);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    setFilterType(initialFilterType);
    setFilterPattern(initialFilterPattern);
  }, [initialFilterType, initialFilterPattern]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);

    if (filterType !== 'none' && !filterPattern.trim()) {
      setError('Pattern is required when a filter type is selected');
      return;
    }

    // Validate regex pattern
    if (filterType === 'regex') {
      try {
        new RegExp(filterPattern);
      } catch {
        setError('Invalid regular expression pattern');
        return;
      }
    }

    setIsSubmitting(true);
    try {
      await onSave(filterType, filterType === 'none' ? undefined : filterPattern.trim());
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to save branch filter');
    } finally {
      setIsSubmitting(false);
    }
  };

  const selectedOption = FILTER_TYPE_OPTIONS.find((opt) => opt.value === filterType);
  const examples = PATTERN_EXAMPLES[filterType] || [];

  return (
    <form onSubmit={handleSubmit} className="space-y-4">
      {/* Filter Type Selection */}
      <div>
        <label className="block text-sm font-medium text-theme-text-primary mb-2">
          Branch Filter Type
        </label>
        <div className="space-y-2">
          {FILTER_TYPE_OPTIONS.map((option) => (
            <label
              key={option.value}
              className={`flex items-start p-3 rounded-lg border cursor-pointer transition-colors ${
                filterType === option.value
                  ? 'border-theme-primary bg-theme-primary/5'
                  : 'border-theme-border hover:border-theme-border-hover'
              } ${disabled ? 'opacity-50 cursor-not-allowed' : ''}`}
            >
              <input
                type="radio"
                name="filterType"
                value={option.value}
                checked={filterType === option.value}
                onChange={(e) => setFilterType(e.target.value as BranchFilterType)}
                disabled={disabled}
                className="mt-1 mr-3"
              />
              <div>
                <span className="font-medium text-theme-text-primary">{option.label}</span>
                <p className="text-sm text-theme-text-secondary mt-0.5">{option.description}</p>
              </div>
            </label>
          ))}
        </div>
      </div>

      {/* Pattern Input */}
      {filterType !== 'none' && (
        <div>
          <label
            htmlFor="filterPattern"
            className="block text-sm font-medium text-theme-text-primary mb-1"
          >
            {filterType === 'exact' ? 'Branch Name' : 'Pattern'}
          </label>
          <input
            type="text"
            id="filterPattern"
            value={filterPattern}
            onChange={(e) => setFilterPattern(e.target.value)}
            placeholder={
              filterType === 'exact'
                ? 'e.g., main'
                : filterType === 'wildcard'
                  ? 'e.g., feature/*'
                  : 'e.g., ^(main|develop)$'
            }
            disabled={disabled}
            className="w-full px-3 py-2 border border-theme-border rounded-lg bg-theme-bg-secondary text-theme-text-primary placeholder-theme-text-tertiary focus:outline-none focus:ring-2 focus:ring-theme-primary focus:border-transparent"
          />
          {examples.length > 0 && (
            <div className="mt-2">
              <span className="text-xs text-theme-text-secondary">Examples: </span>
              <div className="flex flex-wrap gap-1 mt-1">
                {examples.map((example) => (
                  <button
                    key={example}
                    type="button"
                    onClick={() => setFilterPattern(example)}
                    disabled={disabled}
                    className="px-2 py-0.5 text-xs bg-theme-bg-tertiary text-theme-text-secondary rounded hover:bg-theme-bg-hover hover:text-theme-text-primary transition-colors"
                  >
                    {example}
                  </button>
                ))}
              </div>
            </div>
          )}
        </div>
      )}

      {/* Preview */}
      {filterType !== 'none' && filterPattern && (
        <div className="p-3 bg-theme-bg-tertiary rounded-lg">
          <div className="text-sm font-medium text-theme-text-primary mb-1">Preview</div>
          <div className="text-sm text-theme-text-secondary">
            {filterType === 'exact' && (
              <>
                Only webhooks from branch <code className="text-theme-primary">{filterPattern}</code>{' '}
                will be processed.
              </>
            )}
            {filterType === 'wildcard' && (
              <>
                Webhooks from branches matching{' '}
                <code className="text-theme-primary">{filterPattern}</code> will be processed.
              </>
            )}
            {filterType === 'regex' && (
              <>
                Webhooks from branches matching regex{' '}
                <code className="text-theme-primary">{filterPattern}</code> will be processed.
              </>
            )}
          </div>
        </div>
      )}

      {/* Error Message */}
      {error && (
        <div className="p-3 bg-theme-danger/10 border border-theme-danger/20 rounded-lg">
          <p className="text-sm text-theme-danger">{error}</p>
        </div>
      )}

      {/* Action Buttons */}
      <div className="flex justify-end gap-3 pt-2">
        {onCancel && (
          <button
            type="button"
            onClick={onCancel}
            disabled={isSubmitting}
            className="px-4 py-2 text-sm font-medium text-theme-text-secondary hover:text-theme-text-primary transition-colors"
          >
            Cancel
          </button>
        )}
        <button
          type="submit"
          disabled={disabled || isSubmitting}
          className="px-4 py-2 text-sm font-medium bg-theme-primary text-white rounded-lg hover:bg-theme-primary-hover disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
        >
          {isSubmitting ? 'Saving...' : 'Save Branch Filter'}
        </button>
      </div>
    </form>
  );
};

export default BranchFilterForm;

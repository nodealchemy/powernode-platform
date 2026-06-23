import React from 'react';
import { Globe, User, LayoutGrid } from 'lucide-react';
import type { ContentScope } from '../types';

interface ScopeOption {
  value: ContentScope;
  label: string;
  icon: React.ReactNode;
}

const SCOPE_OPTIONS: ScopeOption[] = [
  { value: 'global', label: 'Global', icon: <Globe className="w-3.5 h-3.5" /> },
  { value: 'custom', label: 'My Custom', icon: <User className="w-3.5 h-3.5" /> },
  { value: 'all', label: 'All', icon: <LayoutGrid className="w-3.5 h-3.5" /> },
];

interface ScopeFilterProps {
  value: ContentScope;
  onChange: (scope: ContentScope) => void;
  className?: string;
}

/**
 * Segmented control for filtering foundational content by ownership scope:
 * Global (platform-provided) · My Custom (account-owned) · All. Drives the
 * `?scope=` list query param. Reused across every content page.
 */
export const ScopeFilter: React.FC<ScopeFilterProps> = ({ value, onChange, className = '' }) => (
  <div
    role="tablist"
    aria-label="Content scope"
    className={`inline-flex items-center gap-0.5 p-1 bg-theme-surface border border-theme rounded-lg ${className}`}
  >
    {SCOPE_OPTIONS.map((option) => {
      const isActive = value === option.value;
      return (
        <button
          key={option.value}
          type="button"
          role="tab"
          aria-selected={isActive}
          onClick={() => onChange(option.value)}
          className={`flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium rounded-md transition-colors ${
            isActive
              ? 'bg-theme-interactive-primary text-white shadow-sm'
              : 'text-theme-secondary hover:text-theme-primary hover:bg-theme-surface-hover'
          }`}
        >
          {option.icon}
          <span>{option.label}</span>
        </button>
      );
    })}
  </div>
);

export default ScopeFilter;

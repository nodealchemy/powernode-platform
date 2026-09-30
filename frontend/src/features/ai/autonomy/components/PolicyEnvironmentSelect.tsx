import React from 'react';
import type { PolicyEnvironmentOption } from '../types/autonomy';

interface PolicyEnvironmentSelectProps {
  options: PolicyEnvironmentOption[];
  value: string[];
  onChange: (slugs: string[]) => void;
}

/**
 * Multi-select for a policy's conditions.environments. Nothing selected means
 * the policy applies in every environment. A slug the row already names that is
 * no longer an environment stays listed (flagged), so the operator can untick it:
 * the server refuses a slug the account does not have.
 */
export const PolicyEnvironmentSelect: React.FC<PolicyEnvironmentSelectProps> = ({ options, value, onChange }) => {
  const known = new Set(options.map(o => o.slug));
  const stale = value.filter(slug => !known.has(slug));

  const toggle = (slug: string) => {
    onChange(value.includes(slug) ? value.filter(s => s !== slug) : [...value, slug]);
  };

  return (
    <div>
      <div className="flex flex-wrap items-center gap-2" role="group" aria-label="Environments">
        <span className="text-sm text-theme-tertiary">Environments:</span>
        {options.map(o => (
          <label key={o.slug} className="flex items-center gap-1 text-xs text-theme-secondary">
            <input
              type="checkbox"
              checked={value.includes(o.slug)}
              onChange={() => toggle(o.slug)}
              className="rounded border-theme"
            />
            {o.name}
          </label>
        ))}
        {stale.map(slug => (
          <label key={slug} className="flex items-center gap-1 text-xs text-theme-error-fg">
            <input
              type="checkbox"
              checked
              onChange={() => toggle(slug)}
              className="rounded border-theme"
            />
            {slug} (no longer an environment)
          </label>
        ))}
      </div>
      <p className="text-xs text-theme-tertiary mt-1">
        {value.length === 0 ? 'None selected: applies in every environment.' : 'Applies only in the selected environments.'}
      </p>
    </div>
  );
};

import React from 'react';
import type { PolicyEnvironmentOption } from '../types/autonomy';

interface PolicyEnvironmentSelectProps {
  options: PolicyEnvironmentOption[];
  /** Where the options list is: only a successfully loaded list can say a slug is stale, and only then may the selection be edited. */
  status: 'loading' | 'error' | 'ready';
  value: string[];
  onChange: (slugs: string[]) => void;
}

/**
 * Multi-select for a policy's conditions.environments. Nothing selected means
 * the policy applies in every environment. A slug the row already names that is
 * no longer an environment stays listed (flagged), so the operator can untick it:
 * the server refuses a slug the account does not have.
 *
 * Until the list has loaded (or if it failed) the selection is shown as it is,
 * unflagged and not editable: an empty options list would otherwise mark every
 * selected slug stale and invite unticking them all, which widens the policy to
 * every environment.
 */
export const PolicyEnvironmentSelect: React.FC<PolicyEnvironmentSelectProps> = ({ options, status, value, onChange }) => {
  const ready = status === 'ready';
  const known = new Set(options.map(o => o.slug));
  const stale = ready ? value.filter(slug => !known.has(slug)) : [];
  const pending = ready ? [] : value;

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
        {pending.map(slug => (
          <label key={slug} className="flex items-center gap-1 text-xs text-theme-secondary">
            <input type="checkbox" checked disabled className="rounded border-theme" />
            {slug}
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
      {status === 'loading' && <p className="text-xs text-theme-tertiary mt-1">Loading environments...</p>}
      {status === 'error' && (
        <p role="alert" className="text-xs text-theme-error-fg mt-1">
          Could not load environments; the selection is unchanged and cannot be edited until they load.
        </p>
      )}
      {ready && (
        <p className="text-xs text-theme-tertiary mt-1">
          {value.length === 0 ? 'None selected: applies in every environment.' : 'Applies only in the selected environments.'}
        </p>
      )}
    </div>
  );
};

import React, { useState } from 'react';
import { Plus, X } from 'lucide-react';

// Hostname or "*.hostname" wildcard. Mirrors Setup::DomainConfigurator on the server.
const LABEL = '[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?';
const DOMAIN_RE = new RegExp(`^(?:\\*\\.)?${LABEL}(?:\\.${LABEL})*$`, 'i');

export const isValidDomain = (value: string): boolean => DOMAIN_RE.test(value.trim());

interface DomainListFieldProps {
  id: string;
  /** Newline-separated domains (the wire format the server splits). */
  value: string;
  onChange: (value: string) => void;
  placeholder?: string;
  disabled?: boolean;
}

const parse = (value: string): string[] =>
  value.split(/[\n,]+/).map((d) => d.trim()).filter(Boolean);

/** Add/remove list editor for extra domains; wildcards like *.example.com are allowed. */
export const DomainListField: React.FC<DomainListFieldProps> = ({
  id,
  value,
  onChange,
  placeholder = 'ops.example.com or *.example.com',
  disabled = false,
}) => {
  const [draft, setDraft] = useState('');
  const [error, setError] = useState<string | null>(null);
  const domains = parse(value);

  const add = () => {
    const next = draft.trim().toLowerCase();
    if (!next) return;
    if (!isValidDomain(next)) {
      setError(`"${next}" is not a valid domain`);
      return;
    }
    setError(null);
    setDraft('');
    if (!domains.includes(next)) onChange([...domains, next].join('\n'));
  };

  const remove = (domain: string) => onChange(domains.filter((d) => d !== domain).join('\n'));

  return (
    <div className="space-y-2" data-testid={`${id}-list`}>
      <div className="flex gap-2">
        <input
          id={id}
          data-testid={id}
          type="text"
          className="w-full rounded-md border border-theme bg-theme-surface px-3 py-2 text-sm text-theme-primary focus:border-theme-interactive-primary focus:outline-none"
          value={draft}
          placeholder={placeholder}
          disabled={disabled}
          autoComplete="off"
          onChange={(e) => setDraft(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter') {
              e.preventDefault();
              add();
            }
          }}
        />
        <button
          type="button"
          data-testid={`${id}-add`}
          className="inline-flex items-center gap-1 rounded-md border border-theme bg-theme-surface px-3 py-2 text-sm text-theme-primary hover:bg-theme-background-secondary disabled:opacity-50"
          disabled={disabled || draft.trim().length === 0}
          onClick={add}
        >
          <Plus className="h-4 w-4" aria-hidden="true" />
          Add
        </button>
      </div>
      {error && (
        <p className="text-xs text-theme-danger-fg" data-testid={`${id}-error`}>
          {error}
        </p>
      )}
      {domains.length > 0 && (
        <ul className="space-y-1">
          {domains.map((domain) => (
            <li
              key={domain}
              className="flex items-center justify-between rounded-md border border-theme bg-theme-background-secondary px-3 py-1 text-sm text-theme-primary"
            >
              <span>{domain}</span>
              <button
                type="button"
                aria-label={`Remove ${domain}`}
                data-testid={`${id}-remove-${domain}`}
                className="text-theme-secondary hover:text-theme-danger-fg"
                disabled={disabled}
                onClick={() => remove(domain)}
              >
                <X className="h-4 w-4" aria-hidden="true" />
              </button>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
};

export default DomainListField;

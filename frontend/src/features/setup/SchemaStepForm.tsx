import React from 'react';
import type { SetupFieldDef } from './services/setupApi';

interface SchemaStepFormProps {
  fields: SetupFieldDef[];
  values: Record<string, string>;
  /** Fired on every edit with the next values and whether all required fields are filled. */
  onChange: (values: Record<string, string>, valid: boolean) => void;
  /** Prefix for field ids / test hooks (e.g. "setup-admin"). */
  idPrefix?: string;
  disabled?: boolean;
}

/**
 * Generic, schema-driven form for a setup step (admin, domain, …). Controlled:
 * the parent owns `values`; this component renders each field from the step's
 * schema and reports `(values, valid)` on edit. Validity = every required field
 * is non-blank. No internal effects — keeps the driver loop-free.
 */
export const SchemaStepForm: React.FC<SchemaStepFormProps> = ({
  fields,
  values,
  onChange,
  idPrefix = 'setup',
  disabled = false,
}) => {
  const computeValid = (next: Record<string, string>): boolean =>
    fields.every((f) => !f.required || (next[f.key] ?? '').trim().length > 0);

  const handle = (key: string, value: string) => {
    const next = { ...values, [key]: value };
    onChange(next, computeValid(next));
  };

  return (
    <div className="space-y-3" data-testid={`${idPrefix}-step-form`}>
      {fields.map((field) => {
        const fieldId = `${idPrefix}-field-${field.key}`;
        const value = values[field.key] ?? '';
        return (
          <div key={field.key} className="space-y-1">
            <label htmlFor={fieldId} className="block text-sm font-medium text-theme-primary">
              {field.label}
              {field.required && <span className="text-theme-danger-fg"> *</span>}
            </label>
            {field.type === 'textarea' ? (
              <textarea
                id={fieldId}
                data-testid={fieldId}
                className="w-full rounded-md border border-theme bg-theme-surface px-3 py-2 text-sm text-theme-primary focus:border-theme-interactive-primary focus:outline-none"
                rows={3}
                value={value}
                placeholder={field.placeholder}
                disabled={disabled}
                onChange={(e) => handle(field.key, e.target.value)}
              />
            ) : (
              <input
                id={fieldId}
                data-testid={fieldId}
                type={field.type}
                className="w-full rounded-md border border-theme bg-theme-surface px-3 py-2 text-sm text-theme-primary focus:border-theme-interactive-primary focus:outline-none"
                value={value}
                placeholder={field.placeholder}
                disabled={disabled}
                autoComplete={field.type === 'password' ? 'new-password' : 'off'}
                onChange={(e) => handle(field.key, e.target.value)}
              />
            )}
            {field.helper && <p className="text-xs text-theme-secondary">{field.helper}</p>}
          </div>
        );
      })}
    </div>
  );
};

export default SchemaStepForm;

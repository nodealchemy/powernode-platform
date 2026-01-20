import { useState, useMemo } from 'react';
import type { IntegrationTemplate } from '../../types';

interface ConfigurationStepProps {
  template: IntegrationTemplate;
  initialName: string;
  initialConfiguration: Record<string, unknown>;
  onSave: (name: string, configuration: Record<string, unknown>) => void;
  onBack: () => void;
}

interface SchemaProperty {
  type: string;
  title?: string;
  description?: string;
  default?: unknown;
  enum?: string[];
  minimum?: number;
  maximum?: number;
  required?: boolean;
}

interface ConfigSchema {
  type: string;
  properties?: Record<string, SchemaProperty>;
  required?: string[];
}

export function ConfigurationStep({
  template,
  initialName,
  initialConfiguration,
  onSave,
  onBack,
}: ConfigurationStepProps) {
  const [name, setName] = useState(initialName);
  const [configuration, setConfiguration] = useState<Record<string, unknown>>(
    initialConfiguration
  );
  const [errors, setErrors] = useState<Record<string, string>>({});

  const schema = template.configuration_schema as unknown as ConfigSchema;
  const properties = schema?.properties || {};
  const requiredFields = schema?.required || [];

  const sortedProperties = useMemo(() => {
    return Object.entries(properties).sort(([, a], [, b]) => {
      const aRequired = requiredFields.includes(a.title || '');
      const bRequired = requiredFields.includes(b.title || '');
      if (aRequired && !bRequired) return -1;
      if (!aRequired && bRequired) return 1;
      return 0;
    });
  }, [properties, requiredFields]);

  const handleFieldChange = (key: string, value: unknown) => {
    setConfiguration((prev) => ({
      ...prev,
      [key]: value,
    }));
    // Clear error when field is modified
    if (errors[key]) {
      setErrors((prev) => {
        const newErrors = { ...prev };
        delete newErrors[key];
        return newErrors;
      });
    }
  };

  const validateForm = (): boolean => {
    const newErrors: Record<string, string> = {};

    if (!name.trim()) {
      newErrors.name = 'Name is required';
    }

    requiredFields.forEach((field) => {
      const value = configuration[field];
      if (value === undefined || value === null || value === '') {
        newErrors[field] = `${properties[field]?.title || field} is required`;
      }
    });

    setErrors(newErrors);
    return Object.keys(newErrors).length === 0;
  };

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (validateForm()) {
      onSave(name.trim(), configuration);
    }
  };

  const renderField = (key: string, property: SchemaProperty) => {
    const isRequired = requiredFields.includes(key);
    const value = configuration[key] ?? property.default ?? '';
    const error = errors[key];

    const label = (
      <label className="block text-sm font-medium text-theme-primary mb-1">
        {property.title || key}
        {isRequired && <span className="text-theme-error ml-1">*</span>}
      </label>
    );

    const helpText = property.description && (
      <p className="text-xs text-theme-tertiary mt-1">{property.description}</p>
    );

    const errorText = error && (
      <p className="text-xs text-theme-error mt-1">{error}</p>
    );

    const inputClasses = `w-full px-4 py-2 bg-theme-surface border rounded-lg text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary ${
      error ? 'border-theme-error' : 'border-theme'
    }`;

    switch (property.type) {
      case 'string':
        if (property.enum) {
          return (
            <div key={key}>
              {label}
              <select
                value={String(value)}
                onChange={(e) => handleFieldChange(key, e.target.value)}
                className={inputClasses}
              >
                <option value="">Select...</option>
                {property.enum.map((option) => (
                  <option key={option} value={option}>
                    {option}
                  </option>
                ))}
              </select>
              {helpText}
              {errorText}
            </div>
          );
        }
        return (
          <div key={key}>
            {label}
            <input
              type="text"
              value={String(value)}
              onChange={(e) => handleFieldChange(key, e.target.value)}
              className={inputClasses}
            />
            {helpText}
            {errorText}
          </div>
        );

      case 'number':
      case 'integer':
        return (
          <div key={key}>
            {label}
            <input
              type="number"
              value={value !== '' ? Number(value) : ''}
              onChange={(e) =>
                handleFieldChange(
                  key,
                  e.target.value ? Number(e.target.value) : ''
                )
              }
              min={property.minimum}
              max={property.maximum}
              className={inputClasses}
            />
            {helpText}
            {errorText}
          </div>
        );

      case 'boolean':
        return (
          <div key={key} className="flex items-start gap-3">
            <input
              type="checkbox"
              id={key}
              checked={Boolean(value)}
              onChange={(e) => handleFieldChange(key, e.target.checked)}
              className="mt-1 text-theme-primary focus:ring-theme-primary rounded"
            />
            <div>
              <label
                htmlFor={key}
                className="text-sm font-medium text-theme-primary cursor-pointer"
              >
                {property.title || key}
              </label>
              {property.description && (
                <p className="text-xs text-theme-tertiary">{property.description}</p>
              )}
            </div>
          </div>
        );

      case 'array':
        return (
          <div key={key}>
            {label}
            <textarea
              value={Array.isArray(value) ? value.join('\n') : String(value)}
              onChange={(e) =>
                handleFieldChange(
                  key,
                  e.target.value.split('\n').filter((v) => v.trim())
                )
              }
              placeholder="One item per line"
              rows={3}
              className={inputClasses}
            />
            {helpText}
            {errorText}
          </div>
        );

      case 'object':
        return (
          <div key={key}>
            {label}
            <textarea
              value={typeof value === 'object' ? JSON.stringify(value, null, 2) : String(value)}
              onChange={(e) => {
                try {
                  handleFieldChange(key, JSON.parse(e.target.value));
                } catch {
                  // Keep raw value if not valid JSON
                }
              }}
              placeholder="{}"
              rows={4}
              className={`${inputClasses} font-mono text-sm`}
            />
            {helpText}
            {errorText}
          </div>
        );

      default:
        return (
          <div key={key}>
            {label}
            <input
              type="text"
              value={String(value)}
              onChange={(e) => handleFieldChange(key, e.target.value)}
              className={inputClasses}
            />
            {helpText}
            {errorText}
          </div>
        );
    }
  };

  return (
    <form onSubmit={handleSubmit} className="space-y-6">
      <div>
        <h2 className="text-lg font-semibold text-theme-primary">Configure Integration</h2>
        <p className="text-sm text-theme-secondary mt-1">
          Customize your integration settings
        </p>
      </div>

      {/* Instance Name */}
      <div>
        <label className="block text-sm font-medium text-theme-primary mb-1">
          Integration Name
          <span className="text-theme-error ml-1">*</span>
        </label>
        <input
          type="text"
          value={name}
          onChange={(e) => {
            setName(e.target.value);
            if (errors.name) {
              setErrors((prev) => {
                const newErrors = { ...prev };
                delete newErrors.name;
                return newErrors;
              });
            }
          }}
          placeholder="My Integration"
          className={`w-full px-4 py-2 bg-theme-surface border rounded-lg text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary ${
            errors.name ? 'border-theme-error' : 'border-theme'
          }`}
        />
        <p className="text-xs text-theme-tertiary mt-1">
          A friendly name to identify this integration
        </p>
        {errors.name && (
          <p className="text-xs text-theme-error mt-1">{errors.name}</p>
        )}
      </div>

      {/* Configuration Fields */}
      {sortedProperties.length > 0 && (
        <div className="space-y-4 pt-4 border-t border-theme">
          <h3 className="text-sm font-medium text-theme-secondary">
            Template Configuration
          </h3>
          {sortedProperties.map(([key, property]) => renderField(key, property))}
        </div>
      )}

      {/* Actions */}
      <div className="flex justify-between pt-4 border-t border-theme">
        <button
          type="button"
          onClick={onBack}
          className="px-4 py-2 text-theme-secondary hover:text-theme-primary transition-colors"
        >
          Back
        </button>
        <button
          type="submit"
          className="btn-theme btn-theme-primary btn-theme-md"
        >
          Next
        </button>
      </div>
    </form>
  );
}

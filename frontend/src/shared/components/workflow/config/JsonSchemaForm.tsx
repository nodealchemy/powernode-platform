import React, { useCallback } from 'react';
import { Input } from '@/shared/components/ui/Input';
import { Textarea } from '@/shared/components/ui/Textarea';
import { EnhancedSelect } from '@/shared/components/ui/EnhancedSelect';
import { Variable } from 'lucide-react';
import type { WorkflowVariable } from '@/shared/hooks/useWorkflowVariables';
import { ArrayOfObjectsField } from './schema-fields/ArrayOfObjectsField';
import { AdditionalPropertiesField } from './schema-fields/AdditionalPropertiesField';
import { VariableAutocomplete } from './schema-fields/VariableAutocomplete';

export interface JsonSchemaProperty {
  type: 'string' | 'number' | 'integer' | 'boolean' | 'array' | 'object';
  title?: string;
  description?: string;
  default?: unknown;
  enum?: (string | number)[];
  format?: string;
  minimum?: number;
  maximum?: number;
  minLength?: number;
  maxLength?: number;
  minItems?: number;
  maxItems?: number;
  pattern?: string;
  items?: JsonSchemaProperty;
  properties?: Record<string, JsonSchemaProperty>;
  additionalProperties?: boolean | JsonSchemaProperty;
  required?: string[];
}

export interface JsonSchema {
  type: 'object';
  title?: string;
  description?: string;
  properties?: Record<string, JsonSchemaProperty>;
  required?: string[];
}

interface JsonSchemaFormProps {
  schema: JsonSchema | Record<string, unknown>;
  values: Record<string, unknown>;
  onChange: (values: Record<string, unknown>) => void;
  workflowVariables?: WorkflowVariable[];
  onInsertVariable?: (parameterName: string, variable: WorkflowVariable) => void;
  errors?: Record<string, string>;
  disabled?: boolean;
}

/**
 * Renders a form dynamically from a JSON Schema definition.
 * Supports variable mapping for workflow parameters.
 */
export const JsonSchemaForm: React.FC<JsonSchemaFormProps> = ({
  schema,
  values,
  onChange,
  workflowVariables = [],
  onInsertVariable,
  errors = {},
  disabled = false,
}) => {
  const normalizedSchema = normalizeSchema(schema);

  const handleValueChange = useCallback((key: string, value: unknown) => {
    onChange({
      ...values,
      [key]: value,
    });
  }, [values, onChange]);

  if (!normalizedSchema.properties || Object.keys(normalizedSchema.properties).length === 0) {
    return (
      <div className="text-center py-4 text-theme-muted text-sm">
        No parameters required for this tool.
      </div>
    );
  }

  const properties = normalizedSchema.properties;
  const requiredFields = normalizedSchema.required || [];

  return (
    <div className="space-y-4">
      {Object.entries(properties).map(([key, prop]) => (
        <SchemaField
          key={key}
          name={key}
          property={prop}
          value={values[key]}
          onChange={(value) => handleValueChange(key, value)}
          required={requiredFields.includes(key)}
          error={errors[key]}
          disabled={disabled}
          workflowVariables={workflowVariables}
          onInsertVariable={onInsertVariable ? (variable) => onInsertVariable(key, variable) : undefined}
        />
      ))}
    </div>
  );
};

interface SchemaFieldProps {
  name: string;
  property: JsonSchemaProperty;
  value: unknown;
  onChange: (value: unknown) => void;
  required?: boolean;
  error?: string;
  disabled?: boolean;
  workflowVariables?: WorkflowVariable[];
  onInsertVariable?: (variable: WorkflowVariable) => void;
}

const SchemaField: React.FC<SchemaFieldProps> = ({
  name,
  property,
  value,
  onChange,
  required = false,
  error,
  disabled = false,
  workflowVariables = [],
  onInsertVariable,
}) => {
  const label = property.title || formatFieldName(name);
  const description = property.description;

  // Render variable selector button
  const variableButton = workflowVariables.length > 0 && onInsertVariable ? (
    <VariableSelector
      variables={workflowVariables}
      onSelect={onInsertVariable}
    />
  ) : null;

  // Render based on type and format
  if (property.enum && property.enum.length > 0) {
    return (
      <div>
        <EnhancedSelect
          label={label}
          value={String(value ?? property.default ?? '')}
          onChange={(val) => onChange(val)}
          options={property.enum.map((opt) => ({
            value: String(opt),
            label: String(opt),
          }))}
          disabled={disabled}
          error={error}
        />
        {description && <p className="text-xs text-theme-muted mt-1">{description}</p>}
      </div>
    );
  }

  switch (property.type) {
    case 'boolean':
      return (
        <div className="flex items-start gap-3 p-3 rounded-lg border border-theme-border bg-theme-surface">
          <input
            type="checkbox"
            checked={Boolean(value ?? property.default)}
            onChange={(e) => onChange(e.target.checked)}
            disabled={disabled}
            className="mt-0.5 rounded border-theme-border"
          />
          <div className="flex-1">
            <label className="text-sm font-medium text-theme-primary">
              {label}
              {required && <span className="text-theme-error ml-1">*</span>}
            </label>
            {description && (
              <p className="text-xs text-theme-muted mt-1">{description}</p>
            )}
            {error && <p className="text-xs text-theme-error mt-1">{error}</p>}
          </div>
        </div>
      );

    case 'number':
    case 'integer':
      return (
        <div>
          <div className="flex items-center gap-2">
            <div className="flex-1">
              <Input
                label={label}
                type="number"
                value={value !== undefined ? String(value) : String(property.default ?? '')}
                onChange={(e) => {
                  const val = property.type === 'integer'
                    ? parseInt(e.target.value, 10)
                    : parseFloat(e.target.value);
                  onChange(isNaN(val) ? undefined : val);
                }}
                min={property.minimum}
                max={property.maximum}
                step={property.type === 'integer' ? 1 : 0.1}
                disabled={disabled}
                error={error}
                required={required}
              />
            </div>
            {variableButton}
          </div>
          {description && <p className="text-xs text-theme-muted mt-1">{description}</p>}
        </div>
      );

    case 'array':
      return (
        <ArrayField
          name={name}
          property={property}
          value={value as unknown[] | undefined}
          onChange={onChange}
          required={required}
          error={error}
          disabled={disabled}
          workflowVariables={workflowVariables}
          onInsertVariable={onInsertVariable}
        />
      );

    case 'object':
      return (
        <ObjectField
          name={name}
          property={property}
          value={value as Record<string, unknown> | undefined}
          onChange={onChange}
          required={required}
          error={error}
          disabled={disabled}
          workflowVariables={workflowVariables}
        />
      );

    case 'string':
    default:
      // Check if multiline based on format or if content looks like text
      const isMultiline = property.format === 'textarea' ||
                         (property.maxLength && property.maxLength > 200);

      // Use VariableAutocomplete when workflow variables are available
      const hasVariables = workflowVariables && workflowVariables.length > 0;

      if (isMultiline) {
        return (
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">
              {label}
              {required && <span className="text-theme-error ml-1">*</span>}
            </label>
            {hasVariables ? (
              <VariableAutocomplete
                value={String(value ?? property.default ?? '')}
                onChange={(val) => onChange(val)}
                variables={workflowVariables}
                disabled={disabled}
                multiline
                rows={4}
                placeholder={`Enter ${label.toLowerCase()} or type {{ for variables`}
              />
            ) : (
              <div className="flex items-start gap-2">
                <div className="flex-1">
                  <Textarea
                    value={String(value ?? property.default ?? '')}
                    onChange={(e) => onChange(e.target.value)}
                    rows={4}
                    disabled={disabled}
                    error={error}
                    required={required}
                    placeholder={`Enter ${label.toLowerCase()}`}
                  />
                </div>
              </div>
            )}
            {error && <p className="text-xs text-theme-error mt-1">{error}</p>}
            {description && <p className="text-xs text-theme-muted mt-1">{description}</p>}
          </div>
        );
      }

      return (
        <div>
          <label className="block text-sm font-medium text-theme-primary mb-1">
            {label}
            {required && <span className="text-theme-error ml-1">*</span>}
          </label>
          {hasVariables ? (
            <VariableAutocomplete
              value={String(value ?? property.default ?? '')}
              onChange={(val) => onChange(val)}
              variables={workflowVariables}
              disabled={disabled}
              placeholder={`Enter ${label.toLowerCase()} or type {{ for variables`}
            />
          ) : (
            <div className="flex items-center gap-2">
              <div className="flex-1">
                <Input
                  value={String(value ?? property.default ?? '')}
                  onChange={(e) => onChange(e.target.value)}
                  disabled={disabled}
                  error={error}
                  required={required}
                  placeholder={`Enter ${label.toLowerCase()}`}
                />
              </div>
            </div>
          )}
          {error && <p className="text-xs text-theme-error mt-1">{error}</p>}
          {description && <p className="text-xs text-theme-muted mt-1">{description}</p>}
        </div>
      );
  }
};

interface ArrayFieldProps {
  name: string;
  property: JsonSchemaProperty;
  value: unknown[] | undefined;
  onChange: (value: unknown[]) => void;
  required?: boolean;
  error?: string;
  disabled?: boolean;
  workflowVariables?: WorkflowVariable[];
  onInsertVariable?: (variable: WorkflowVariable) => void;
}

const ArrayField: React.FC<ArrayFieldProps> = ({
  name,
  property,
  value = [],
  onChange,
  required = false,
  error,
  disabled = false,
  workflowVariables = [],
  onInsertVariable,
}) => {
  const label = property.title || formatFieldName(name);
  const itemSchema = property.items;

  // Check if this is an array of objects
  const isArrayOfObjects = itemSchema?.type === 'object' && itemSchema.properties;

  if (isArrayOfObjects) {
    // Use enhanced ArrayOfObjectsField for object arrays
    return (
      <ArrayOfObjectsField
        name={name}
        property={property}
        value={value as Record<string, unknown>[]}
        onChange={onChange as (value: Record<string, unknown>[]) => void}
        required={required}
        error={error}
        disabled={disabled}
        workflowVariables={workflowVariables}
        onInsertVariable={onInsertVariable}
        renderItemForm={(item, _index, onItemChange, schema) => (
          <JsonSchemaForm
            schema={{ type: 'object', properties: schema.properties, required: schema.required }}
            values={item}
            onChange={onItemChange}
            workflowVariables={workflowVariables}
            disabled={disabled}
          />
        )}
      />
    );
  }

  // Simple string/primitive array handling
  const handleArrayChange = (text: string) => {
    const items = text.split(',').map(s => s.trim()).filter(s => s);
    onChange(items);
  };

  return (
    <div>
      <Input
        label={label}
        value={Array.isArray(value) ? value.join(', ') : ''}
        onChange={(e) => handleArrayChange(e.target.value)}
        placeholder="item1, item2, item3 (comma-separated)"
        disabled={disabled}
        error={error}
        required={required}
      />
      {property.description && (
        <p className="text-xs text-theme-muted mt-1">{property.description}</p>
      )}
    </div>
  );
};

interface ObjectFieldProps {
  name: string;
  property: JsonSchemaProperty;
  value: Record<string, unknown> | undefined;
  onChange: (value: Record<string, unknown>) => void;
  required?: boolean;
  error?: string;
  disabled?: boolean;
  workflowVariables?: WorkflowVariable[];
}

const ObjectField: React.FC<ObjectFieldProps> = ({
  name,
  property,
  value = {},
  onChange,
  required = false,
  error,
  disabled = false,
  workflowVariables = [],
}) => {
  const label = property.title || formatFieldName(name);

  // Check if this is an additionalProperties object (dynamic key-value pairs)
  const hasAdditionalProperties = property.additionalProperties !== undefined &&
    property.additionalProperties !== false &&
    !property.properties;

  if (hasAdditionalProperties) {
    return (
      <AdditionalPropertiesField
        name={name}
        property={property}
        value={value}
        onChange={onChange}
        required={required}
        error={error}
        disabled={disabled}
        workflowVariables={workflowVariables}
      />
    );
  }

  // If nested properties defined, render them
  if (property.properties) {
    return (
      <div className="border border-theme rounded-lg p-3">
        <label className="block text-sm font-medium text-theme-primary mb-3">
          {label}
          {required && <span className="text-theme-error ml-1">*</span>}
        </label>
        <JsonSchemaForm
          schema={{ type: 'object', properties: property.properties, required: property.required }}
          values={value}
          onChange={onChange}
          workflowVariables={workflowVariables}
          disabled={disabled}
        />
        {property.description && (
          <p className="text-xs text-theme-muted mt-2">{property.description}</p>
        )}
        {error && <p className="text-xs text-theme-error mt-1">{error}</p>}
      </div>
    );
  }

  // Otherwise, render as JSON
  return (
    <div>
      <Textarea
        label={label}
        value={JSON.stringify(value, null, 2)}
        onChange={(e) => {
          try {
            onChange(JSON.parse(e.target.value));
          } catch {
            // Invalid JSON, don't update
          }
        }}
        rows={4}
        className="font-mono text-sm"
        disabled={disabled}
        error={error}
        required={required}
        placeholder="{}"
      />
      {property.description && (
        <p className="text-xs text-theme-muted mt-1">{property.description}</p>
      )}
    </div>
  );
};

interface VariableSelectorProps {
  variables: WorkflowVariable[];
  onSelect: (variable: WorkflowVariable) => void;
}

const VariableSelector: React.FC<VariableSelectorProps> = ({ variables, onSelect }) => {
  const [isOpen, setIsOpen] = React.useState(false);

  if (variables.length === 0) return null;

  return (
    <div className="relative">
      <button
        type="button"
        onClick={() => setIsOpen(!isOpen)}
        className="p-2 rounded-lg border border-theme hover:bg-theme-surface-hover text-theme-muted hover:text-theme-primary transition-colors"
        title="Insert workflow variable"
      >
        <Variable className="h-4 w-4" />
      </button>

      {isOpen && (
        <>
          <div
            className="fixed inset-0 z-40"
            onClick={() => setIsOpen(false)}
          />
          <div className="absolute right-0 top-full mt-1 w-64 max-h-48 overflow-y-auto bg-theme-surface border border-theme rounded-lg shadow-lg z-50">
            {variables.map((variable) => (
              <button
                key={variable.path}
                type="button"
                onClick={() => {
                  onSelect(variable);
                  setIsOpen(false);
                }}
                className="w-full text-left px-3 py-2 hover:bg-theme-surface-hover transition-colors"
              >
                <div className="text-sm font-medium text-theme-primary">
                  {variable.name}
                </div>
                <div className="text-xs text-theme-muted font-mono">
                  {`{{${variable.path}}}`}
                </div>
              </button>
            ))}
          </div>
        </>
      )}
    </div>
  );
};

// Helper functions

function formatFieldName(name: string): string {
  return name
    .replace(/_/g, ' ')
    .replace(/([A-Z])/g, ' $1')
    .replace(/^./, (str) => str.toUpperCase())
    .trim();
}

function normalizeSchema(schema: JsonSchema | Record<string, unknown>): JsonSchema {
  // If it's already a proper schema
  if (schema && typeof schema === 'object' && 'properties' in schema) {
    return schema as JsonSchema;
  }

  // If it's just a properties object, wrap it
  if (schema && typeof schema === 'object') {
    return {
      type: 'object',
      properties: schema as Record<string, JsonSchemaProperty>,
    };
  }

  return { type: 'object', properties: {} };
}

export default JsonSchemaForm;

import React, { useCallback, useState } from 'react';
import { Plus, Trash2, AlertCircle } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { Input } from '@/shared/components/ui/Input';
import type { JsonSchemaProperty } from '../JsonSchemaForm';
import type { WorkflowVariable } from '@/shared/hooks/useWorkflowVariables';

interface AdditionalPropertiesFieldProps {
  name: string;
  property: JsonSchemaProperty;
  value: Record<string, unknown> | undefined;
  onChange: (value: Record<string, unknown>) => void;
  required?: boolean;
  error?: string;
  disabled?: boolean;
  workflowVariables?: WorkflowVariable[];
  onInsertVariable?: (key: string, variable: WorkflowVariable) => void;
}

interface KeyValuePair {
  id: string;
  key: string;
  value: string;
  keyError?: string;
}

/**
 * Renders a dynamic key-value editor for objects with additionalProperties.
 * Allows adding/removing arbitrary key-value pairs.
 */
export const AdditionalPropertiesField: React.FC<AdditionalPropertiesFieldProps> = ({
  name,
  property,
  value = {},
  onChange,
  required = false,
  error,
  disabled = false,
}) => {
  const label = property.title || formatFieldName(name);

  // Track pairs with unique IDs for stable rendering
  const [pairs, setPairs] = useState<KeyValuePair[]>(() =>
    Object.entries(value).map(([key, val], index) => ({
      id: `pair-${index}-${Date.now()}`,
      key,
      value: String(val ?? ''),
    }))
  );

  // Validate key uniqueness and format
  const validateKey = useCallback((key: string, currentId: string): string | undefined => {
    if (!key.trim()) {
      return 'Key is required';
    }

    // Check for duplicate keys
    const duplicates = pairs.filter(p => p.id !== currentId && p.key === key.trim());
    if (duplicates.length > 0) {
      return 'Duplicate key';
    }

    // Validate key format (alphanumeric, underscores, hyphens)
    if (!/^[a-zA-Z_][a-zA-Z0-9_-]*$/.test(key.trim())) {
      return 'Invalid key format';
    }

    return undefined;
  }, [pairs]);

  // Sync pairs to parent value
  const syncToParent = useCallback((newPairs: KeyValuePair[]) => {
    const newValue: Record<string, unknown> = {};

    for (const pair of newPairs) {
      if (pair.key.trim() && !pair.keyError) {
        // Try to parse as JSON, fall back to string
        let parsedValue: unknown = pair.value;
        if (pair.value.trim()) {
          try {
            parsedValue = JSON.parse(pair.value);
          } catch (_error) {
            // Keep as string if not valid JSON
          }
        }
        newValue[pair.key.trim()] = parsedValue;
      }
    }

    onChange(newValue);
  }, [onChange]);

  const handleAddPair = useCallback(() => {
    const newPair: KeyValuePair = {
      id: `pair-${Date.now()}`,
      key: '',
      value: '',
    };
    const newPairs = [...pairs, newPair];
    setPairs(newPairs);
  }, [pairs]);

  const handleRemovePair = useCallback((id: string) => {
    const newPairs = pairs.filter(p => p.id !== id);
    setPairs(newPairs);
    syncToParent(newPairs);
  }, [pairs, syncToParent]);

  const handleKeyChange = useCallback((id: string, newKey: string) => {
    const newPairs = pairs.map(p => {
      if (p.id === id) {
        return {
          ...p,
          key: newKey,
          keyError: validateKey(newKey, id),
        };
      }
      return p;
    });
    setPairs(newPairs);
    syncToParent(newPairs);
  }, [pairs, validateKey, syncToParent]);

  const handleValueChange = useCallback((id: string, newValue: string) => {
    const newPairs = pairs.map(p => {
      if (p.id === id) {
        return { ...p, value: newValue };
      }
      return p;
    });
    setPairs(newPairs);
    syncToParent(newPairs);
  }, [pairs, syncToParent]);

  const hasErrors = pairs.some(p => p.keyError);

  return (
    <div className="border border-theme rounded-lg overflow-hidden">
      {/* Header */}
      <div className="flex items-center justify-between px-4 py-3 bg-theme-surface border-b border-theme">
        <div>
          <label className="text-sm font-medium text-theme-primary">
            {label}
            {required && <span className="text-theme-error ml-1">*</span>}
          </label>
          <span className="text-xs text-theme-tertiary ml-2">
            ({pairs.length} {pairs.length === 1 ? 'property' : 'properties'})
          </span>
        </div>
        <Button
          type="button"
          variant="ghost"
          size="sm"
          onClick={handleAddPair}
          disabled={disabled}
          className="text-theme-info"
        >
          <Plus className="h-4 w-4 mr-1" />
          Add Property
        </Button>
      </div>

      {/* Description */}
      {property.description && (
        <div className="px-4 py-2 bg-theme-hover border-b border-theme">
          <p className="text-xs text-theme-secondary">{property.description}</p>
        </div>
      )}

      {/* Key-Value Pairs */}
      <div className="divide-y divide-theme">
        {pairs.length === 0 ? (
          <div className="p-4 text-center text-sm text-theme-tertiary">
            No properties defined. Click "Add Property" to add a key-value pair.
          </div>
        ) : (
          pairs.map((pair) => (
            <div
              key={pair.id}
              className="flex items-start gap-3 p-3 bg-theme-surface hover:bg-theme-hover transition-colors"
            >
              {/* Key Input */}
              <div className="flex-1">
                <div className="relative">
                  <Input
                    value={pair.key}
                    onChange={(e) => handleKeyChange(pair.id, e.target.value)}
                    placeholder="property_name"
                    disabled={disabled}
                    className={`font-mono text-sm ${pair.keyError ? 'border-theme-error' : ''}`}
                  />
                  {pair.keyError && (
                    <div className="absolute right-2 top-1/2 -translate-y-1/2">
                      <AlertCircle className="h-4 w-4 text-theme-error" />
                    </div>
                  )}
                </div>
                {pair.keyError && (
                  <p className="text-xs text-theme-error mt-1">{pair.keyError}</p>
                )}
              </div>

              {/* Equals Sign */}
              <span className="text-theme-tertiary self-center pt-2">:</span>

              {/* Value Input */}
              <div className="flex-[2]">
                <Input
                  value={pair.value}
                  onChange={(e) => handleValueChange(pair.id, e.target.value)}
                  placeholder="value (string, number, or JSON)"
                  disabled={disabled}
                  className="font-mono text-sm"
                />
                <p className="text-xs text-theme-tertiary mt-1">
                  Use quotes for strings: "text", or use {"{{"}variable{"}}"}
                </p>
              </div>

              {/* Delete Button */}
              <Button
                type="button"
                variant="ghost"
                size="sm"
                onClick={() => handleRemovePair(pair.id)}
                disabled={disabled}
                className="text-theme-error hover:bg-theme-error/10 self-center"
              >
                <Trash2 className="h-4 w-4" />
              </Button>
            </div>
          ))
        )}
      </div>

      {/* Error */}
      {(error || hasErrors) && (
        <div className="px-4 py-2 bg-theme-error/10 border-t border-theme-error">
          <p className="text-xs text-theme-error">
            {error || 'Please fix the key errors above'}
          </p>
        </div>
      )}

      {/* Help Text */}
      <div className="px-4 py-2 bg-theme-hover border-t border-theme">
        <p className="text-xs text-theme-tertiary">
          Keys must start with a letter or underscore and contain only alphanumeric characters, underscores, and hyphens.
        </p>
      </div>
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

export default AdditionalPropertiesField;

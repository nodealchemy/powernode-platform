import React, { useCallback } from 'react';
import { Plus, Trash2, GripVertical, ChevronDown, ChevronRight } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import type { JsonSchemaProperty } from '../JsonSchemaForm';
import type { WorkflowVariable } from '@/shared/hooks/useWorkflowVariables';
import { SortableArrayItem } from './SortableArrayItem';

interface ArrayOfObjectsFieldProps {
  name: string;
  property: JsonSchemaProperty;
  value: Record<string, unknown>[] | undefined;
  onChange: (value: Record<string, unknown>[]) => void;
  required?: boolean;
  error?: string;
  disabled?: boolean;
  workflowVariables?: WorkflowVariable[];
  onInsertVariable?: (variable: WorkflowVariable) => void;
  renderItemForm: (
    item: Record<string, unknown>,
    index: number,
    onItemChange: (value: Record<string, unknown>) => void,
    itemSchema: JsonSchemaProperty
  ) => React.ReactNode;
}

/**
 * Renders an array of objects with add/remove/reorder functionality.
 * Each item can be expanded/collapsed and supports drag-and-drop reordering.
 */
export const ArrayOfObjectsField: React.FC<ArrayOfObjectsFieldProps> = ({
  name,
  property,
  value = [],
  onChange,
  required = false,
  error,
  disabled = false,
  renderItemForm,
}) => {
  const label = property.title || formatFieldName(name);
  const itemSchema = property.items || { type: 'object', properties: {} };
  const minItems = property.minItems ?? 0;
  const maxItems = property.maxItems ?? Infinity;

  const [expandedItems, setExpandedItems] = React.useState<Set<number>>(
    new Set(value.map((_, i) => i))
  );

  const handleAddItem = useCallback(() => {
    if (value.length >= maxItems) return;

    // Create new item with defaults from schema
    const newItem = createDefaultItem(itemSchema);
    const newValue = [...value, newItem];
    onChange(newValue);

    // Auto-expand new item
    setExpandedItems(prev => new Set([...prev, newValue.length - 1]));
  }, [value, onChange, maxItems, itemSchema]);

  const handleRemoveItem = useCallback((index: number) => {
    if (value.length <= minItems) return;

    const newValue = value.filter((_, i) => i !== index);
    onChange(newValue);

    // Update expanded items indices
    setExpandedItems(prev => {
      const newSet = new Set<number>();
      prev.forEach(i => {
        if (i < index) newSet.add(i);
        else if (i > index) newSet.add(i - 1);
      });
      return newSet;
    });
  }, [value, onChange, minItems]);

  const handleItemChange = useCallback((index: number, newItemValue: Record<string, unknown>) => {
    const newValue = [...value];
    newValue[index] = newItemValue;
    onChange(newValue);
  }, [value, onChange]);

  const handleReorder = useCallback((fromIndex: number, toIndex: number) => {
    if (fromIndex === toIndex) return;

    const newValue = [...value];
    const [removed] = newValue.splice(fromIndex, 1);
    newValue.splice(toIndex, 0, removed);
    onChange(newValue);

    // Update expanded items
    setExpandedItems(prev => {
      const newSet = new Set<number>();
      prev.forEach(i => {
        if (i === fromIndex) {
          newSet.add(toIndex);
        } else if (fromIndex < toIndex) {
          // Moving down
          if (i > fromIndex && i <= toIndex) newSet.add(i - 1);
          else newSet.add(i);
        } else {
          // Moving up
          if (i >= toIndex && i < fromIndex) newSet.add(i + 1);
          else newSet.add(i);
        }
      });
      return newSet;
    });
  }, [value, onChange]);

  const toggleExpanded = useCallback((index: number) => {
    setExpandedItems(prev => {
      const newSet = new Set(prev);
      if (newSet.has(index)) {
        newSet.delete(index);
      } else {
        newSet.add(index);
      }
      return newSet;
    });
  }, []);

  const getItemTitle = (item: Record<string, unknown>, index: number): string => {
    // Try to find a title-like field
    const titleFields = ['name', 'title', 'label', 'id', 'key'];
    for (const field of titleFields) {
      if (item[field] && typeof item[field] === 'string') {
        return item[field] as string;
      }
    }
    return `Item ${index + 1}`;
  };

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
            ({value.length} item{value.length !== 1 ? 's' : ''})
          </span>
        </div>
        <Button
          type="button"
          variant="ghost"
          size="sm"
          onClick={handleAddItem}
          disabled={disabled || value.length >= maxItems}
          className="text-theme-info"
        >
          <Plus className="h-4 w-4 mr-1" />
          Add
        </Button>
      </div>

      {/* Description */}
      {property.description && (
        <div className="px-4 py-2 bg-theme-hover border-b border-theme">
          <p className="text-xs text-theme-secondary">{property.description}</p>
        </div>
      )}

      {/* Items */}
      <div className="divide-y divide-theme">
        {value.length === 0 ? (
          <div className="p-4 text-center text-sm text-theme-tertiary">
            No items. Click "Add" to add an item.
          </div>
        ) : (
          value.map((item, index) => (
            <SortableArrayItem
              key={index}
              index={index}
              totalItems={value.length}
              onMoveUp={index > 0 ? () => handleReorder(index, index - 1) : undefined}
              onMoveDown={index < value.length - 1 ? () => handleReorder(index, index + 1) : undefined}
              disabled={disabled}
            >
              <div className="bg-theme-surface">
                {/* Item Header */}
                <div
                  className="flex items-center gap-2 px-4 py-2 cursor-pointer hover:bg-theme-hover"
                  onClick={() => toggleExpanded(index)}
                >
                  <GripVertical className="h-4 w-4 text-theme-tertiary flex-shrink-0" />
                  <button
                    type="button"
                    className="p-0.5 text-theme-secondary"
                    onClick={(e) => {
                      e.stopPropagation();
                      toggleExpanded(index);
                    }}
                  >
                    {expandedItems.has(index) ? (
                      <ChevronDown className="h-4 w-4" />
                    ) : (
                      <ChevronRight className="h-4 w-4" />
                    )}
                  </button>
                  <span className="flex-1 text-sm font-medium text-theme-primary truncate">
                    {getItemTitle(item, index)}
                  </span>
                  <Button
                    type="button"
                    variant="ghost"
                    size="sm"
                    onClick={(e) => {
                      e.stopPropagation();
                      handleRemoveItem(index);
                    }}
                    disabled={disabled || value.length <= minItems}
                    className="text-theme-error hover:bg-theme-error/10"
                  >
                    <Trash2 className="h-4 w-4" />
                  </Button>
                </div>

                {/* Item Content */}
                {expandedItems.has(index) && (
                  <div className="px-4 pb-4 pt-2 border-t border-theme/50">
                    {renderItemForm(
                      item,
                      index,
                      (newValue) => handleItemChange(index, newValue),
                      itemSchema
                    )}
                  </div>
                )}
              </div>
            </SortableArrayItem>
          ))
        )}
      </div>

      {/* Error */}
      {error && (
        <div className="px-4 py-2 bg-theme-error/10 border-t border-theme-error">
          <p className="text-xs text-theme-error">{error}</p>
        </div>
      )}

      {/* Footer with constraints */}
      {(minItems > 0 || maxItems < Infinity) && (
        <div className="px-4 py-2 bg-theme-hover border-t border-theme">
          <p className="text-xs text-theme-tertiary">
            {minItems > 0 && maxItems < Infinity
              ? `Between ${minItems} and ${maxItems} items required`
              : minItems > 0
              ? `At least ${minItems} item${minItems !== 1 ? 's' : ''} required`
              : `Maximum ${maxItems} items allowed`}
          </p>
        </div>
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

function createDefaultItem(itemSchema: JsonSchemaProperty): Record<string, unknown> {
  const item: Record<string, unknown> = {};

  if (itemSchema.properties) {
    for (const [key, prop] of Object.entries(itemSchema.properties)) {
      if (prop.default !== undefined) {
        item[key] = prop.default;
      } else {
        // Set sensible defaults based on type
        switch (prop.type) {
          case 'string':
            item[key] = '';
            break;
          case 'number':
          case 'integer':
            item[key] = prop.minimum ?? 0;
            break;
          case 'boolean':
            item[key] = false;
            break;
          case 'array':
            item[key] = [];
            break;
          case 'object':
            item[key] = {};
            break;
        }
      }
    }
  }

  return item;
}

export default ArrayOfObjectsField;

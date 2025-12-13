import React, { useRef, useState, useCallback, useEffect } from 'react';
import { Variable } from 'lucide-react';
import type { WorkflowVariable } from '@/shared/hooks/useWorkflowVariables';

interface VariableAutocompleteProps {
  value: string;
  onChange: (value: string) => void;
  onBlur?: () => void;
  variables: WorkflowVariable[];
  placeholder?: string;
  disabled?: boolean;
  multiline?: boolean;
  rows?: number;
  className?: string;
}

/**
 * An input/textarea component that provides inline autocomplete for workflow variables.
 * Triggered by typing '{{' and shows a dropdown of available variables.
 */
export const VariableAutocomplete: React.FC<VariableAutocompleteProps> = ({
  value,
  onChange,
  onBlur,
  variables,
  placeholder,
  disabled = false,
  multiline = false,
  rows = 3,
  className = '',
}) => {
  const inputRef = useRef<HTMLInputElement | HTMLTextAreaElement>(null);
  const dropdownRef = useRef<HTMLDivElement>(null);

  const [showDropdown, setShowDropdown] = useState(false);
  const [dropdownPosition, setDropdownPosition] = useState({ top: 0, left: 0 });
  const [searchTerm, setSearchTerm] = useState('');
  const [selectedIndex, setSelectedIndex] = useState(0);
  const [insertPosition, setInsertPosition] = useState<{ start: number; end: number } | null>(null);

  // Filter variables based on search term
  const filteredVariables = variables.filter(v => {
    const term = searchTerm.toLowerCase();
    return (
      v.name.toLowerCase().includes(term) ||
      v.path.toLowerCase().includes(term) ||
      v.type.toLowerCase().includes(term)
    );
  });

  // Calculate dropdown position based on input position
  const updateDropdownPosition = useCallback(() => {
    const input = inputRef.current;
    if (!input) return;

    // Position dropdown below the input
    setDropdownPosition({
      top: input.offsetHeight + 4,
      left: 0,
    });
  }, []);

  // Check for {{ trigger and show dropdown
  const handleInput = useCallback((e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) => {
    const newValue = e.target.value;
    const cursorPos = e.target.selectionStart ?? 0;

    onChange(newValue);

    // Check if we just typed '{{' or are inside a {{...}} block
    const textBeforeCursor = newValue.slice(0, cursorPos);
    const lastOpenBrace = textBeforeCursor.lastIndexOf('{{');
    const lastCloseBrace = textBeforeCursor.lastIndexOf('}}');

    if (lastOpenBrace > lastCloseBrace) {
      // We're inside an incomplete variable reference
      const searchStart = lastOpenBrace + 2;
      const currentSearch = textBeforeCursor.slice(searchStart);

      // Only show if not too much has been typed (avoid showing for long text)
      if (currentSearch.length <= 50 && !/[^a-zA-Z0-9._]/.test(currentSearch)) {
        setSearchTerm(currentSearch);
        setInsertPosition({ start: lastOpenBrace, end: cursorPos });
        setSelectedIndex(0);
        setShowDropdown(true);
        updateDropdownPosition();
        return;
      }
    }

    setShowDropdown(false);
    setInsertPosition(null);
  }, [onChange, updateDropdownPosition]);

  // Insert selected variable
  const insertVariable = useCallback((variable: WorkflowVariable) => {
    const input = inputRef.current;
    if (!input || !insertPosition) return;

    const before = value.slice(0, insertPosition.start);
    const after = value.slice(insertPosition.end);
    const variableText = `{{${variable.path}}}`;

    const newValue = before + variableText + after;
    onChange(newValue);

    // Move cursor after the inserted variable
    const newCursorPos = before.length + variableText.length;
    setTimeout(() => {
      input.focus();
      input.setSelectionRange(newCursorPos, newCursorPos);
    }, 0);

    setShowDropdown(false);
    setInsertPosition(null);
    setSearchTerm('');
  }, [value, onChange, insertPosition]);

  // Keyboard navigation
  const handleKeyDown = useCallback((e: React.KeyboardEvent) => {
    if (!showDropdown) return;

    switch (e.key) {
      case 'ArrowDown':
        e.preventDefault();
        setSelectedIndex(prev =>
          prev < filteredVariables.length - 1 ? prev + 1 : 0
        );
        break;
      case 'ArrowUp':
        e.preventDefault();
        setSelectedIndex(prev =>
          prev > 0 ? prev - 1 : filteredVariables.length - 1
        );
        break;
      case 'Enter':
      case 'Tab':
        if (filteredVariables.length > 0) {
          e.preventDefault();
          insertVariable(filteredVariables[selectedIndex]);
        }
        break;
      case 'Escape':
        e.preventDefault();
        setShowDropdown(false);
        setInsertPosition(null);
        break;
    }
  }, [showDropdown, filteredVariables, selectedIndex, insertVariable]);

  // Close dropdown on click outside
  useEffect(() => {
    const handleClickOutside = (e: MouseEvent) => {
      if (
        dropdownRef.current &&
        !dropdownRef.current.contains(e.target as Node) &&
        inputRef.current &&
        !inputRef.current.contains(e.target as Node)
      ) {
        setShowDropdown(false);
      }
    };

    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, []);

  // Scroll selected item into view
  useEffect(() => {
    if (showDropdown && dropdownRef.current) {
      const selectedElement = dropdownRef.current.children[selectedIndex] as HTMLElement;
      if (selectedElement) {
        selectedElement.scrollIntoView({ block: 'nearest' });
      }
    }
  }, [selectedIndex, showDropdown]);

  const inputClassName = `w-full px-3 py-2 border border-theme rounded-lg bg-theme-surface text-theme-primary
    placeholder:text-theme-tertiary focus:outline-none focus:ring-2 focus:ring-theme-info/30
    disabled:opacity-50 disabled:cursor-not-allowed ${className}`;

  const InputComponent = multiline ? 'textarea' : 'input';

  return (
    <div className="relative">
      <InputComponent
        ref={inputRef as React.RefObject<HTMLInputElement & HTMLTextAreaElement>}
        value={value}
        onChange={handleInput}
        onBlur={onBlur}
        onKeyDown={handleKeyDown}
        placeholder={placeholder || "Type {{ to insert a variable"}
        disabled={disabled}
        rows={multiline ? rows : undefined}
        className={inputClassName}
      />

      {/* Variable hint indicator */}
      {variables.length > 0 && !disabled && (
        <div className="absolute right-2 top-2 text-theme-tertiary">
          <Variable className="h-4 w-4" />
        </div>
      )}

      {/* Autocomplete dropdown */}
      {showDropdown && filteredVariables.length > 0 && (
        <div
          ref={dropdownRef}
          className="absolute z-50 w-full max-h-48 overflow-y-auto bg-theme-surface border border-theme rounded-lg shadow-lg"
          style={{
            top: dropdownPosition.top,
            left: dropdownPosition.left,
          }}
        >
          {filteredVariables.map((variable, index) => (
            <button
              key={variable.path}
              type="button"
              onClick={() => insertVariable(variable)}
              onMouseEnter={() => setSelectedIndex(index)}
              className={`w-full text-left px-3 py-2 transition-colors ${
                index === selectedIndex
                  ? 'bg-theme-info/10 text-theme-info'
                  : 'hover:bg-theme-hover'
              }`}
            >
              <div className="flex items-center gap-2">
                <Variable className="h-4 w-4 text-theme-tertiary flex-shrink-0" />
                <div className="flex-1 min-w-0">
                  <div className="text-sm font-medium text-theme-primary truncate">
                    {variable.name}
                  </div>
                  <div className="text-xs text-theme-tertiary font-mono truncate">
                    {`{{${variable.path}}}`}
                  </div>
                </div>
                <span className={`text-xs px-1.5 py-0.5 rounded ${getTypeColor(variable.type)}`}>
                  {variable.type}
                </span>
              </div>
            </button>
          ))}
        </div>
      )}

      {/* No matches message */}
      {showDropdown && filteredVariables.length === 0 && searchTerm && (
        <div
          ref={dropdownRef}
          className="absolute z-50 w-full bg-theme-surface border border-theme rounded-lg shadow-lg p-3 text-center"
          style={{
            top: dropdownPosition.top,
            left: dropdownPosition.left,
          }}
        >
          <p className="text-sm text-theme-tertiary">
            No variables match "{searchTerm}"
          </p>
        </div>
      )}
    </div>
  );
};

function getTypeColor(type: string): string {
  switch (type.toLowerCase()) {
    case 'string':
      return 'bg-theme-success/10 text-theme-success';
    case 'number':
    case 'integer':
      return 'bg-theme-info/10 text-theme-info';
    case 'boolean':
      return 'bg-theme-warning/10 text-theme-warning';
    case 'array':
      return 'bg-theme-interactive-primary/20 text-theme-interactive-primary';
    case 'object':
      return 'bg-theme-warning/20 text-theme-warning';
    default:
      return 'bg-theme-hover text-theme-secondary';
  }
}

export default VariableAutocomplete;

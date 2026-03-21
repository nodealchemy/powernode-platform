import React, { useState, useCallback, useEffect, useRef } from 'react';
import { Copy, Check, AlertCircle } from 'lucide-react';

interface YamlEditorProps {
  /** The current value as an object or JSON string */
  value: Record<string, unknown> | string;
  /** Callback when value changes, receives parsed object */
  onChange: (value: Record<string, unknown>) => void;
  /** Optional label */
  label?: string;
  /** Optional placeholder text */
  placeholder?: string;
  /** Optional help text */
  helpText?: string;
  /** Optional error message */
  error?: string;
  /** Whether the field is required */
  required?: boolean;
  /** Whether the editor is disabled */
  disabled?: boolean;
  /** Whether the editor is read-only */
  readOnly?: boolean;
  /** Minimum height in pixels */
  minHeight?: number;
  /** Optional className */
  className?: string;
  /** Show line numbers */
  showLineNumbers?: boolean;
  /** Show copy button */
  showCopy?: boolean;
}

/**
 * Convert an object to a YAML-like indented string format
 * This provides a readable format while working with JSON data internally
 */
function objectToYaml(obj: Record<string, unknown>, indent: number = 0): string {
  const spaces = '  '.repeat(indent);
  const lines: string[] = [];

  for (const [key, value] of Object.entries(obj)) {
    if (value === null || value === undefined) {
      lines.push(`${spaces}${key}: null`);
    } else if (typeof value === 'boolean') {
      lines.push(`${spaces}${key}: ${value}`);
    } else if (typeof value === 'number') {
      lines.push(`${spaces}${key}: ${value}`);
    } else if (typeof value === 'string') {
      // Handle multiline strings
      if (value.includes('\n')) {
        lines.push(`${spaces}${key}: |`);
        value.split('\n').forEach(line => {
          lines.push(`${spaces}  ${line}`);
        });
      } else if (value.includes(':') || value.includes('#') || value.startsWith(' ') || value.endsWith(' ')) {
        // Quote strings that need escaping
        lines.push(`${spaces}${key}: "${value.replace(/"/g, '\\"')}"`);
      } else {
        lines.push(`${spaces}${key}: ${value}`);
      }
    } else if (Array.isArray(value)) {
      if (value.length === 0) {
        lines.push(`${spaces}${key}: []`);
      } else {
        lines.push(`${spaces}${key}:`);
        value.forEach(item => {
          if (typeof item === 'object' && item !== null) {
            const itemLines = objectToYaml(item as Record<string, unknown>, indent + 2).split('\n');
            if (itemLines.length > 0) {
              lines.push(`${spaces}  - ${itemLines[0].trim()}`);
              itemLines.slice(1).forEach(line => {
                lines.push(`${spaces}    ${line.trim()}`);
              });
            }
          } else {
            lines.push(`${spaces}  - ${item}`);
          }
        });
      }
    } else if (typeof value === 'object') {
      const nested = objectToYaml(value as Record<string, unknown>, indent + 1);
      if (nested.trim()) {
        lines.push(`${spaces}${key}:`);
        lines.push(nested);
      } else {
        lines.push(`${spaces}${key}: {}`);
      }
    }
  }

  return lines.join('\n');
}

/**
 * Parse a YAML-like string into an object
 * Handles basic YAML syntax patterns
 */
function yamlToObject(yaml: string): Record<string, unknown> {
  const lines = yaml.split('\n');
  const result: Record<string, unknown> = {};
  const stack: { obj: Record<string, unknown>; indent: number; key?: string; isArray?: boolean }[] = [
    { obj: result, indent: -1 }
  ];

  let multilineKey: string | null = null;
  let multilineIndent = 0;
  let multilineValue: string[] = [];

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const trimmed = line.trimEnd();

    // Skip empty lines and comments
    if (!trimmed || trimmed.startsWith('#')) {
      if (multilineKey) {
        multilineValue.push('');
      }
      continue;
    }

    const indent = line.search(/\S/);

    // Handle multiline strings
    if (multilineKey !== null) {
      if (indent > multilineIndent) {
        multilineValue.push(line.slice(multilineIndent + 2));
        continue;
      } else {
        // End multiline
        const parent = stack[stack.length - 1];
        parent.obj[multilineKey] = multilineValue.join('\n');
        multilineKey = null;
        multilineValue = [];
      }
    }

    // Pop stack for decreased indent
    while (stack.length > 1 && indent <= stack[stack.length - 1].indent) {
      stack.pop();
    }

    const current = stack[stack.length - 1];

    // Array item
    if (trimmed.startsWith('- ')) {
      const itemValue = trimmed.slice(2).trim();
      if (current.isArray && Array.isArray(current.obj[current.key!])) {
        const arr = current.obj[current.key!] as unknown[];
        if (itemValue.includes(':')) {
          // Object in array
          const colonIdx = itemValue.indexOf(':');
          const key = itemValue.slice(0, colonIdx).trim();
          const value = parseValue(itemValue.slice(colonIdx + 1).trim());
          const itemObj: Record<string, unknown> = { [key]: value };
          arr.push(itemObj);
          stack.push({ obj: itemObj, indent: indent + 2, isArray: false });
        } else {
          arr.push(parseValue(itemValue));
        }
      }
      continue;
    }

    // Key-value pair
    const colonIdx = trimmed.indexOf(':');
    if (colonIdx > 0) {
      const key = trimmed.slice(0, colonIdx).trim();
      const valueStr = trimmed.slice(colonIdx + 1).trim();

      if (valueStr === '|') {
        // Multiline string
        multilineKey = key;
        multilineIndent = indent;
        multilineValue = [];
        continue;
      } else if (valueStr === '' || valueStr === '{}' || valueStr === '[]') {
        // Nested object or array
        if (valueStr === '[]') {
          current.obj[key] = [];
          stack.push({ obj: current.obj, indent, key, isArray: true });
        } else if (valueStr === '{}') {
          current.obj[key] = {};
        } else {
          // Check if next line is array or object
          const nextLine = lines[i + 1];
          if (nextLine && nextLine.trimStart().startsWith('-')) {
            current.obj[key] = [];
            stack.push({ obj: current.obj, indent, key, isArray: true });
          } else {
            current.obj[key] = {};
            stack.push({ obj: current.obj[key] as Record<string, unknown>, indent });
          }
        }
      } else {
        current.obj[key] = parseValue(valueStr);
      }
    }
  }

  // Handle any remaining multiline content
  if (multilineKey !== null) {
    const parent = stack[stack.length - 1];
    parent.obj[multilineKey] = multilineValue.join('\n');
  }

  return result;
}

/**
 * Parse a single value from YAML-like format
 */
function parseValue(str: string): unknown {
  if (str === '' || str === 'null' || str === '~') return null;
  if (str === 'true') return true;
  if (str === 'false') return false;

  // Number
  if (/^-?\d+$/.test(str)) return parseInt(str, 10);
  if (/^-?\d+\.\d+$/.test(str)) return parseFloat(str);

  // Quoted string
  if ((str.startsWith('"') && str.endsWith('"')) || (str.startsWith("'") && str.endsWith("'"))) {
    return str.slice(1, -1).replace(/\\"/g, '"').replace(/\\'/g, "'");
  }

  return str;
}

/**
 * YamlEditor - A YAML-like editor for JSON configuration objects
 *
 * Used for editing module specs, masks, and other configuration objects
 * that are stored as JSONB in the database.
 */
export const YamlEditor: React.FC<YamlEditorProps> = ({
  value,
  onChange,
  label,
  placeholder = '# Enter configuration in YAML format\nkey: value',
  helpText,
  error,
  required = false,
  disabled = false,
  readOnly = false,
  minHeight = 200,
  className = '',
  showLineNumbers = true,
  showCopy = true
}) => {
  const [text, setText] = useState('');
  const [parseError, setParseError] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const lineNumbersRef = useRef<HTMLDivElement>(null);

  // Convert initial value to text
  useEffect(() => {
    try {
      let obj: Record<string, unknown>;
      if (typeof value === 'string') {
        obj = value ? JSON.parse(value) : {};
      } else {
        obj = value || {};
      }
      const yamlText = Object.keys(obj).length > 0 ? objectToYaml(obj) : '';
      setText(yamlText);
      setParseError(null);
    } catch {
      setText(typeof value === 'string' ? value : '');
    }
  }, []);

  // Sync scroll between textarea and line numbers
  const handleScroll = useCallback(() => {
    if (textareaRef.current && lineNumbersRef.current) {
      lineNumbersRef.current.scrollTop = textareaRef.current.scrollTop;
    }
  }, []);

  // Handle text changes
  const handleChange = useCallback((e: React.ChangeEvent<HTMLTextAreaElement>) => {
    const newText = e.target.value;
    setText(newText);

    // Try to parse and validate
    try {
      if (!newText.trim()) {
        setParseError(null);
        onChange({});
        return;
      }

      const parsed = yamlToObject(newText);
      setParseError(null);
      onChange(parsed);
    } catch (err) {
      setParseError(err instanceof Error ? err.message : 'Invalid YAML syntax');
    }
  }, [onChange]);

  // Handle copy
  const handleCopy = useCallback(async () => {
    try {
      await navigator.clipboard.writeText(text);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      // Clipboard API not available
    }
  }, [text]);

  // Calculate line numbers
  const lineCount = text.split('\n').length;
  const lineNumbers = Array.from({ length: Math.max(lineCount, 1) }, (_, i) => i + 1);

  const hasError = !!error || !!parseError;
  const displayError = error || parseError;

  return (
    <div className={className}>
      {label && (
        <label className="block text-sm font-semibold text-theme-primary mb-2">
          {label}
          {required && <span className="text-theme-error ml-1">*</span>}
        </label>
      )}

      <div
        className={`relative border rounded-lg overflow-hidden ${
          hasError ? 'border-theme-error' : 'border-theme'
        } ${disabled ? 'opacity-60' : ''}`}
      >
        {/* Header */}
        <div className="flex items-center justify-between px-3 py-2 border-b border-theme bg-theme-surface">
          <span className="text-xs font-medium text-theme-secondary uppercase tracking-wider">
            YAML
          </span>
          {showCopy && (
            <button
              type="button"
              onClick={handleCopy}
              disabled={disabled}
              className="flex items-center gap-1 px-2 py-1 text-xs text-theme-secondary hover:text-theme-primary transition-colors duration-200 disabled:opacity-50"
            >
              {copied ? (
                <>
                  <Check className="w-3 h-3" />
                  Copied
                </>
              ) : (
                <>
                  <Copy className="w-3 h-3" />
                  Copy
                </>
              )}
            </button>
          )}
        </div>

        {/* Editor */}
        <div className="flex bg-theme-background">
          {/* Line numbers */}
          {showLineNumbers && (
            <div
              ref={lineNumbersRef}
              className="flex-shrink-0 px-3 py-3 text-right text-xs font-mono text-theme-tertiary bg-theme-surface border-r border-theme select-none overflow-hidden"
              style={{ minHeight }}
            >
              {lineNumbers.map(num => (
                <div key={num} className="leading-5">
                  {num}
                </div>
              ))}
            </div>
          )}

          {/* Textarea */}
          <textarea
            ref={textareaRef}
            value={text}
            onChange={handleChange}
            onScroll={handleScroll}
            placeholder={placeholder}
            disabled={disabled}
            readOnly={readOnly}
            className="flex-1 px-3 py-3 font-mono text-sm text-theme-primary bg-transparent resize-none focus:outline-none leading-5"
            style={{ minHeight }}
            spellCheck={false}
          />
        </div>
      </div>

      {/* Error message */}
      {displayError && (
        <p className="mt-1 text-sm text-theme-error flex items-center gap-1">
          <AlertCircle className="w-4 h-4 flex-shrink-0" />
          <span>{displayError}</span>
        </p>
      )}

      {/* Help text */}
      {helpText && !displayError && (
        <p className="mt-1 text-sm text-theme-tertiary">
          {helpText}
        </p>
      )}
    </div>
  );
};

/**
 * useYamlEditor - Hook for managing YAML editor state with useForm integration
 */
export function useYamlEditor(initialValue: Record<string, unknown> = {}) {
  const [value, setValue] = useState<Record<string, unknown>>(initialValue);
  const [error, setError] = useState<string | null>(null);

  const handleChange = useCallback((newValue: Record<string, unknown>) => {
    setValue(newValue);
    setError(null);
  }, []);

  const validate = useCallback((): boolean => {
    // Add custom validation logic here if needed
    return true;
  }, []);

  const reset = useCallback(() => {
    setValue(initialValue);
    setError(null);
  }, [initialValue]);

  return {
    value,
    error,
    onChange: handleChange,
    validate,
    reset,
    setValue
  };
}

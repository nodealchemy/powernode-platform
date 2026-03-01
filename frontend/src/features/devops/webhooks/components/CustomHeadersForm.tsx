import React, { useState, useEffect } from 'react';

interface CustomHeader {
  key: string;
  value: string;
  id: string;
}

interface CustomHeadersFormProps {
  initialHeaders?: Record<string, string>;
  onChange: (headers: Record<string, string>) => void;
  maxHeaders?: number;
  disabled?: boolean;
}

const RESERVED_HEADERS = [
  'content-type',
  'user-agent',
  'host',
  'content-length',
  'authorization',
  'accept',
  'accept-encoding',
  'connection',
  'transfer-encoding',
];

export const CustomHeadersForm: React.FC<CustomHeadersFormProps> = ({
  initialHeaders = {},
  onChange,
  maxHeaders = 20,
  disabled = false,
}) => {
  const [headers, setHeaders] = useState<CustomHeader[]>([]);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const headerList = Object.entries(initialHeaders).map(([key, value]) => ({
      key,
      value,
      id: crypto.randomUUID(),
    }));
    setHeaders(headerList.length > 0 ? headerList : [{ key: '', value: '', id: crypto.randomUUID() }]);
  }, [initialHeaders]);

  const updateParent = (newHeaders: CustomHeader[]) => {
    const headerObj: Record<string, string> = {};
    newHeaders.forEach((h) => {
      if (h.key.trim()) {
        headerObj[h.key.trim()] = h.value;
      }
    });
    onChange(headerObj);
  };

  const handleAddHeader = () => {
    if (headers.length >= maxHeaders) {
      setError(`Maximum of ${maxHeaders} headers allowed`);
      return;
    }
    const newHeaders = [...headers, { key: '', value: '', id: crypto.randomUUID() }];
    setHeaders(newHeaders);
    setError(null);
  };

  const handleRemoveHeader = (id: string) => {
    const newHeaders = headers.filter((h) => h.id !== id);
    if (newHeaders.length === 0) {
      newHeaders.push({ key: '', value: '', id: crypto.randomUUID() });
    }
    setHeaders(newHeaders);
    updateParent(newHeaders);
    setError(null);
  };

  const handleHeaderChange = (id: string, field: 'key' | 'value', value: string) => {
    setError(null);

    // Validate reserved headers
    if (field === 'key' && RESERVED_HEADERS.includes(value.toLowerCase())) {
      setError(`"${value}" is a reserved header and cannot be used`);
    }

    // Check for duplicate keys
    if (field === 'key') {
      const duplicate = headers.find(
        (h) => h.id !== id && h.key.toLowerCase() === value.toLowerCase() && value.trim()
      );
      if (duplicate) {
        setError(`Header "${value}" already exists`);
      }
    }

    const newHeaders = headers.map((h) => (h.id === id ? { ...h, [field]: value } : h));
    setHeaders(newHeaders);
    updateParent(newHeaders);
  };

  const hasValidHeaders = headers.some((h) => h.key.trim() && h.value.trim());

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <label className="block text-sm font-medium text-theme-text-primary">Custom Headers</label>
          <p className="text-xs text-theme-text-secondary mt-0.5">
            Add custom HTTP headers to include with webhook deliveries ({headers.filter((h) => h.key.trim()).length}/{maxHeaders})
          </p>
        </div>
        <button
          type="button"
          onClick={handleAddHeader}
          disabled={disabled || headers.length >= maxHeaders}
          className="inline-flex items-center gap-1 px-2 py-1 text-xs font-medium text-theme-primary hover:bg-theme-primary/10 rounded transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
        >
          <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 4v16m8-8H4" />
          </svg>
          Add Header
        </button>
      </div>

      <div className="space-y-2">
        {headers.map((header, index) => (
          <div key={header.id} className="flex items-start gap-2">
            <div className="flex-1 grid grid-cols-2 gap-2">
              <div>
                {index === 0 && (
                  <label className="block text-xs text-theme-text-tertiary mb-1">Header Name</label>
                )}
                <input
                  type="text"
                  value={header.key}
                  onChange={(e) => handleHeaderChange(header.id, 'key', e.target.value)}
                  placeholder="X-Custom-Header"
                  disabled={disabled}
                  className="w-full px-3 py-2 text-sm border border-theme-border rounded-lg bg-theme-bg-secondary text-theme-text-primary placeholder-theme-text-tertiary focus:outline-none focus:ring-2 focus:ring-theme-primary focus:border-transparent disabled:opacity-50"
                />
              </div>
              <div>
                {index === 0 && (
                  <label className="block text-xs text-theme-text-tertiary mb-1">Value</label>
                )}
                <input
                  type="text"
                  value={header.value}
                  onChange={(e) => handleHeaderChange(header.id, 'value', e.target.value)}
                  placeholder="header-value"
                  disabled={disabled}
                  className="w-full px-3 py-2 text-sm border border-theme-border rounded-lg bg-theme-bg-secondary text-theme-text-primary placeholder-theme-text-tertiary focus:outline-none focus:ring-2 focus:ring-theme-primary focus:border-transparent disabled:opacity-50"
                />
              </div>
            </div>
            <button
              type="button"
              onClick={() => handleRemoveHeader(header.id)}
              disabled={disabled || (headers.length === 1 && !header.key && !header.value)}
              className={`p-2 text-theme-text-tertiary hover:text-theme-danger hover:bg-theme-danger/10 rounded transition-colors disabled:opacity-50 disabled:cursor-not-allowed ${index === 0 ? 'mt-5' : ''}`}
            >
              <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  strokeWidth={2}
                  d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"
                />
              </svg>
            </button>
          </div>
        ))}
      </div>

      {error && (
        <div className="p-2 bg-theme-danger/10 border border-theme-danger/20 rounded-lg">
          <p className="text-xs text-theme-danger">{error}</p>
        </div>
      )}

      {hasValidHeaders && (
        <div className="p-3 bg-theme-bg-tertiary rounded-lg">
          <div className="text-xs font-medium text-theme-text-secondary mb-2">Preview</div>
          <div className="font-mono text-xs space-y-0.5">
            {headers
              .filter((h) => h.key.trim())
              .map((h) => (
                <div key={h.id} className="text-theme-text-primary">
                  <span className="text-theme-primary">{h.key}</span>
                  <span className="text-theme-text-tertiary">: </span>
                  <span>{h.value || '(empty)'}</span>
                </div>
              ))}
          </div>
        </div>
      )}

      <div className="text-xs text-theme-text-tertiary">
        <strong>Note:</strong> Reserved headers like Content-Type, Authorization, and Host cannot be
        overridden.
      </div>
    </div>
  );
};

export default CustomHeadersForm;

import React, { useState } from 'react';
import { Copy, Check, ChevronRight, ChevronDown, Search } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { Input } from '@/shared/components/ui/Input';
import { useNotifications } from '@/shared/hooks/useNotifications';

interface WebhookPayloadViewerProps {
  payload: Record<string, unknown>;
  className?: string;
}

interface JsonNodeProps {
  keyName?: string;
  value: unknown;
  depth: number;
  searchTerm: string;
}

const JsonNode: React.FC<JsonNodeProps> = ({ keyName, value, depth, searchTerm }) => {
  const [isExpanded, setIsExpanded] = useState(depth < 2);

  const isObject = value !== null && typeof value === 'object';
  const isArray = Array.isArray(value);
  const isEmpty = isObject && Object.keys(value as object).length === 0;

  const indent = depth * 16;

  const matchesSearch = (val: unknown): boolean => {
    if (!searchTerm) return false;
    const term = searchTerm.toLowerCase();
    if (typeof val === 'string') return val.toLowerCase().includes(term);
    if (typeof val === 'number') return val.toString().includes(term);
    if (keyName) return keyName.toLowerCase().includes(term);
    return false;
  };

  const highlight = matchesSearch(value) || (keyName && keyName.toLowerCase().includes(searchTerm.toLowerCase()));

  const renderValue = () => {
    if (value === null) return <span className="text-theme-tertiary">null</span>;
    if (value === undefined) return <span className="text-theme-tertiary">undefined</span>;
    if (typeof value === 'boolean') {
      return <span className="text-theme-accent">{value.toString()}</span>;
    }
    if (typeof value === 'number') {
      return <span className="text-theme-info">{value}</span>;
    }
    if (typeof value === 'string') {
      // Check if it's a URL
      if (value.startsWith('http://') || value.startsWith('https://')) {
        return (
          <a
            href={value}
            target="_blank"
            rel="noopener noreferrer"
            className="text-theme-success hover:underline"
          >
            "{value}"
          </a>
        );
      }
      return <span className="text-theme-success">"{value}"</span>;
    }
    return null;
  };

  if (!isObject) {
    return (
      <div
        className={`flex items-center py-0.5 ${highlight ? 'bg-theme-warning/20' : ''}`}
        style={{ paddingLeft: indent }}
      >
        {keyName && (
          <>
            <span className="text-theme-info">"{keyName}"</span>
            <span className="text-theme-secondary mx-1">:</span>
          </>
        )}
        {renderValue()}
      </div>
    );
  }

  const entries = Object.entries(value as object);
  const bracketOpen = isArray ? '[' : '{';
  const bracketClose = isArray ? ']' : '}';

  if (isEmpty) {
    return (
      <div
        className={`flex items-center py-0.5 ${highlight ? 'bg-theme-warning/20' : ''}`}
        style={{ paddingLeft: indent }}
      >
        {keyName && (
          <>
            <span className="text-theme-info">"{keyName}"</span>
            <span className="text-theme-secondary mx-1">:</span>
          </>
        )}
        <span className="text-theme-secondary">{bracketOpen}{bracketClose}</span>
      </div>
    );
  }

  return (
    <div className={highlight ? 'bg-theme-warning/20' : ''}>
      <button
        className="flex items-center py-0.5 hover:bg-theme-surface-hover w-full text-left"
        style={{ paddingLeft: indent }}
        onClick={() => setIsExpanded(!isExpanded)}
      >
        {isExpanded ? (
          <ChevronDown className="w-3 h-3 text-theme-tertiary mr-1 flex-shrink-0" />
        ) : (
          <ChevronRight className="w-3 h-3 text-theme-tertiary mr-1 flex-shrink-0" />
        )}
        {keyName && (
          <>
            <span className="text-theme-info">"{keyName}"</span>
            <span className="text-theme-secondary mx-1">:</span>
          </>
        )}
        <span className="text-theme-secondary">{bracketOpen}</span>
        {!isExpanded && (
          <>
            <span className="text-theme-tertiary mx-1">
              {isArray ? `${entries.length} items` : `${entries.length} keys`}
            </span>
            <span className="text-theme-secondary">{bracketClose}</span>
          </>
        )}
      </button>

      {isExpanded && (
        <>
          {entries.map(([key, val]) => (
            <JsonNode
              key={key}
              keyName={isArray ? undefined : key}
              value={val}
              depth={depth + 1}
              searchTerm={searchTerm}
            />
          ))}
          <div style={{ paddingLeft: indent }} className="text-theme-secondary py-0.5">
            {bracketClose}
          </div>
        </>
      )}
    </div>
  );
};

export const WebhookPayloadViewer: React.FC<WebhookPayloadViewerProps> = ({
  payload,
  className = '',
}) => {
  const [searchTerm, setSearchTerm] = useState('');
  const [copied, setCopied] = useState(false);
  const { showNotification } = useNotifications();

  const handleCopy = async () => {
    try {
      await navigator.clipboard.writeText(JSON.stringify(payload, null, 2));
      setCopied(true);
      showNotification('Payload copied to clipboard', 'success');
      setTimeout(() => setCopied(false), 2000);
    } catch {
      // Copy failed silently
    }
  };

  return (
    <div className={`bg-theme-surface-inset rounded-lg overflow-hidden ${className}`}>
      {/* Header */}
      <div className="flex items-center justify-between px-4 py-2 bg-theme-surface border-b border-theme">
        <div className="relative flex-1 max-w-xs">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-theme-tertiary" />
          <Input
            type="text"
            placeholder="Search payload..."
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
            className="pl-9 text-sm"
          />
        </div>
        <Button
          onClick={handleCopy}
          variant="ghost"
          size="sm"
          className="text-theme-secondary hover:text-theme-primary ml-2"
        >
          {copied ? (
            <>
              <Check className="w-4 h-4 mr-1" />
              Copied
            </>
          ) : (
            <>
              <Copy className="w-4 h-4 mr-1" />
              Copy
            </>
          )}
        </Button>
      </div>

      {/* Content */}
      <div className="max-h-96 overflow-auto font-mono text-sm p-2">
        <JsonNode
          value={payload}
          depth={0}
          searchTerm={searchTerm}
        />
      </div>

      {/* Footer */}
      <div className="px-4 py-2 bg-theme-surface border-t border-theme text-xs text-theme-tertiary">
        {Object.keys(payload).length} top-level keys •{' '}
        {(JSON.stringify(payload).length / 1024).toFixed(1)} KB
      </div>
    </div>
  );
};

export default WebhookPayloadViewer;

import { useState } from 'react';
import { ChevronDown, ChevronRight, Copy, Check, ExternalLink } from 'lucide-react';
import type { ExecutionResource } from '../types';

interface OutputViewerProps {
  data: Record<string, unknown> | ExecutionResource;
}

const URL_REGEX = /https?:\/\/[^\s"'<>]+/g;

function JsonNode({ label, value, depth = 0 }: { label: string; value: unknown; depth?: number }) {
  const [expanded, setExpanded] = useState(depth < 2);

  if (value === null || value === undefined) {
    return (
      <div className="flex items-center gap-1" style={{ paddingLeft: `${depth * 16}px` }}>
        <span className="text-theme-text-tertiary">{label}:</span>
        <span className="text-theme-text-tertiary italic">null</span>
      </div>
    );
  }

  if (typeof value === 'string') {
    const urls = value.match(URL_REGEX);
    return (
      <div className="flex items-start gap-1" style={{ paddingLeft: `${depth * 16}px` }}>
        <span className="text-theme-text-tertiary shrink-0">{label}:</span>
        <span className="text-theme-text-primary break-all">
          {urls ? (
            <a href={urls[0]} target="_blank" rel="noopener noreferrer" className="text-theme-primary hover:underline inline-flex items-center gap-0.5">
              {value}
              <ExternalLink className="w-3 h-3" />
            </a>
          ) : (
            `"${value}"`
          )}
        </span>
      </div>
    );
  }

  if (typeof value === 'number' || typeof value === 'boolean') {
    return (
      <div className="flex items-center gap-1" style={{ paddingLeft: `${depth * 16}px` }}>
        <span className="text-theme-text-tertiary">{label}:</span>
        <span className="text-theme-text-primary">{String(value)}</span>
      </div>
    );
  }

  if (typeof value === 'object') {
    const entries = Array.isArray(value)
      ? value.map((v, i) => [String(i), v] as [string, unknown])
      : Object.entries(value as Record<string, unknown>);

    return (
      <div style={{ paddingLeft: `${depth * 16}px` }}>
        <button
          onClick={() => setExpanded(!expanded)}
          className="flex items-center gap-1 text-theme-text-secondary hover:text-theme-text-primary transition-colors"
        >
          {expanded ? <ChevronDown className="w-3.5 h-3.5" /> : <ChevronRight className="w-3.5 h-3.5" />}
          <span className="text-theme-text-tertiary">{label}</span>
          <span className="text-xs text-theme-text-tertiary">
            {Array.isArray(value) ? `[${entries.length}]` : `{${entries.length}}`}
          </span>
        </button>
        {expanded && entries.map(([k, v]) => (
          <JsonNode key={k} label={k} value={v} depth={depth + 1} />
        ))}
      </div>
    );
  }

  return null;
}

export function OutputViewer({ data }: OutputViewerProps) {
  const [copied, setCopied] = useState(false);

  const handleCopy = () => {
    navigator.clipboard.writeText(JSON.stringify(data, null, 2));
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <div className="space-y-2">
      <div className="flex justify-end">
        <button
          onClick={handleCopy}
          className="inline-flex items-center gap-1 px-2 py-1 text-xs text-theme-text-secondary hover:text-theme-text-primary transition-colors"
        >
          {copied ? <Check className="w-3.5 h-3.5" /> : <Copy className="w-3.5 h-3.5" />}
          {copied ? 'Copied' : 'Copy'}
        </button>
      </div>
      <div className="rounded-lg border border-theme-border p-3 bg-theme-bg-tertiary text-xs font-mono space-y-0.5">
        {Object.entries(data as Record<string, unknown>).map(([key, value]) => (
          <JsonNode key={key} label={key} value={value} />
        ))}
      </div>
    </div>
  );
}

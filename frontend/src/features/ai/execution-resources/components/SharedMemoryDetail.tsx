import React from 'react';
import { ExternalLink } from 'lucide-react';
import type { ExecutionResource } from '../types';

interface SharedMemoryDetailProps {
  resource: ExecutionResource;
}

const URL_REGEX = /https?:\/\/[^\s"'<>]+/g;

function autoLinkUrls(text: string): React.ReactNode[] {
  const parts = text.split(URL_REGEX);
  const urls = text.match(URL_REGEX) || [];
  const result: React.ReactNode[] = [];

  parts.forEach((part, i) => {
    result.push(<span key={`text-${i}`}>{part}</span>);
    if (urls[i]) {
      result.push(
        <a
          key={`url-${i}`}
          href={urls[i]}
          target="_blank"
          rel="noopener noreferrer"
          className="text-theme-primary hover:underline inline-flex items-center gap-0.5"
        >
          {urls[i]}
          <ExternalLink className="w-3 h-3 inline" />
        </a>
      );
    }
  });

  return result;
}

export function SharedMemoryDetail({ resource }: SharedMemoryDetailProps) {
  const previewText = resource.preview || '{}';
  let parsed: Record<string, unknown> = {};

  try {
    parsed = JSON.parse(previewText);
  } catch {
    // Not JSON, display as text
  }

  const entries = Object.entries(parsed);

  return (
    <div className="space-y-4">
      <div className="text-sm text-theme-text-secondary">
        Pool: {resource.source_label}
      </div>

      {resource.url && (
        <a
          href={resource.url}
          target="_blank"
          rel="noopener noreferrer"
          className="inline-flex items-center gap-1.5 text-sm text-theme-primary hover:underline"
        >
          <ExternalLink className="w-3.5 h-3.5" />
          Open URL
        </a>
      )}

      {entries.length > 0 ? (
        <div className="space-y-2">
          {entries.map(([key, value]) => (
            <div key={key} className="p-3 rounded-lg border border-theme-border">
              <div className="text-xs font-medium text-theme-text-tertiary mb-1">{key}</div>
              <div className="text-sm text-theme-text-primary font-mono whitespace-pre-wrap break-all">
                {typeof value === 'string'
                  ? autoLinkUrls(value)
                  : JSON.stringify(value, null, 2)}
              </div>
            </div>
          ))}
        </div>
      ) : (
        <div className="p-3 rounded-lg bg-theme-bg-tertiary font-mono text-xs text-theme-text-primary whitespace-pre-wrap">
          {autoLinkUrls(previewText)}
        </div>
      )}

      {resource.metadata && (
        <div className="text-xs text-theme-text-tertiary">
          Version: {(resource.metadata as Record<string, unknown>).version as string || 'N/A'}
        </div>
      )}
    </div>
  );
}

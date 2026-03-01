import React from 'react';
import { ExternalLink, Database, Clock, Shield, User } from 'lucide-react';
import type { ResourceDetailProps } from '../types';
import { DetailSection, StatCard, formatBytes, formatTimestamp } from './DetailSection';
import { OutputViewer } from './OutputViewer';

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

export function SharedMemoryDetail({ resource }: ResourceDetailProps) {
  const data = resource.full_data || {};
  const entries = Object.entries(data);

  return (
    <div className="space-y-4">
      {/* Pool info */}
      <div className="grid grid-cols-2 gap-2">
        <StatCard label="Pool Type" value={resource.pool_type} icon={<Database className="w-3.5 h-3.5" />} />
        <StatCard label="Scope" value={resource.scope} />
        <StatCard label="Size" value={formatBytes(resource.data_size_bytes)} />
        <StatCard label="Version" value={resource.version} />
      </div>

      {/* Metadata */}
      <div className="flex flex-wrap gap-3 text-sm">
        {resource.persist_across_executions && (
          <span className="px-2 py-0.5 rounded text-xs bg-theme-info/10 text-theme-info">Persistent</span>
        )}
        {resource.owner_agent_name && (
          <div className="flex items-center gap-1.5">
            <User className="w-3.5 h-3.5 text-theme-tertiary" />
            <span className="text-theme-secondary">Owner:</span>
            <span className="text-theme-primary">{resource.owner_agent_name}</span>
          </div>
        )}
        {resource.team_name && (
          <span className="text-theme-secondary">Team: <span className="text-theme-primary">{resource.team_name}</span></span>
        )}
      </div>

      {/* Timestamps */}
      <div className="flex flex-wrap gap-4 text-xs text-theme-tertiary">
        {resource.last_accessed_at && (
          <div className="flex items-center gap-1">
            <Clock className="w-3 h-3" />
            Last accessed: {formatTimestamp(resource.last_accessed_at)}
          </div>
        )}
        {resource.expires_at && (
          <div className="flex items-center gap-1">
            <Clock className="w-3 h-3" />
            Expires: {formatTimestamp(resource.expires_at)}
          </div>
        )}
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

      {/* Data */}
      <DetailSection title={`Data (${entries.length} entries)`} defaultOpen>
        {entries.length > 0 ? (
          <div className="space-y-2">
            {entries.map(([key, value]) => (
              <div key={key} className="p-3 rounded-lg border border-theme">
                <div className="text-xs font-medium text-theme-tertiary mb-1">{key}</div>
                <div className="text-sm text-theme-primary font-mono whitespace-pre-wrap break-all">
                  {typeof value === 'string'
                    ? autoLinkUrls(value)
                    : JSON.stringify(value, null, 2)}
                </div>
              </div>
            ))}
          </div>
        ) : (
          <div className="text-sm text-theme-tertiary italic">No data entries</div>
        )}
      </DetailSection>

      {/* Access control */}
      {resource.access_control && Object.keys(resource.access_control).length > 0 && (
        <DetailSection title="Access Control" icon={<Shield className="w-4 h-4" />} defaultOpen={false}>
          <OutputViewer data={resource.access_control} />
        </DetailSection>
      )}

      {/* Retention policy */}
      {resource.retention_policy && Object.keys(resource.retention_policy).length > 0 && (
        <DetailSection title="Retention Policy" defaultOpen={false}>
          <OutputViewer data={resource.retention_policy} />
        </DetailSection>
      )}
    </div>
  );
}

import { Clock, DollarSign, Zap, AlertTriangle, User, ExternalLink } from 'lucide-react';
import type { ResourceDetailProps } from '../types';
import { DetailSection, StatCard, formatDuration, formatTimestamp } from './DetailSection';
import { OutputViewer } from './OutputViewer';

export function ArtifactContentViewer({ resource }: ResourceDetailProps) {
  const isJson = resource.mime_type?.includes('json');
  const isCode = resource.mime_type?.includes('javascript') ||
    resource.mime_type?.includes('typescript') ||
    resource.mime_type?.includes('python') ||
    resource.mime_type?.includes('ruby');

  const formatContent = (content: string) => {
    if (isJson) {
      try {
        return JSON.stringify(JSON.parse(content), null, 2);
      } catch {
        return content;
      }
    }
    return content;
  };

  const hasError = resource.error_message || resource.error_code;
  const hasStats = resource.cost || resource.tokens_used || resource.duration_ms;

  return (
    <div className="space-y-4">
      {/* Agent Info */}
      {(resource.from_agent_name || resource.to_agent_name) && (
        <div className="flex items-center gap-4 text-sm">
          {resource.from_agent_name && (
            <div className="flex items-center gap-1.5">
              <User className="w-3.5 h-3.5 text-theme-tertiary" />
              <span className="text-theme-secondary">From:</span>
              <span className="font-medium text-theme-primary">{resource.from_agent_name}</span>
            </div>
          )}
          {resource.to_agent_name && (
            <div className="flex items-center gap-1.5">
              <User className="w-3.5 h-3.5 text-theme-tertiary" />
              <span className="text-theme-secondary">To:</span>
              <span className="font-medium text-theme-primary">{resource.to_agent_name}</span>
            </div>
          )}
        </div>
      )}

      {/* Stats */}
      {hasStats && (
        <div className="grid grid-cols-3 gap-2">
          <StatCard label="Cost" value={resource.cost ? `$${Number(resource.cost).toFixed(4)}` : undefined} icon={<DollarSign className="w-3.5 h-3.5" />} />
          <StatCard label="Tokens" value={resource.tokens_used?.toLocaleString()} icon={<Zap className="w-3.5 h-3.5" />} />
          <StatCard label="Duration" value={formatDuration(resource.duration_ms)} icon={<Clock className="w-3.5 h-3.5" />} />
        </div>
      )}

      {/* Timestamps */}
      {(resource.started_at || resource.completed_at) && (
        <div className="flex gap-4 text-xs text-theme-tertiary">
          {resource.started_at && <span>Started: {formatTimestamp(resource.started_at)}</span>}
          {resource.completed_at && <span>Completed: {formatTimestamp(resource.completed_at)}</span>}
        </div>
      )}

      {/* Extra info */}
      <div className="flex flex-wrap gap-3 text-xs text-theme-secondary">
        {resource.subtasks_count !== undefined && resource.subtasks_count > 0 && (
          <span>Subtasks: {resource.subtasks_count}</span>
        )}
        {resource.is_external && <span className="px-1.5 py-0.5 rounded bg-theme-info/10 text-theme-info">External</span>}
        {resource.retry_count !== undefined && resource.retry_count > 0 && (
          <span>Retries: {resource.retry_count}/{resource.max_retries}</span>
        )}
        {resource.sequence_number !== undefined && <span>Seq #{resource.sequence_number}</span>}
      </div>

      {resource.mime_type && (
        <div className="text-xs text-theme-tertiary">
          MIME: {resource.mime_type}
        </div>
      )}

      {resource.url && (
        <a
          href={resource.url}
          target="_blank"
          rel="noopener noreferrer"
          className="inline-flex items-center gap-1.5 text-sm text-theme-primary hover:underline"
        >
          <ExternalLink className="w-3.5 h-3.5" />
          Open original
        </a>
      )}

      {/* Error */}
      {hasError && (
        <DetailSection title="Error" icon={<AlertTriangle className="w-4 h-4" />} defaultOpen>
          <div className="space-y-2">
            {resource.error_code && (
              <span className="text-xs px-2 py-0.5 rounded bg-theme-error/10 text-theme-error font-mono">{resource.error_code}</span>
            )}
            {resource.error_message && (
              <p className="text-sm text-theme-error">{resource.error_message}</p>
            )}
            {resource.error_details && Object.keys(resource.error_details).length > 0 && (
              <OutputViewer data={resource.error_details} />
            )}
          </div>
        </DetailSection>
      )}

      {/* Content preview */}
      {resource.preview && (
        <DetailSection title="Content Preview" defaultOpen>
          <div className={`rounded-lg border border-theme p-4 overflow-auto max-h-[400px] ${
            isCode || isJson ? 'font-mono text-xs' : 'text-sm'
          } bg-theme-surface text-theme-primary whitespace-pre-wrap`}>
            {formatContent(resource.preview)}
          </div>
        </DetailSection>
      )}

      {/* Full artifacts */}
      {resource.full_artifacts && resource.full_artifacts.length > 0 && (
        <DetailSection title={`Artifacts (${resource.full_artifacts.length})`} defaultOpen={false}>
          <OutputViewer data={{ artifacts: resource.full_artifacts }} />
        </DetailSection>
      )}

      {/* Input */}
      {resource.input && Object.keys(resource.input).length > 0 && (
        <DetailSection title="Input" defaultOpen={false}>
          <OutputViewer data={resource.input} />
        </DetailSection>
      )}

      {/* Output */}
      {resource.output && Object.keys(resource.output).length > 0 && (
        <DetailSection title="Output" defaultOpen={false}>
          <OutputViewer data={resource.output} />
        </DetailSection>
      )}

      {/* History */}
      {resource.history && resource.history.length > 0 && (
        <DetailSection title={`History (${resource.history.length})`} defaultOpen={false}>
          <OutputViewer data={{ history: resource.history }} />
        </DetailSection>
      )}
    </div>
  );
}

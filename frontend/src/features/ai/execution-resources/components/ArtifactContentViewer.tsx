

import type { ExecutionResource } from '../types';

interface ArtifactContentViewerProps {
  resource: ExecutionResource;
}

export function ArtifactContentViewer({ resource }: ArtifactContentViewerProps) {
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

  return (
    <div className="space-y-4">
      {resource.mime_type && (
        <div className="text-xs text-theme-text-tertiary">
          MIME: {resource.mime_type}
        </div>
      )}

      {resource.url && (
        <a
          href={resource.url}
          target="_blank"
          rel="noopener noreferrer"
          className="text-sm text-theme-primary hover:underline"
        >
          Open original
        </a>
      )}

      <div className={`rounded-lg border border-theme-border p-4 overflow-auto max-h-[500px] ${
        isCode || isJson ? 'font-mono text-xs' : 'text-sm'
      } bg-theme-bg-tertiary text-theme-text-primary whitespace-pre-wrap`}>
        {resource.preview ? formatContent(resource.preview) : 'No content available'}
      </div>

      {resource.description && (
        <div className="text-sm text-theme-text-secondary">
          {resource.description}
        </div>
      )}
    </div>
  );
}

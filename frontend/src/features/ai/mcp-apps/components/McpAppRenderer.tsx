import React, { useState, useRef, useCallback } from 'react';
import { ExternalLink, RefreshCw, Shield } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useRenderMcpApp } from '../api/mcpAppsApi';
import type { McpAppRenderResult } from '../types/mcpApps';

interface McpAppRendererProps {
  appId: string;
  appName: string;
  sessionId?: string;
}

export const McpAppRenderer: React.FC<McpAppRendererProps> = ({
  appId,
  appName,
  sessionId,
}) => {
  const iframeRef = useRef<HTMLIFrameElement>(null);
  const [renderResult, setRenderResult] = useState<McpAppRenderResult | null>(null);
  const renderApp = useRenderMcpApp();

  const handleRender = useCallback(() => {
    renderApp.mutate(
      { id: appId, session_id: sessionId },
      {
        onSuccess: (result) => {
          setRenderResult(result);
        },
      }
    );
  }, [appId, sessionId, renderApp]);

  const handleRefresh = () => {
    setRenderResult(null);
    handleRender();
  };

  if (!renderResult && !renderApp.isPending) {
    return (
      <div className="bg-theme-card border border-theme rounded-lg p-8 text-center">
        <Shield className="h-10 w-10 text-theme-muted mx-auto mb-3 opacity-50" />
        <h4 className="text-sm font-medium text-theme-primary mb-2">
          Sandboxed Renderer
        </h4>
        <p className="text-xs text-theme-secondary mb-4">
          Render &quot;{appName}&quot; in a sandboxed iframe environment.
        </p>
        <Button variant="primary" size="sm" onClick={handleRender}>
          <ExternalLink className="h-4 w-4 mr-1" />
          Render App
        </Button>
      </div>
    );
  }

  if (renderApp.isPending) {
    return (
      <div className="bg-theme-card border border-theme rounded-lg p-8 text-center">
        <LoadingSpinner size="sm" className="mb-2" />
        <p className="text-sm text-theme-secondary">Rendering app...</p>
      </div>
    );
  }

  if (renderApp.isError) {
    return (
      <div className="bg-theme-card border border-theme rounded-lg p-8 text-center">
        <p className="text-sm text-theme-error mb-3">Failed to render app.</p>
        <Button variant="secondary" size="sm" onClick={handleRender}>
          Retry
        </Button>
      </div>
    );
  }

  return (
    <div className="bg-theme-card border border-theme rounded-lg overflow-hidden">
      {/* Toolbar */}
      <div className="flex items-center justify-between px-3 py-2 bg-theme-surface border-b border-theme">
        <div className="flex items-center gap-2">
          <Shield className="h-4 w-4 text-theme-muted" />
          <span className="text-xs font-medium text-theme-primary">{appName}</span>
          {renderResult?.instance_id && (
            <Badge variant="outline" size="xs">
              {renderResult.instance_id.slice(0, 8)}...
            </Badge>
          )}
        </div>
        <Button variant="ghost" size="xs" onClick={handleRefresh} title="Refresh">
          <RefreshCw className="h-3.5 w-3.5" />
        </Button>
      </div>

      {/* Sandboxed iframe */}
      {renderResult && (
        <iframe
          ref={iframeRef}
          srcDoc={renderResult.html}
          sandbox={renderResult.sandbox_attrs || 'allow-scripts'}
          className="w-full border-0"
          style={{ minHeight: '400px' }}
          title={`MCP App: ${appName}`}
        />
      )}
    </div>
  );
};

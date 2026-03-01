import React, { useState } from 'react';
import { ExternalLink, Monitor, RefreshCw } from 'lucide-react';

interface AppPreviewPanelProps {
  url: string;
  port: number | null;
  containerId: string | null;
}

export const AppPreviewPanel: React.FC<AppPreviewPanelProps> = ({ url, port, containerId }) => {
  const [showIframe, setShowIframe] = useState(false);
  const [iframeKey, setIframeKey] = useState(0);

  return (
    <div className="card-theme-elevated p-5">
      <div className="flex items-center justify-between mb-4">
        <div className="flex items-center gap-2">
          <Monitor className="w-5 h-5 text-theme-accent" />
          <h3 className="text-sm font-semibold text-theme-primary">App Preview</h3>
        </div>
        <div className="flex items-center gap-2">
          {showIframe && (
            <button
              onClick={() => setIframeKey(k => k + 1)}
              className="p-1 text-theme-tertiary hover:text-theme-primary"
              title="Refresh preview"
            >
              <RefreshCw className="w-4 h-4" />
            </button>
          )}
          <a
            href={url}
            target="_blank"
            rel="noopener noreferrer"
            className="inline-flex items-center gap-1 text-xs text-theme-accent hover:underline"
          >
            Open in new tab <ExternalLink className="w-3 h-3" />
          </a>
        </div>
      </div>

      <div className="space-y-3">
        <div className="flex items-center gap-4 text-xs">
          <div className="flex items-center gap-1">
            <span className="w-2 h-2 rounded-full bg-theme-success" />
            <span className="text-theme-secondary">Running</span>
          </div>
          {port && (
            <span className="text-theme-tertiary">Port: {port}</span>
          )}
          {containerId && (
            <span className="text-theme-tertiary font-mono">
              {containerId.substring(0, 12)}
            </span>
          )}
        </div>

        {!showIframe ? (
          <button
            onClick={() => setShowIframe(true)}
            className="w-full py-8 border-2 border-dashed border-theme-border rounded-lg text-center hover:border-theme-accent/50 transition-colors"
          >
            <Monitor className="w-8 h-8 text-theme-tertiary mx-auto mb-2" />
            <span className="text-sm text-theme-secondary">Click to load preview</span>
          </button>
        ) : (
          <div className="border border-theme-border rounded-lg overflow-hidden">
            <iframe
              key={iframeKey}
              src={url}
              title="App Preview"
              className="w-full h-96 bg-white"
              sandbox="allow-scripts allow-same-origin allow-forms"
            />
          </div>
        )}
      </div>
    </div>
  );
};


import { AlertCircle, Zap, Package, FileText, ChevronRight, ExternalLink } from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import type { McpServer, McpTool } from '@/pages/app/ai/McpBrowserPage';

export interface McpServerCardProps {
  server: McpServer;
  tools: McpTool[];
  onTestTool?: (tool: McpTool) => void;
  onClick?: () => void;
}

export const McpServerCard: React.FC<McpServerCardProps> = ({
  server,
  tools,
  onTestTool,
  onClick
}) => {
  const getStatusBadge = () => {
    switch (server.status) {
      case 'connected':
        return <Badge variant="success" size="sm">Connected</Badge>;
      case 'disconnected':
        return <Badge variant="outline" size="sm">Disconnected</Badge>;
      case 'error':
        return <Badge variant="danger" size="sm">Error</Badge>;
      default:
        return <Badge variant="outline" size="sm">Unknown</Badge>;
    }
  };

  const getConnectionTypeBadge = () => {
    const colors: Record<string, string> = {
      stdio: 'bg-theme-interactive-primary',
      sse: 'bg-theme-success',
      websocket: 'bg-theme-info'
    };

    const color = colors[server.connection_type] || 'bg-theme-tertiary';

    return (
      <Badge variant="outline" size="sm" className={`${color} bg-opacity-10`}>
        {server.connection_type.toUpperCase()}
      </Badge>
    );
  };

  const formatTimestamp = (timestamp?: string) => {
    if (!timestamp) return 'Never';
    const date = new Date(timestamp);
    const now = new Date();
    const diff = now.getTime() - date.getTime();

    const seconds = Math.floor(diff / 1000);
    const minutes = Math.floor(seconds / 60);
    const hours = Math.floor(minutes / 60);
    const days = Math.floor(hours / 24);

    if (days > 0) return `${days}d ago`;
    if (hours > 0) return `${hours}h ago`;
    if (minutes > 0) return `${minutes}m ago`;
    return `${seconds}s ago`;
  };

  return (
    <Card className="p-5 hover:shadow-lg transition-shadow">
      {/* Header */}
      <div className="flex items-start justify-between mb-4">
        <div className="flex items-center gap-3">
          <div className={`w-12 h-12 rounded-lg flex items-center justify-center text-2xl ${
            server.status === 'connected' ? 'bg-theme-success bg-opacity-10' :
            server.status === 'error' ? 'bg-theme-error bg-opacity-10' :
            'bg-theme-surface'
          }`}>
            {server.metadata?.icon || '🔌'}
          </div>
          <div>
            <h3 className="font-semibold text-theme-primary flex items-center gap-2">
              {server.name}
              {server.metadata?.url && (
                <a
                  href={server.metadata.url}
                  target="_blank"
                  rel="noopener noreferrer"
                  onClick={(e) => e.stopPropagation()}
                  className="text-theme-tertiary hover:text-theme-interactive-primary transition-colors"
                >
                  <ExternalLink className="h-4 w-4" />
                </a>
              )}
            </h3>
            <p className="text-sm text-theme-tertiary">v{server.version}</p>
          </div>
        </div>
        <div className="flex items-center gap-2">
          {getConnectionTypeBadge()}
          {getStatusBadge()}
        </div>
      </div>

      {/* Description */}
      {server.description && (
        <p className="text-sm text-theme-secondary mb-4">{server.description}</p>
      )}

      {/* Error Message */}
      {server.status === 'error' && server.error_message && (
        <div className="mb-4 p-3 bg-theme-error bg-opacity-5 border border-theme-error rounded-lg">
          <div className="flex items-center gap-2 text-theme-error text-sm">
            <AlertCircle className="h-4 w-4 flex-shrink-0" />
            <span>{server.error_message}</span>
          </div>
        </div>
      )}

      {/* Capabilities */}
      <div className="flex items-center gap-2 mb-4 flex-wrap">
        {server.capabilities.tools && (
          <Badge variant="outline" size="sm" className="flex items-center gap-1">
            <Zap className="h-3 w-3" />
            Tools
          </Badge>
        )}
        {server.capabilities.resources && (
          <Badge variant="outline" size="sm" className="flex items-center gap-1">
            <Package className="h-3 w-3" />
            Resources
          </Badge>
        )}
        {server.capabilities.prompts && (
          <Badge variant="outline" size="sm" className="flex items-center gap-1">
            <FileText className="h-3 w-3" />
            Prompts
          </Badge>
        )}
      </div>

      {/* Statistics */}
      <div className="grid grid-cols-3 gap-4 mb-4 p-3 bg-theme-surface rounded-lg">
        <div>
          <p className="text-xs text-theme-tertiary mb-1">Tools</p>
          <p className="text-lg font-bold text-theme-primary">{server.tools_count}</p>
        </div>
        <div>
          <p className="text-xs text-theme-tertiary mb-1">Resources</p>
          <p className="text-lg font-bold text-theme-primary">{server.resources_count}</p>
        </div>
        <div>
          <p className="text-xs text-theme-tertiary mb-1">Prompts</p>
          <p className="text-lg font-bold text-theme-primary">{server.prompts_count}</p>
        </div>
      </div>

      {/* Metadata */}
      <div className="text-xs text-theme-tertiary space-y-1 mb-4">
        {server.metadata?.author && (
          <div className="flex justify-between">
            <span>Author:</span>
            <span className="text-theme-primary">{server.metadata.author}</span>
          </div>
        )}
        <div className="flex justify-between">
          <span>Protocol:</span>
          <span className="text-theme-primary">{server.protocol_version}</span>
        </div>
        {server.last_connected_at && (
          <div className="flex justify-between">
            <span>Last Connected:</span>
            <span className="text-theme-primary">{formatTimestamp(server.last_connected_at)}</span>
          </div>
        )}
      </div>

      {/* Tools List */}
      {tools.length > 0 && (
        <div className="mb-4">
          <h4 className="text-sm font-medium text-theme-primary mb-2">Available Tools</h4>
          <div className="space-y-2 max-h-40 overflow-y-auto">
            {tools.slice(0, 5).map(tool => (
              <div
                key={tool.id}
                className="flex items-center justify-between p-2 bg-theme-surface rounded hover:bg-theme-interactive-primary hover:bg-opacity-5 transition-colors"
              >
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-medium text-theme-primary truncate">{tool.name}</p>
                  {tool.description && (
                    <p className="text-xs text-theme-tertiary truncate">{tool.description}</p>
                  )}
                </div>
                {onTestTool && server.status === 'connected' && (
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={(e) => {
                      e.stopPropagation();
                      onTestTool(tool);
                    }}
                    className="ml-2 flex-shrink-0"
                  >
                    <Zap className="h-4 w-4" />
                  </Button>
                )}
              </div>
            ))}
            {tools.length > 5 && (
              <p className="text-xs text-theme-tertiary text-center py-2">
                +{tools.length - 5} more tools
              </p>
            )}
          </div>
        </div>
      )}

      {/* Actions */}
      <div className="flex items-center gap-2 pt-4 border-t border-theme">
        <Button
          variant="ghost"
          size="sm"
          onClick={(e) => {
            e.stopPropagation();
            onClick?.();
          }}
          className="ml-auto flex items-center gap-1"
        >
          View Details
          <ChevronRight className="h-4 w-4" />
        </Button>
      </div>
    </Card>
  );
};

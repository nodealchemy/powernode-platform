import { useState } from 'react';
import { AlertCircle, Zap, Package, FileText, ExternalLink, Plug, PlugZap, Trash2, RefreshCw, Settings, Server, Clock } from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import type { McpServer, McpTool } from '@/pages/app/ai/McpBrowserPage';

export interface McpServerCardProps {
  server: McpServer;
  tools: McpTool[];
  onTestTool?: (tool: McpTool) => void;
  onClick?: () => void;
  onConnect?: (serverId: string) => Promise<void>;
  onDisconnect?: (serverId: string) => Promise<void>;
  onDelete?: (serverId: string) => void;
  onEdit?: (server: McpServer) => void;
  onRefreshCapabilities?: (serverId: string) => Promise<void>;
}

export const McpServerCard: React.FC<McpServerCardProps> = ({
  server,
  tools,
  onTestTool,
  onClick: _onClick,
  onConnect,
  onDisconnect,
  onDelete,
  onEdit,
  onRefreshCapabilities
}) => {
  const [connecting, setConnecting] = useState(false);
  const [disconnecting, setDisconnecting] = useState(false);
  const [refreshing, setRefreshing] = useState(false);

  const handleConnect = async (e: React.MouseEvent) => {
    e.stopPropagation();
    if (!onConnect) return;
    setConnecting(true);
    try {
      await onConnect(server.id);
    } finally {
      setConnecting(false);
    }
  };

  const handleDisconnect = async (e: React.MouseEvent) => {
    e.stopPropagation();
    if (!onDisconnect) return;
    setDisconnecting(true);
    try {
      await onDisconnect(server.id);
    } finally {
      setDisconnecting(false);
    }
  };

  const handleRefresh = async (e: React.MouseEvent) => {
    e.stopPropagation();
    if (!onRefreshCapabilities) return;
    setRefreshing(true);
    try {
      await onRefreshCapabilities(server.id);
    } finally {
      setRefreshing(false);
    }
  };

  const getStatusColor = () => {
    switch (server.status) {
      case 'connected': return 'bg-theme-success';
      case 'connecting': return 'bg-theme-warning';
      case 'error': return 'bg-theme-error';
      default: return 'bg-theme-tertiary';
    }
  };

  const getStatusText = () => {
    switch (server.status) {
      case 'connected': return 'Connected';
      case 'connecting': return 'Connecting...';
      case 'disconnected': return 'Disconnected';
      case 'error': return 'Error';
      default: return 'Unknown';
    }
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
    return 'Just now';
  };

  const isConnected = server.status === 'connected';
  const isConnecting = server.status === 'connecting' || connecting;

  return (
    <Card className="overflow-hidden hover:shadow-lg transition-shadow">
      {/* Header with status indicator */}
      <div className="p-4 border-b border-theme">
        <div className="flex items-start gap-3">
          {/* Server Icon with Status Indicator */}
          <div className="relative">
            <div className={`w-12 h-12 rounded-lg flex items-center justify-center text-2xl ${
              isConnected ? 'bg-theme-success bg-opacity-10' :
              server.status === 'error' ? 'bg-theme-error bg-opacity-10' :
              'bg-theme-surface'
            }`}>
              {server.metadata?.icon || <Server className="h-6 w-6 text-theme-tertiary" />}
            </div>
            {/* Status dot */}
            <div className={`absolute -bottom-1 -right-1 w-4 h-4 rounded-full border-2 border-theme-bg ${getStatusColor()}`} />
          </div>

          {/* Server Info */}
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-2">
              <h3 className="font-semibold text-theme-primary truncate">{server.name}</h3>
              {server.metadata?.url && (
                <a
                  href={server.metadata.url}
                  target="_blank"
                  rel="noopener noreferrer"
                  onClick={(e) => e.stopPropagation()}
                  className="text-theme-tertiary hover:text-theme-interactive-primary flex-shrink-0"
                >
                  <ExternalLink className="h-4 w-4" />
                </a>
              )}
            </div>
            <div className="flex items-center gap-2 mt-1">
              <Badge variant="outline" size="sm">
                {server.connection_type.toUpperCase()}
              </Badge>
              <span className="text-xs text-theme-tertiary">v{server.version}</span>
            </div>
          </div>

          {/* Status Badge */}
          <Badge
            variant={isConnected ? 'success' : server.status === 'error' ? 'danger' : 'outline'}
            size="sm"
          >
            {getStatusText()}
          </Badge>
        </div>

        {/* Description */}
        {server.description && (
          <p className="text-sm text-theme-secondary mt-3 line-clamp-2">{server.description}</p>
        )}
      </div>

      {/* Error Message */}
      {server.status === 'error' && server.error_message && (
        <div className="px-4 py-3 bg-theme-error bg-opacity-5 border-b border-theme-error border-opacity-20">
          <div className="flex items-start gap-2 text-theme-error text-sm">
            <AlertCircle className="h-4 w-4 flex-shrink-0 mt-0.5" />
            <span className="line-clamp-2">{server.error_message}</span>
          </div>
        </div>
      )}

      {/* Stats & Capabilities */}
      <div className="p-4 bg-theme-surface bg-opacity-50">
        <div className="grid grid-cols-3 gap-4 text-center">
          <div>
            <div className="flex items-center justify-center gap-1 text-theme-tertiary mb-1">
              <Zap className="h-3 w-3" />
              <span className="text-xs">Tools</span>
            </div>
            <p className="text-lg font-bold text-theme-primary">{server.tools_count}</p>
          </div>
          <div>
            <div className="flex items-center justify-center gap-1 text-theme-tertiary mb-1">
              <Package className="h-3 w-3" />
              <span className="text-xs">Resources</span>
            </div>
            <p className="text-lg font-bold text-theme-primary">{server.resources_count}</p>
          </div>
          <div>
            <div className="flex items-center justify-center gap-1 text-theme-tertiary mb-1">
              <FileText className="h-3 w-3" />
              <span className="text-xs">Prompts</span>
            </div>
            <p className="text-lg font-bold text-theme-primary">{server.prompts_count}</p>
          </div>
        </div>

        {/* Last Connected */}
        {server.last_connected_at && (
          <div className="flex items-center justify-center gap-1 mt-3 text-xs text-theme-tertiary">
            <Clock className="h-3 w-3" />
            <span>Last active {formatTimestamp(server.last_connected_at)}</span>
          </div>
        )}
      </div>

      {/* Tools Preview */}
      {tools.length > 0 && isConnected && (
        <div className="px-4 py-3 border-t border-theme">
          <div className="flex items-center justify-between mb-2">
            <span className="text-xs font-medium text-theme-tertiary uppercase tracking-wider">Available Tools</span>
            {tools.length > 3 && (
              <span className="text-xs text-theme-interactive-primary">+{tools.length - 3} more</span>
            )}
          </div>
          <div className="flex flex-wrap gap-1">
            {tools.slice(0, 3).map(tool => (
              <button
                key={tool.id}
                onClick={(e) => {
                  e.stopPropagation();
                  onTestTool?.(tool);
                }}
                className="inline-flex items-center gap-1 px-2 py-1 text-xs bg-theme-interactive-primary bg-opacity-10 text-theme-interactive-primary rounded hover:bg-opacity-20 transition-colors"
                title={tool.description || tool.name}
              >
                <Zap className="h-3 w-3" />
                {tool.name}
              </button>
            ))}
          </div>
        </div>
      )}

      {/* Action Bar */}
      <div className="px-4 py-3 bg-theme-surface border-t border-theme">
        <div className="flex items-center gap-2">
          {/* Primary Action - Connect/Disconnect */}
          {isConnected ? (
            <Button
              variant="outline"
              size="sm"
              onClick={handleDisconnect}
              disabled={disconnecting}
            >
              <Plug className="h-4 w-4 mr-1.5" />
              {disconnecting ? 'Disconnecting...' : 'Disconnect'}
            </Button>
          ) : (
            <Button
              variant="primary"
              size="sm"
              onClick={handleConnect}
              disabled={isConnecting}
            >
              <PlugZap className="h-4 w-4 mr-1.5" />
              {isConnecting ? 'Connecting...' : 'Connect'}
            </Button>
          )}

          {/* Spacer */}
          <div className="flex-1" />

          {/* Refresh - only when connected */}
          {isConnected && onRefreshCapabilities && (
            <Button
              variant="outline"
              size="sm"
              onClick={handleRefresh}
              disabled={refreshing}
              title="Refresh tools & capabilities"
            >
              <RefreshCw className={`h-4 w-4 ${refreshing ? 'animate-spin' : ''}`} />
            </Button>
          )}

          {/* Edit */}
          {onEdit && (
            <Button
              variant="outline"
              size="sm"
              onClick={(e) => {
                e.stopPropagation();
                onEdit(server);
              }}
              title="Edit server settings"
            >
              <Settings className="h-4 w-4" />
            </Button>
          )}

          {/* Delete */}
          {onDelete && (
            <Button
              variant="outline"
              size="sm"
              onClick={(e) => {
                e.stopPropagation();
                onDelete(server.id);
              }}
              title="Delete server"
              className="text-theme-error hover:bg-theme-error hover:bg-opacity-10"
            >
              <Trash2 className="h-4 w-4" />
            </Button>
          )}
        </div>
      </div>
    </Card>
  );
};

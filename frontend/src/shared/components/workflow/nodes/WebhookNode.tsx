import React from 'react';
import { Handle, Position, NodeProps } from '@xyflow/react';
import { Send, Globe, Lock } from 'lucide-react';

export const WebhookNode: React.FC<NodeProps<any>> = ({ 
  data, 
  selected 
}) => {
  const getWebhookIcon = () => {
    if (data.configuration?.authentication?.type && data.configuration.authentication.type !== 'none') {
      return <Lock className="h-4 w-4" />;
    }
    if (data.configuration?.method === 'GET') {
      return <Globe className="h-4 w-4" />;
    }
    return <Send className="h-4 w-4" />;
  };

  const getWebhookLabel = () => {
    const config = data.configuration;
    if (!config) return 'Webhook';

    const method = config.method || 'POST';
    const hasAuth = config.authentication?.type && config.authentication.type !== 'none';
    
    if (hasAuth) {
      return `${method} (Authenticated)`;
    }
    return `${method} Request`;
  };

  const getStatusColor = () => {
    const config = data.configuration;
    if (!config?.url) return 'bg-theme-surface0';
    
    if (config.authentication?.type && config.authentication.type !== 'none') {
      return 'bg-theme-info';
    }
    return 'bg-emerald-500';
  };

  const getBorderColor = () => {
    const config = data.configuration;
    if (!config?.url) return 'border-theme-muted';
    
    if (config.authentication?.type && config.authentication.type !== 'none') {
      return 'border-theme-info';
    }
    return 'border-emerald-500';
  };

  const getMethodColor = () => {
    switch (data.configuration?.method) {
      case 'GET':
        return 'text-theme-success';
      case 'POST':
        return 'text-theme-info';
      case 'PUT':
        return 'text-theme-warning';
      case 'PATCH':
        return 'text-theme-interactive-primary';
      case 'DELETE':
        return 'text-theme-danger';
      default:
        return 'text-theme-info';
    }
  };

  const formatTimeout = () => {
    const seconds = data.configuration?.timeoutSeconds;
    if (!seconds) return null;
    
    if (seconds < 60) {
      return `${seconds}s timeout`;
    }
    const minutes = Math.floor(seconds / 60);
    return `${minutes}m timeout`;
  };

  return (
    <div className={`
      relative bg-theme-surface border-2 rounded-lg p-4 w-48 shadow-lg
      ${selected ? 'border-theme-interactive-primary ring-2 ring-theme-interactive-primary/20' : getBorderColor()}
      hover:shadow-xl transition-all duration-200
    `}>
      {/* Input Handle - orientation-aware */}
      <Handle
        type="target"
        position={data.handleOrientation === 'horizontal' ? Position.Left : Position.Top}
        className={`w-3 h-3 ${getStatusColor().replace('bg-', 'bg-')} border-2 border-theme-surface`}
        style={data.handleOrientation === 'horizontal' ? { left: -6 } : { top: -6 }}
      />

      {/* Header */}
      <div className="flex items-center gap-3 mb-3">
        <div className={`w-8 h-8 ${getStatusColor()} rounded-lg flex items-center justify-center text-white`}>
          {getWebhookIcon()}
        </div>
        <div className="flex-1 min-w-0">
          <h3 className="font-semibold text-theme-primary truncate">
            {data.name || 'Webhook'}
          </h3>
          <p className={`text-xs font-medium ${getMethodColor()}`}>
            {getWebhookLabel()}
          </p>
        </div>
      </div>

      {/* Description */}
      {data.description && (
        <p className="text-sm text-theme-primary mb-3 line-clamp-2">
          {data.description}
        </p>
      )}

      {/* Configuration Details */}
      <div className="space-y-2">
        {data.configuration?.url && (
          <div className="text-xs">
            <span className="text-theme-muted">URL:</span>
            <span className="ml-1 text-theme-secondary font-mono">
              {data.configuration.url.length > 30 
                ? `${data.configuration.url.substring(0, 30)}...`
                : data.configuration.url
              }
            </span>
          </div>
        )}

        {data.configuration?.authentication?.type && data.configuration.authentication.type !== 'none' && (
          <div className="text-xs">
            <span className="text-theme-muted">Auth:</span>
            <span className="ml-1 text-theme-info font-semibold">
              {data.configuration.authentication.type.toUpperCase()}
            </span>
          </div>
        )}

        {data.configuration?.retryAttempts && data.configuration.retryAttempts > 0 && (
          <div className="text-xs">
            <span className="text-theme-muted">Retries:</span>
            <span className="ml-1 text-theme-secondary">
              {data.configuration.retryAttempts}
            </span>
          </div>
        )}

        {formatTimeout() && (
          <div className="text-xs">
            <span className="text-theme-muted">Timeout:</span>
            <span className="ml-1 text-theme-secondary">
              {formatTimeout()}
            </span>
          </div>
        )}
      </div>

      {/* Status Indicator */}
      <div className="absolute top-2 right-2">
        <div className={`w-2 h-2 ${getStatusColor()} rounded-full animate-pulse`} />
      </div>

      {/* Security Badge */}
      {data.configuration?.authentication?.type && data.configuration.authentication.type !== 'none' && (
        <div className="absolute -top-1 -right-1">
          <Lock className="h-3 w-3 text-theme-info" />
        </div>
      )}

      {/* Success Output Handle - orientation-aware */}
      <Handle
        type="source"
        position={data.handleOrientation === 'horizontal' ? Position.Right : Position.Bottom}
        id="success"
        className={`w-3 h-3 ${getStatusColor().replace('bg-', 'bg-')} border-2 border-theme-surface`}
        style={data.handleOrientation === 'horizontal' ? { right: -6, top: '40%' } : { bottom: -6, left: '40%' }}
      />

      {/* Error Output Handle - orientation-aware */}
      <Handle
        type="source"
        position={data.handleOrientation === 'horizontal' ? Position.Right : Position.Bottom}
        id="error"
        className="w-3 h-3 bg-theme-danger border-2 border-theme-surface"
        style={data.handleOrientation === 'horizontal' ? { right: -6, top: '60%' } : { bottom: -6, left: '60%' }}
      />
    </div>
  );
};
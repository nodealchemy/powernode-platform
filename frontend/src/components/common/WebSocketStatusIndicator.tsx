import React from 'react';
import { useWebSocketConnection } from '../../hooks/useWebSocketConnection';

interface WebSocketStatusIndicatorProps {
  showDetails?: boolean;
  className?: string;
}

export const WebSocketStatusIndicator: React.FC<WebSocketStatusIndicatorProps> = ({ 
  showDetails = false, 
  className = "" 
}) => {
  const { 
    status, 
    isConnected, 
    lastConnected, 
    reconnectAttempts, 
    latency, 
    error,
    connect,
    disconnect,
    ping,
    getConnectionQuality 
  } = useWebSocketConnection();

  const getStatusConfig = () => {
    switch (status) {
      case 'connected':
        return {
          dotColor: 'bg-theme-success',
          textColor: 'text-theme-success',
          label: 'Real-time',
          description: 'Real-time connection active'
        };
      case 'connecting':
        return {
          dotColor: 'bg-theme-warning animate-pulse',
          textColor: 'text-theme-warning',
          label: 'Connecting',
          description: 'Establishing connection...'
        };
      case 'reconnecting':
        return {
          dotColor: 'bg-theme-warning animate-pulse',
          textColor: 'text-theme-warning',
          label: 'Reconnecting',
          description: `Reconnecting... (${reconnectAttempts}/5)`
        };
      case 'error':
        return {
          dotColor: 'bg-theme-error',
          textColor: 'text-theme-error',
          label: 'Error',
          description: error || 'Connection error'
        };
      case 'disconnected':
      default:
        return {
          dotColor: 'bg-theme-tertiary',
          textColor: 'text-theme-secondary',
          label: 'Offline',
          description: 'Real-time connection inactive'
        };
    }
  };

  const config = getStatusConfig();
  const connectionQuality = getConnectionQuality();

  const formatLatency = (ms: number | null) => {
    if (ms === null) return 'N/A';
    // Round to nearest integer for cleaner display
    return `${Math.round(ms)}ms`;
  };

  const getQualityColor = (quality: string) => {
    switch (quality) {
      case 'excellent': return 'text-theme-success';
      case 'good': return 'text-theme-info';
      case 'fair': return 'text-theme-warning';
      case 'poor': return 'text-theme-error';
      default: return 'text-theme-secondary';
    }
  };

  if (!showDetails) {
    // Compact indicator matching Analytics Dashboard design
    return (
      <div className={`flex items-center space-x-2 ${className}`}>
        <div 
          className={`w-2 h-2 rounded-full ${config.dotColor}`}
          title={config.description}
        />
        <span className={`text-xs ${config.textColor}`}>
          {config.label}
        </span>
      </div>
    );
  }

  // Detailed status panel
  return (
    <div className={`card-theme rounded-lg p-4 ${className}`}>
      <div className="flex items-center justify-between mb-3">
        <h3 className="font-medium text-theme-primary">WebSocket Connection</h3>
        <div className="flex items-center space-x-2">
          <div className={`w-2 h-2 rounded-full ${config.dotColor}`} />
          <span className={`text-sm ${config.textColor}`}>
            {config.label}
          </span>
        </div>
      </div>

      <div className="space-y-2 text-sm">
        <div className="flex justify-between">
          <span className="text-theme-secondary">Status:</span>
          <span className="text-theme-primary">{config.description}</span>
        </div>
        
        {isConnected && (
          <>
            <div className="flex justify-between">
              <span className="text-theme-secondary">Connection Quality:</span>
              <span className={`capitalize ${getQualityColor(connectionQuality)}`}>
                {connectionQuality}
              </span>
            </div>
            <div className="flex justify-between">
              <span className="text-theme-secondary">Latency:</span>
              <span className="text-theme-primary">{formatLatency(latency)}</span>
            </div>
            {lastConnected && (
              <div className="flex justify-between">
                <span className="text-theme-secondary">Connected At:</span>
                <span className="text-theme-primary">{lastConnected.toLocaleString()}</span>
              </div>
            )}
          </>
        )}

        {status === 'reconnecting' && (
          <div className="flex justify-between">
            <span className="text-theme-secondary">Reconnect Attempts:</span>
            <span className="text-theme-primary">{reconnectAttempts} of 5</span>
          </div>
        )}

        {error && (
          <div className="mt-2 p-2 bg-theme-error-background border border-theme-error rounded text-xs text-theme-error">
            {error}
          </div>
        )}
      </div>

      <div className="flex justify-end space-x-2 mt-4 pt-3 border-t border-theme-light">
        <button
          onClick={ping}
          disabled={!isConnected}
          className="px-3 py-1 text-xs bg-blue-100 dark:bg-blue-900/20 text-blue-700 dark:text-blue-400 rounded hover:bg-blue-200 dark:hover:bg-blue-900/30 disabled:opacity-50 disabled:cursor-not-allowed"
        >
          Test Connection
        </button>
        <button
          onClick={isConnected ? disconnect : connect}
          className={`px-3 py-1 text-xs rounded ${
            isConnected 
              ? 'bg-theme-error-background text-theme-error hover:bg-theme-error-background' 
              : 'bg-theme-success-background text-theme-success hover:bg-theme-success-background'
          }`}
        >
          {isConnected ? 'Disconnect' : 'Connect'}
        </button>
      </div>
    </div>
  );
};
import React from 'react';
import { useWebSocket } from '@/shared/hooks/useWebSocket';

interface WebSocketStatusIndicatorProps {
  showDetails?: boolean;
  className?: string;
}

export const WebSocketStatusIndicator: React.FC<WebSocketStatusIndicatorProps> = ({ 
WebSocketStatusIndicator.displayName = 'WebSocketStatusIndicator';
  showDetails = false, 
  className = "" 
}) => {
  const { 
    isConnected, 
    lastConnected, 
    error
  } = useWebSocket();

  const getStatusConfig = () => {
    if (isConnected) {
      return {
        dotColor: 'bg-theme-success',
        textColor: 'text-theme-success',
        label: 'Real-time',
        description: 'Real-time connection active'
      };
    } else if (error) {
      return {
        dotColor: 'bg-theme-error',
        textColor: 'text-theme-error',
        label: 'Error',
        description: error
      };
    } else {
      return {
        dotColor: 'bg-theme-tertiary',
        textColor: 'text-theme-secondary',
        label: 'Offline',
        description: 'Real-time connection inactive'
      };
    }
  };

  const config = getStatusConfig();

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
        
        {isConnected && lastConnected && (
          <div className="flex justify-between">
            <span className="text-theme-secondary">Connected At:</span>
            <span className="text-theme-primary">{lastConnected.toLocaleString()}</span>
          </div>
        )}

        {error && (
          <div className="mt-2 p-2 bg-theme-error-background border border-theme-error rounded text-xs text-theme-error">
            {error}
          </div>
        )}
      </div>
    </div>
  );
};
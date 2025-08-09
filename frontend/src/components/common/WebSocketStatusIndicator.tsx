import React, { useState } from 'react';
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
  
  const [showTooltip, setShowTooltip] = useState(false);
  const [tooltipTimeoutId, setTooltipTimeoutId] = useState<NodeJS.Timeout | null>(null);

  const getStatusConfig = () => {
    switch (status) {
      case 'connected':
        return {
          color: 'text-green-500',
          bgColor: 'bg-green-100 hover:bg-green-200',
          icon: '●',
          label: 'Connected',
          description: 'Real-time connection active'
        };
      case 'connecting':
        return {
          color: 'text-yellow-500',
          bgColor: 'bg-yellow-100 hover:bg-yellow-200',
          icon: '◐',
          label: 'Connecting',
          description: 'Establishing connection...'
        };
      case 'reconnecting':
        return {
          color: 'text-orange-500',
          bgColor: 'bg-orange-100 hover:bg-orange-200',
          icon: '◒',
          label: 'Reconnecting',
          description: `Reconnecting... (${reconnectAttempts}/5)`
        };
      case 'error':
        return {
          color: 'text-red-500',
          bgColor: 'bg-red-100 hover:bg-red-200',
          icon: '✗',
          label: 'Error',
          description: error || 'Connection error'
        };
      case 'disconnected':
      default:
        return {
          color: 'text-gray-500',
          bgColor: 'bg-gray-100 hover:bg-gray-200',
          icon: '○',
          label: 'Disconnected',
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
      case 'excellent': return 'text-green-600';
      case 'good': return 'text-blue-600';
      case 'fair': return 'text-yellow-600';
      case 'poor': return 'text-red-600';
      default: return 'text-gray-600';
    }
  };

  const handleClick = () => {
    if (status === 'disconnected' || status === 'error') {
      connect();
    } else if (status === 'connected') {
      ping(); // Test connection
    }
  };

  if (!showDetails) {
    // Compact indicator for header
    return (
      <div className="relative">
        <button
          onClick={handleClick}
          onMouseEnter={() => {
            if (tooltipTimeoutId) {
              clearTimeout(tooltipTimeoutId);
              setTooltipTimeoutId(null);
            }
            setShowTooltip(true);
          }}
          onMouseLeave={() => {
            const timeoutId = setTimeout(() => setShowTooltip(false), 100);
            setTooltipTimeoutId(timeoutId);
          }}
          className={`p-2 rounded-md transition-colors ${config.bgColor} ${className}`}
          title={config.description}
        >
          <div className="flex items-center space-x-1">
            <span className={`text-lg ${config.color}`}>{config.icon}</span>
          </div>
        </button>

        {showTooltip && (
          <div 
            className="absolute top-full right-0 mt-2 w-64 bg-white border border-gray-200 rounded-lg shadow-lg z-[9999] p-3"
            onMouseEnter={() => {
              if (tooltipTimeoutId) {
                clearTimeout(tooltipTimeoutId);
                setTooltipTimeoutId(null);
              }
            }}
            onMouseLeave={() => {
              const timeoutId = setTimeout(() => setShowTooltip(false), 100);
              setTooltipTimeoutId(timeoutId);
            }}
          >
            <div className="text-sm">
              <div className="flex items-center justify-between mb-2">
                <span className="font-medium">WebSocket Status</span>
                <span className={`text-xs px-2 py-1 rounded ${config.color} ${config.bgColor}`}>
                  {config.label}
                </span>
              </div>
              
              {isConnected && (
                <>
                  <div className="flex justify-between text-xs text-gray-600 mb-1">
                    <span>Latency:</span>
                    <span className={getQualityColor(connectionQuality)}>
                      {formatLatency(latency)} ({connectionQuality})
                    </span>
                  </div>
                  {lastConnected && (
                    <div className="flex justify-between text-xs text-gray-600 mb-1">
                      <span>Connected:</span>
                      <span>{lastConnected.toLocaleTimeString()}</span>
                    </div>
                  )}
                </>
              )}
              
              {error && (
                <div className="text-xs text-red-600 mt-1">
                  {error}
                </div>
              )}

              {status === 'reconnecting' && (
                <div className="text-xs text-orange-600 mt-1">
                  Attempt {reconnectAttempts} of 5
                </div>
              )}

              <div className="flex justify-between mt-2 pt-2 border-t border-gray-100">
                <button
                  onClick={(e) => {
                    e.stopPropagation();
                    ping();
                  }}
                  disabled={!isConnected}
                  className="text-xs text-blue-600 hover:text-blue-800 disabled:text-gray-400"
                >
                  Test
                </button>
                <button
                  onClick={(e) => {
                    e.stopPropagation();
                    if (isConnected) {
                      disconnect();
                    } else {
                      connect();
                    }
                  }}
                  className="text-xs text-blue-600 hover:text-blue-800"
                >
                  {isConnected ? 'Disconnect' : 'Connect'}
                </button>
              </div>
            </div>
          </div>
        )}
      </div>
    );
  }

  // Detailed status panel
  return (
    <div className={`bg-white border border-gray-200 rounded-lg p-4 ${className}`}>
      <div className="flex items-center justify-between mb-3">
        <h3 className="font-medium text-gray-900">WebSocket Connection</h3>
        <div className="flex items-center space-x-2">
          <span className={`text-lg ${config.color}`}>{config.icon}</span>
          <span className={`text-sm px-2 py-1 rounded ${config.color} ${config.bgColor}`}>
            {config.label}
          </span>
        </div>
      </div>

      <div className="space-y-2 text-sm">
        <div className="flex justify-between">
          <span className="text-gray-600">Status:</span>
          <span>{config.description}</span>
        </div>
        
        {isConnected && (
          <>
            <div className="flex justify-between">
              <span className="text-gray-600">Connection Quality:</span>
              <span className={`capitalize ${getQualityColor(connectionQuality)}`}>
                {connectionQuality}
              </span>
            </div>
            <div className="flex justify-between">
              <span className="text-gray-600">Latency:</span>
              <span>{formatLatency(latency)}</span>
            </div>
            {lastConnected && (
              <div className="flex justify-between">
                <span className="text-gray-600">Connected At:</span>
                <span>{lastConnected.toLocaleString()}</span>
              </div>
            )}
          </>
        )}

        {status === 'reconnecting' && (
          <div className="flex justify-between">
            <span className="text-gray-600">Reconnect Attempts:</span>
            <span>{reconnectAttempts} of 5</span>
          </div>
        )}

        {error && (
          <div className="mt-2 p-2 bg-red-50 border border-red-200 rounded text-xs text-red-600">
            {error}
          </div>
        )}
      </div>

      <div className="flex justify-end space-x-2 mt-4 pt-3 border-t border-gray-100">
        <button
          onClick={ping}
          disabled={!isConnected}
          className="px-3 py-1 text-xs bg-blue-100 text-blue-700 rounded hover:bg-blue-200 disabled:opacity-50 disabled:cursor-not-allowed"
        >
          Test Connection
        </button>
        <button
          onClick={isConnected ? disconnect : connect}
          className={`px-3 py-1 text-xs rounded ${
            isConnected 
              ? 'bg-red-100 text-red-700 hover:bg-red-200' 
              : 'bg-green-100 text-green-700 hover:bg-green-200'
          }`}
        >
          {isConnected ? 'Disconnect' : 'Connect'}
        </button>
      </div>
    </div>
  );
};
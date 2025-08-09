import React from 'react';
import { WebSocketStatusIndicator } from '../common/WebSocketStatusIndicator';
import { useWebSocketConnection } from '../../hooks/useWebSocketConnection';

export const WebSocketTestPage: React.FC = () => {
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

  return (
    <div className="max-w-4xl mx-auto p-6 space-y-6">
      <h1 className="text-2xl font-bold text-theme-primary">WebSocket Connection Test</h1>
      
      {/* Compact Header-style Indicator */}
      <div className="card-theme p-4 rounded-lg">
        <h2 className="text-lg font-medium text-theme-primary mb-3">Analytics Dashboard Style Indicator</h2>
        <div className="flex items-center space-x-4">
          <span className="text-theme-secondary">Status in Header:</span>
          <WebSocketStatusIndicator />
        </div>
      </div>

      {/* Detailed Status Panel */}
      <div className="card-theme p-4 rounded-lg">
        <h2 className="text-lg font-medium text-theme-primary mb-3">Detailed Status Panel</h2>
        <WebSocketStatusIndicator showDetails={true} />
      </div>

      {/* Raw Connection Data */}
      <div className="card-theme p-4 rounded-lg">
        <h2 className="text-lg font-medium text-theme-primary mb-3">Raw Connection Data</h2>
        <div className="grid grid-cols-2 gap-4 text-sm">
          <div className="text-theme-primary">
            <strong>Status:</strong> <span className="font-mono text-theme-secondary">{status}</span>
          </div>
          <div className="text-theme-primary">
            <strong>Connected:</strong> <span className="font-mono text-theme-secondary">{isConnected ? 'Yes' : 'No'}</span>
          </div>
          <div className="text-theme-primary">
            <strong>Latency:</strong> <span className="font-mono text-theme-secondary">{latency ? `${latency}ms` : 'N/A'}</span>
          </div>
          <div className="text-theme-primary">
            <strong>Quality:</strong> <span className="font-mono text-theme-secondary">{getConnectionQuality()}</span>
          </div>
          <div className="text-theme-primary">
            <strong>Reconnect Attempts:</strong> <span className="font-mono text-theme-secondary">{reconnectAttempts}</span>
          </div>
          <div className="text-theme-primary">
            <strong>Last Connected:</strong> <span className="font-mono text-theme-secondary">{lastConnected?.toLocaleTimeString() || 'Never'}</span>
          </div>
        </div>
        
        {error && (
          <div className="mt-4 p-3 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded">
            <strong className="text-red-800 dark:text-red-400">Error:</strong>
            <p className="text-red-600 dark:text-red-400 text-sm mt-1">{error}</p>
          </div>
        )}
      </div>

      {/* Manual Controls */}
      <div className="card-theme p-4 rounded-lg">
        <h2 className="text-lg font-medium text-theme-primary mb-3">Manual Controls</h2>
        <div className="flex space-x-2">
          <button
            onClick={connect}
            disabled={isConnected || status === 'connecting'}
            className="btn-theme bg-theme-success text-theme-success px-4 py-2 disabled:opacity-50 disabled:cursor-not-allowed"
          >
            Connect
          </button>
          <button
            onClick={disconnect}
            disabled={!isConnected}
            className="btn-theme bg-theme-error text-theme-error px-4 py-2 disabled:opacity-50 disabled:cursor-not-allowed"
          >
            Disconnect
          </button>
          <button
            onClick={ping}
            disabled={!isConnected}
            className="btn-theme btn-theme-primary px-4 py-2 disabled:opacity-50 disabled:cursor-not-allowed"
          >
            Ping Test
          </button>
        </div>
      </div>

      {/* Instructions */}
      <div className="bg-blue-50 dark:bg-blue-900/20 p-4 rounded-lg border border-blue-200 dark:border-blue-800">
        <h3 className="font-medium text-blue-900 dark:text-blue-400 mb-2">Instructions</h3>
        <ul className="text-blue-800 dark:text-blue-300 text-sm space-y-1">
          <li>• The header indicator uses the same design as the Analytics Dashboard</li>
          <li>• Shows status with colored dot and label (Real-time, Offline, Connecting, etc.)</li>
          <li>• The detailed panel shows comprehensive connection information</li>
          <li>• Connection automatically starts when user is authenticated</li>
          <li>• Use manual controls to test connection lifecycle</li>
        </ul>
      </div>
    </div>
  );
};
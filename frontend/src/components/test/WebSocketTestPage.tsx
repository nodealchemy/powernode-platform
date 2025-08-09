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
      <h1 className="text-2xl font-bold text-gray-900">WebSocket Connection Test</h1>
      
      {/* Compact Header-style Indicator */}
      <div className="bg-white p-4 rounded-lg border">
        <h2 className="text-lg font-medium mb-3">Header-style Indicator</h2>
        <div className="flex items-center space-x-4">
          <span>Status in Header:</span>
          <WebSocketStatusIndicator />
        </div>
      </div>

      {/* Detailed Status Panel */}
      <div className="bg-white p-4 rounded-lg border">
        <h2 className="text-lg font-medium mb-3">Detailed Status Panel</h2>
        <WebSocketStatusIndicator showDetails={true} />
      </div>

      {/* Raw Connection Data */}
      <div className="bg-white p-4 rounded-lg border">
        <h2 className="text-lg font-medium mb-3">Raw Connection Data</h2>
        <div className="grid grid-cols-2 gap-4 text-sm">
          <div>
            <strong>Status:</strong> <span className="font-mono">{status}</span>
          </div>
          <div>
            <strong>Connected:</strong> <span className="font-mono">{isConnected ? 'Yes' : 'No'}</span>
          </div>
          <div>
            <strong>Latency:</strong> <span className="font-mono">{latency ? `${latency}ms` : 'N/A'}</span>
          </div>
          <div>
            <strong>Quality:</strong> <span className="font-mono">{getConnectionQuality()}</span>
          </div>
          <div>
            <strong>Reconnect Attempts:</strong> <span className="font-mono">{reconnectAttempts}</span>
          </div>
          <div>
            <strong>Last Connected:</strong> <span className="font-mono">{lastConnected?.toLocaleTimeString() || 'Never'}</span>
          </div>
        </div>
        
        {error && (
          <div className="mt-4 p-3 bg-red-50 border border-red-200 rounded">
            <strong className="text-red-800">Error:</strong>
            <p className="text-red-600 text-sm mt-1">{error}</p>
          </div>
        )}
      </div>

      {/* Manual Controls */}
      <div className="bg-white p-4 rounded-lg border">
        <h2 className="text-lg font-medium mb-3">Manual Controls</h2>
        <div className="flex space-x-2">
          <button
            onClick={connect}
            disabled={isConnected || status === 'connecting'}
            className="px-4 py-2 bg-green-600 text-white rounded hover:bg-green-700 disabled:opacity-50 disabled:cursor-not-allowed"
          >
            Connect
          </button>
          <button
            onClick={disconnect}
            disabled={!isConnected}
            className="px-4 py-2 bg-red-600 text-white rounded hover:bg-red-700 disabled:opacity-50 disabled:cursor-not-allowed"
          >
            Disconnect
          </button>
          <button
            onClick={ping}
            disabled={!isConnected}
            className="px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed"
          >
            Ping Test
          </button>
        </div>
      </div>

      {/* Instructions */}
      <div className="bg-blue-50 p-4 rounded-lg border border-blue-200">
        <h3 className="font-medium text-blue-900 mb-2">Instructions</h3>
        <ul className="text-blue-800 text-sm space-y-1">
          <li>• The header indicator shows a compact status with tooltip on hover</li>
          <li>• The detailed panel shows comprehensive connection information</li>
          <li>• Connection automatically starts when user is authenticated</li>
          <li>• Hover over the header indicator to see connection details</li>
          <li>• Use manual controls to test connection lifecycle</li>
        </ul>
      </div>
    </div>
  );
};
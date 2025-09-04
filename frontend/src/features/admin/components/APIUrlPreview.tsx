import React from 'react';

interface APIUrlPreviewProps {
  urls: {
    base_url: string;
    api_url: string;
    websocket_url: string;
    frontend_url: string;
    generated_at: string;
    proxy_detected: boolean;
  };
}

const APIUrlPreview: React.FC<APIUrlPreviewProps> = ({ urls }) => {
  const copyToClipboard = (text: string, label: string) => {
    navigator.clipboard.writeText(text);
    // Could trigger a notification here
    console.log(`Copied ${label}: ${text}`);
  };

  const urlConfig = [
    {
      label: 'Base URL',
      value: urls.base_url,
      description: 'Root URL for the application',
      usage: 'Used as the base for all other URLs',
      example: null
    },
    {
      label: 'Frontend URL',
      value: urls.frontend_url,
      description: 'React application URL',
      usage: 'Where users access the web interface',
      example: `${urls.frontend_url}/dashboard`
    },
    {
      label: 'API URL',
      value: urls.api_url,
      description: 'Rails API endpoint base',
      usage: 'Base URL for all API requests',
      example: `${urls.api_url}/users`
    },
    {
      label: 'WebSocket URL',
      value: urls.websocket_url,
      description: 'ActionCable WebSocket endpoint',
      usage: 'Real-time communication channel',
      example: `${urls.websocket_url}/cable`
    }
  ];

  return (
    <div className="bg-theme-surface rounded-lg p-6">
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-lg font-medium text-theme-primary">
          Generated API URLs
        </h3>
        {urls.proxy_detected && (
          <span className="px-2 py-1 text-xs bg-theme-success/20 text-theme-success rounded">
            Via Proxy
          </span>
        )}
      </div>

      <div className="space-y-4">
        {urlConfig.map((config) => (
          <div key={config.label} className="border border-theme rounded-lg p-4">
            <div className="flex items-start justify-between">
              <div className="flex-1">
                <div className="flex items-center space-x-2 mb-2">
                  <h4 className="text-sm font-medium text-theme-primary">
                    {config.label}
                  </h4>
                  <button
                    onClick={() => copyToClipboard(config.value, config.label)}
                    className="text-theme-secondary hover:text-theme-primary transition-colors"
                    title="Copy to clipboard"
                  >
                    <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z" />
                    </svg>
                  </button>
                </div>
                <p className="font-mono text-sm text-theme-primary mb-2 break-all">
                  {config.value}
                </p>
                <p className="text-xs text-theme-secondary mb-1">
                  {config.description}
                </p>
                <p className="text-xs text-theme-secondary">
                  <span className="font-medium">Usage:</span> {config.usage}
                </p>
                {config.example && (
                  <p className="text-xs text-theme-secondary mt-1">
                    <span className="font-medium">Example:</span>{' '}
                    <code className="font-mono text-theme-info">{config.example}</code>
                  </p>
                )}
              </div>
            </div>
          </div>
        ))}
      </div>

      {/* Client Configuration Example */}
      <div className="mt-6 p-4 bg-theme-background rounded-lg">
        <h4 className="text-sm font-medium text-theme-secondary mb-3">
          Client Configuration Example
        </h4>
        <pre className="text-xs font-mono text-theme-primary overflow-x-auto">
{`// Frontend API client configuration
const apiClient = axios.create({
  baseURL: '${urls.api_url}',
  headers: {
    'Content-Type': 'application/json',
  },
});

// WebSocket connection
const cable = ActionCable.createConsumer('${urls.websocket_url}/cable');

// Frontend navigation
window.location.href = '${urls.frontend_url}/dashboard';`}
        </pre>
      </div>

      {/* Reverse Proxy Path Mapping Info */}
      <div className="mt-4 p-3 bg-theme-info/10 border border-theme-info rounded-md">
        <h4 className="text-xs font-medium text-theme-info mb-2">
          Reverse Proxy URL Routing
        </h4>
        <p className="text-xs text-theme-info">
          The reverse proxy routes requests based on URL paths:
        </p>
        <ul className="mt-2 text-xs text-theme-info space-y-1">
          <li>• <code>/*</code> → Frontend (React app at {urls.frontend_url})</li>
          <li>• <code>/api/v1/*</code> → Backend API (Rails at {urls.api_url})</li>
          <li>• <code>/cable</code> → WebSocket (ActionCable at {urls.websocket_url}/cable)</li>
        </ul>
        <p className="text-xs text-theme-info mt-2">
          All traffic goes through the same proxy endpoint ({urls.base_url}) and is routed internally.
        </p>
      </div>

      {/* Generation Timestamp */}
      <div className="mt-4 text-xs text-theme-secondary">
        Generated at: {new Date(urls.generated_at).toLocaleString()}
      </div>
    </div>
  );
};

export default APIUrlPreview;
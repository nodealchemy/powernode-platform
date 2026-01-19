
import { ProxyDetectionResult } from '@/shared/services/settings/proxySettingsApi';

interface ProxyDetectionStatusProps {
  detection: ProxyDetectionResult | null;
  onRefresh: () => void;
}

export const ProxyDetectionStatus: React.FC<ProxyDetectionStatusProps> = ({ detection, onRefresh }) => {
  if (!detection) {
    return (
      <div className="bg-theme-surface rounded-lg p-6">
        <div className="flex items-center justify-between mb-4">
          <h3 className="text-lg font-medium text-theme-primary">Proxy Detection Status</h3>
          <button
            onClick={onRefresh}
            className="text-theme-primary hover:text-theme-primary/80 transition-colors"
          >
            <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
            </svg>
          </button>
        </div>
        <p className="text-theme-secondary">Loading detection status...</p>
      </div>
    );
  }

  const getProxyStatus = () => {
    if (!detection.proxy_detected) {
      return {
        label: 'No Proxy Detected',
        color: 'text-theme-secondary',
        bgColor: 'bg-theme-muted',
        description: 'Direct connection detected - no reverse proxy headers found'
      };
    }

    const hasApiPath = detection.proxy_context.forwarded_path?.includes('/api/v1');
    const hasFrontendMapping = !detection.proxy_context.forwarded_path || detection.proxy_context.forwarded_path === '/';

    if (hasApiPath) {
      return {
        label: 'API Proxy Detected',
        color: 'text-theme-success',
        bgColor: 'bg-theme-success',
        description: 'Reverse proxy detected with /api/v1/* path mapping'
      };
    } else if (hasFrontendMapping) {
      return {
        label: 'Frontend Proxy Detected',
        color: 'text-theme-info',
        bgColor: 'bg-theme-info',
        description: 'Reverse proxy detected with /* frontend mapping'
      };
    } else {
      return {
        label: 'Proxy Detected',
        color: 'text-theme-primary',
        bgColor: 'bg-theme-primary',
        description: 'Reverse proxy headers detected in request'
      };
    }
  };

  const status = getProxyStatus();

  return (
    <div className="bg-theme-surface rounded-lg p-6">
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-lg font-medium text-theme-primary">Proxy Detection Status</h3>
        <button
          onClick={onRefresh}
          className="text-theme-primary hover:text-theme-primary/80 transition-colors"
        >
          <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
          </svg>
        </button>
      </div>

      {/* Status Badge */}
      <div className="mb-6">
        <div className="flex items-center space-x-3">
          <span className={`inline-flex items-center px-3 py-1 rounded-full text-sm font-medium ${status.bgColor}/20 ${status.color}`}>
            <span className={`w-2 h-2 rounded-full ${status.bgColor} mr-2`}></span>
            {status.label}
          </span>
          <span className="text-sm text-theme-secondary">
            {status.description}
          </span>
        </div>
      </div>

      {/* Proxy Context */}
      {detection.proxy_detected && detection.proxy_context && (
        <div className="mb-6">
          <h4 className="text-sm font-medium text-theme-secondary mb-3">Detected Proxy Context</h4>
          <div className="space-y-2">
            {Object.entries(detection.proxy_context).map(([key, value]) => (
              <div key={key} className="flex items-start">
                <span className="text-xs font-mono text-theme-secondary w-40">
                  {key.replace(/_/g, ' ').replace(/\b\w/g, l => l.toUpperCase())}:
                </span>
                <span className="text-sm font-mono text-theme-primary break-all">
                  {String(value) || '-'}
                </span>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Request Headers */}
      <div>
        <h4 className="text-sm font-medium text-theme-secondary mb-3">Request Headers</h4>
        <div className="bg-theme-background rounded-md p-4">
          <div className="space-y-2">
            {Object.entries(detection.request_headers).map(([header, value]) => (
              <div key={header} className="flex items-start">
                <span className="text-xs font-mono text-theme-secondary w-40">{header}:</span>
                <span className="text-sm font-mono text-theme-primary break-all">
                  {String(value) || '-'}
                </span>
              </div>
            ))}
          </div>
        </div>
      </div>

      {/* URL Path Mapping Info */}
      <div className="mt-6 p-4 bg-theme-info/10 border border-theme-info rounded-md">
        <h4 className="text-sm font-medium text-theme-info mb-2">
          Typical Reverse Proxy URL Mapping
        </h4>
        <ul className="text-sm text-theme-info space-y-1">
          <li>• <code className="font-mono">{'/*'}</code> → Frontend application (React)</li>
          <li>• <code className="font-mono">{'/api/v1/*'}</code> → Backend API (Rails)</li>
          <li>• <code className="font-mono">/cable</code> → WebSocket connection (ActionCable)</li>
          <li>• <code className="font-mono">{'/webhooks/*'}</code> → Webhook endpoints</li>
        </ul>
        <p className="text-xs text-theme-info mt-2">
          The same reverse proxy handles both frontend and backend routing based on URL paths.
        </p>
      </div>

      {/* Last Detection */}
      <div className="mt-4 text-xs text-theme-secondary">
        Last detected: {new Date(detection.detection_timestamp).toLocaleString()}
      </div>
    </div>
  );
};


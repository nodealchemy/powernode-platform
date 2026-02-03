import React, { useState } from 'react';
import { useNotifications } from '@/shared/hooks/useNotifications';
import proxySettingsApi, { ProxyTestResult } from '@/shared/services/settings/proxySettingsApi';

interface ProxyTestConnectionProps {
  onTestComplete: (result: ProxyTestResult) => void;
}

export const ProxyTestConnection: React.FC<ProxyTestConnectionProps> = ({ onTestComplete }) => {
  const { showNotification } = useNotifications();
  const showSuccess = (msg: string) => showNotification(msg, 'success');
  const showError = (msg: string) => showNotification(msg, 'error');
  const [testing, setTesting] = useState(false);
  const [testResult, setTestResult] = useState<ProxyTestResult | null>(null);
  const [testHeaders, setTestHeaders] = useState({
    'X-Forwarded-Host': '',
    'X-Forwarded-Proto': 'https',
    'X-Forwarded-Port': '',
    'X-Forwarded-Path': '/api/v1',
    'X-Forwarded-For': '',
    'X-Real-IP': ''
  });

  const handleTest = async () => {
    setTesting(true);
    try {
      // Filter out empty headers
      const headersToTest = Object.entries(testHeaders)
        .filter(([_, value]) => value)
        .reduce((acc, [key, value]) => ({ ...acc, [key]: value }), {});

      const result = await proxySettingsApi.testHeaders(headersToTest);
      setTestResult(result);
      onTestComplete(result);
      showSuccess('Proxy test completed successfully');
    } catch (_error) {
      showError('Failed to test proxy configuration');
    } finally {
      setTesting(false);
    }
  };

  const handlePresetConfig = (type: 'nginx' | 'traefik' | 'cloudflare') => {
    const presets = {
      nginx: {
        'X-Forwarded-Host': 'app.example.com',
        'X-Forwarded-Proto': 'https',
        'X-Forwarded-Port': '443',
        'X-Forwarded-Path': '/api/v1',
        'X-Forwarded-For': '192.168.1.100',
        'X-Real-IP': '192.168.1.100'
      },
      traefik: {
        'X-Forwarded-Host': 'app.example.com',
        'X-Forwarded-Proto': 'https',
        'X-Forwarded-Port': '443',
        'X-Forwarded-Path': '/api/v1',
        'X-Forwarded-For': '10.0.0.1',
        'X-Real-IP': '10.0.0.1'
      },
      cloudflare: {
        'X-Forwarded-Host': 'app.example.com',
        'X-Forwarded-Proto': 'https',
        'X-Forwarded-Port': '',
        'X-Forwarded-Path': '/api/v1',
        'X-Forwarded-For': '172.70.0.1',
        'X-Real-IP': '172.70.0.1'
      }
    };
    setTestHeaders(presets[type]);
    showSuccess(`Loaded ${type} preset configuration`);
  };

  return (
    <div className="space-y-6">
      {/* Test Configuration */}
      <div className="bg-theme-surface rounded-lg p-6">
        <h3 className="text-lg font-medium text-theme-primary mb-4">
          Test Proxy Headers
        </h3>
        
        {/* Preset Configurations */}
        <div className="mb-4">
          <p className="text-sm text-theme-secondary mb-2">Load preset configuration:</p>
          <div className="flex space-x-2">
            <button
              onClick={() => handlePresetConfig('nginx')}
              className="px-3 py-1 text-sm bg-theme-muted text-theme-primary rounded hover:bg-theme-muted/80 transition-colors"
            >
              Nginx
            </button>
            <button
              onClick={() => handlePresetConfig('traefik')}
              className="px-3 py-1 text-sm bg-theme-muted text-theme-primary rounded hover:bg-theme-muted/80 transition-colors"
            >
              Traefik
            </button>
            <button
              onClick={() => handlePresetConfig('cloudflare')}
              className="px-3 py-1 text-sm bg-theme-muted text-theme-primary rounded hover:bg-theme-muted/80 transition-colors"
            >
              CloudFlare
            </button>
          </div>
        </div>

        {/* Header Inputs */}
        <div className="space-y-3">
          {Object.entries(testHeaders).map(([header, value]) => (
            <div key={header}>
              <label className="block text-sm font-medium text-theme-secondary mb-1">
                {header}
              </label>
              <input
                type="text"
                value={value}
                onChange={(e) => setTestHeaders({ ...testHeaders, [header]: e.target.value })}
                placeholder={header === 'X-Forwarded-Path' ? '/api/v1 or /' : 'Enter value'}
                className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:ring-2 focus:ring-theme-primary focus:border-theme-primary"
              />
              {header === 'X-Forwarded-Path' && (
                <p className="text-xs text-theme-secondary mt-1">
                  Use <code>/api/v1</code> for API requests or <code>/</code> for frontend
                </p>
              )}
            </div>
          ))}
        </div>

        {/* Test Button */}
        <button
          onClick={handleTest}
          disabled={testing}
          className="mt-4 w-full px-4 py-2 bg-theme-interactive-primary text-white rounded-md hover:bg-theme-interactive-primary-hover disabled:bg-theme-interactive-primary-disabled disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
        >
          {testing ? 'Testing...' : 'Test Configuration'}
        </button>
      </div>

      {/* Test Result */}
      {testResult && (
        <div className="bg-theme-surface rounded-lg p-6">
          <h3 className="text-lg font-medium text-theme-primary mb-4">
            Test Results
          </h3>

          {/* Validation Status */}
          {testResult.validation && (
            <div className="mb-4">
              <div className={`p-3 rounded-md ${
                testResult.validation.valid 
                  ? 'bg-theme-success/10 border border-theme-success' 
                  : 'bg-theme-error/10 border border-theme-error'
              }`}>
                <p className={`text-sm font-medium ${
                  testResult.validation.valid ? 'text-theme-success' : 'text-theme-error'
                }`}>
                  {testResult.validation.valid ? '✓ Valid configuration' : '✗ Invalid configuration'}
                </p>
                {testResult.validation.errors.length > 0 && (
                  <ul className="mt-2 text-sm text-theme-error">
                    {testResult.validation.errors.map((error: string, idx: number) => (
                      <li key={idx}>• {error}</li>
                    ))}
                  </ul>
                )}
                {testResult.validation.trusted && (
                  <p className="mt-2 text-sm text-theme-success">
                    ✓ Host is in trusted list
                  </p>
                )}
              </div>
            </div>
          )}

          {/* Generated URLs */}
          {testResult.generated_urls && (
            <div>
              <h4 className="text-sm font-medium text-theme-secondary mb-3">
                Generated URLs (based on test headers)
              </h4>
              <div className="bg-theme-background rounded-md p-4">
                <div className="space-y-2">
                  <div>
                    <span className="text-xs text-theme-secondary">Base URL:</span>
                    <p className="font-mono text-sm text-theme-primary">{testResult.generated_urls.base_url}</p>
                  </div>
                  <div>
                    <span className="text-xs text-theme-secondary">API URL:</span>
                    <p className="font-mono text-sm text-theme-primary">{testResult.generated_urls.api_url}</p>
                  </div>
                  <div>
                    <span className="text-xs text-theme-secondary">WebSocket URL:</span>
                    <p className="font-mono text-sm text-theme-primary">{testResult.generated_urls.websocket_url}</p>
                  </div>
                  <div>
                    <span className="text-xs text-theme-secondary">Frontend URL:</span>
                    <p className="font-mono text-sm text-theme-primary">{testResult.generated_urls.frontend_url}</p>
                  </div>
                </div>
              </div>
              
              {/* URL Path Mapping Explanation */}
              <div className="mt-4 p-3 bg-theme-info/10 border border-theme-info rounded-md">
                <p className="text-sm text-theme-info">
                  ℹ️ URLs are generated based on proxy headers. In a typical setup:
                </p>
                <ul className="mt-2 text-sm text-theme-info">
                  <li>• Frontend requests (/) are served directly</li>
                  <li>• API requests (/api/v1/*) are proxied to the Rails backend</li>
                  <li>• WebSocket connections (/cable) are proxied with protocol upgrade</li>
                </ul>
              </div>
            </div>
          )}

          {/* Test Timestamp */}
          <div className="mt-4 text-xs text-theme-secondary">
            Tested at: {new Date(testResult.test_performed_at).toLocaleString()}
          </div>
        </div>
      )}
    </div>
  );
};


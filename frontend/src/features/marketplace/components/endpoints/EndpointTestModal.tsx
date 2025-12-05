import React, { useState, useRef } from 'react';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { Badge } from '@/shared/components/ui/Badge';
import { AppEndpoint } from '../../types';
import { getHttpMethodThemeClass } from '../../utils/themeHelpers';
import { X, Play, Copy, Plus, Minus, Clock, CheckCircle, XCircle } from 'lucide-react';
import { useNotifications } from '@/shared/hooks/useNotifications';

interface EndpointTestModalProps {
  isOpen: boolean;
  onClose: () => void;
  endpoint: AppEndpoint | null;
  onTest: (endpointId: string, testData?: any, testHeaders?: Record<string, string>) => Promise<any>;
}

interface TestResult {
  call_id: string;
  status_code: number;
  response_time_ms: number;
  test_result: any;
  error?: string;
}

const getStatusColor = (status: number): string => {
  if (status >= 200 && status < 300) return 'text-theme-success';
  if (status >= 400 && status < 500) return 'text-theme-warning';
  if (status >= 500) return 'text-theme-error';
  return 'text-theme-secondary';
};

export const EndpointTestModal: React.FC<EndpointTestModalProps> = ({
  isOpen,
  onClose,
  endpoint,
  onTest
}) => {
  const [testing, setTesting] = useState(false);
  const [testResult, setTestResult] = useState<TestResult | null>(null);
  const [activeTab, setActiveTab] = useState<'request' | 'response'>('request');
  const [requestBody, setRequestBody] = useState('{\n  \n}');
  const [testHeaders, setTestHeaders] = useState<Record<string, string>>({});
  const [newHeader, setNewHeader] = useState({ key: '', value: '' });
  const responseRef = useRef<HTMLPreElement>(null);
  const { showNotification } = useNotifications();

  const handleTest = async () => {
    if (!endpoint) return;

    setTesting(true);
    setTestResult(null);
    setActiveTab('response');

    try {
      let testData;
      if (requestBody.trim() && requestBody.trim() !== '{\n  \n}') {
        try {
          testData = JSON.parse(requestBody);
        } catch (e) {
          showNotification('Invalid JSON in request body', 'error');
          setTesting(false);
          return;
        }
      }

      const result = await onTest(endpoint.id, testData, testHeaders);
      setTestResult(result);
      showNotification('Test completed successfully', 'success');
    } catch (error) {
      showNotification('Test failed', 'error');
    } finally {
      setTesting(false);
    }
  };

  const addHeader = () => {
    if (newHeader.key && newHeader.value) {
      setTestHeaders(prev => ({ ...prev, [newHeader.key]: newHeader.value }));
      setNewHeader({ key: '', value: '' });
    }
  };

  const removeHeader = (key: string) => {
    setTestHeaders(prev => {
      const headers = { ...prev };
      if (Object.prototype.hasOwnProperty.call(headers, key)) {
        delete headers[key as keyof typeof headers];
      }
      return headers;
    });
  };

  const copyResponse = async () => {
    if (testResult && responseRef.current) {
      try {
        await navigator.clipboard.writeText(responseRef.current.textContent || '');
        showNotification('Response copied to clipboard', 'success');
      } catch (error) {
        showNotification('Failed to copy response', 'error');
      }
    }
  };

  const formatJson = (obj: any): string => {
    try {
      return JSON.stringify(obj, null, 2);
    } catch {
      return String(obj);
    }
  };

  const prettifyJson = () => {
    try {
      const parsed = JSON.parse(requestBody);
      setRequestBody(JSON.stringify(parsed, null, 2));
    } catch (e) {
      showNotification('Invalid JSON format', 'error');
    }
  };

  const tabs = [
    { id: 'request', label: 'Request', icon: '📤' },
    { id: 'response', label: 'Response', icon: '📥' }
  ] as const;

  if (!endpoint) return null;

  return (
    <Modal isOpen={isOpen} onClose={onClose} title="Test API Endpoint" maxWidth="xl">
      <div className="space-y-6">
        <div className="flex items-center justify-between pb-4 border-b border-theme">
          <div>
            <h2 className="text-xl font-semibold text-theme-primary">Test API Endpoint</h2>
            <div className="flex items-center space-x-3 mt-2">
              <Badge className={getHttpMethodThemeClass(endpoint.http_method)}>
                {endpoint.http_method}
              </Badge>
              <span className="text-sm font-mono text-theme-secondary bg-theme-surface px-2 py-1 rounded">
                {endpoint.full_path}
              </span>
            </div>
          </div>
          <Button variant="ghost" size="sm" onClick={onClose}>
            <X className="w-4 h-4" />
          </Button>
        </div>

        {/* Endpoint Info */}
        <div className="bg-theme-surface rounded-lg p-4">
          <h3 className="font-medium text-theme-primary mb-2">{endpoint.name}</h3>
          {endpoint.description && (
            <p className="text-sm text-theme-secondary mb-3">{endpoint.description}</p>
          )}
          <div className="flex items-center space-x-4 text-sm text-theme-tertiary">
            <span>🔒 {endpoint.requires_auth ? 'Auth Required' : 'Public'}</span>
            <span>📝 v{endpoint.version}</span>
            {endpoint.analytics && (
              <span>📊 {endpoint.analytics.total_calls} total calls</span>
            )}
          </div>
        </div>

        {/* Test Button */}
        <div className="flex justify-center">
          <Button
            onClick={handleTest}
            disabled={testing}
            className="flex items-center space-x-2 px-6 py-3"
          >
            {testing ? (
              <>
                <LoadingSpinner size="sm" />
                <span>Testing...</span>
              </>
            ) : (
              <>
                <Play className="w-4 h-4" />
                <span>Run Test</span>
              </>
            )}
          </Button>
        </div>

        {/* Tabs */}
        <div className="border-b border-theme">
          <div className="flex space-x-8 -mb-px overflow-x-auto scrollbar-hide">
            {tabs.map((tab) => (
              <button
                key={tab.id}
                type="button"
                onClick={() => setActiveTab(tab.id)}
                className={`flex items-center space-x-2 py-2 px-1 border-b-2 font-medium text-sm ${
                  activeTab === tab.id
                    ? 'border-theme-link text-theme-link'
                    : 'border-transparent text-theme-secondary hover:text-theme-primary'
                }`}
              >
                <span className="text-base">{tab.icon}</span>
                <span>{tab.label}</span>
              </button>
            ))}
          </div>
        </div>

        {/* Request Tab */}
        {activeTab === 'request' && (
          <div className="space-y-6">
            {/* Headers */}
            <div>
              <h3 className="text-lg font-medium text-theme-primary mb-4">Test Headers</h3>
              
              {Object.entries(testHeaders).map(([key, value]) => (
                <div key={key} className="flex items-center space-x-2 mb-2">
                  <input
                    type="text"
                    value={key}
                    readOnly
                    className="flex-1 px-3 py-2 border border-theme rounded-lg bg-theme-surface text-theme-primary"
                  />
                  <input
                    type="text"
                    value={value}
                    readOnly
                    className="flex-1 px-3 py-2 border border-theme rounded-lg bg-theme-surface text-theme-primary"
                  />
                  <Button
                    type="button"
                    variant="outline"
                    size="sm"
                    onClick={() => removeHeader(key)}
                  >
                    <Minus className="w-4 h-4" />
                  </Button>
                </div>
              ))}

              <div className="flex items-center space-x-2">
                <input
                  type="text"
                  placeholder="Header name (e.g., Content-Type)"
                  value={newHeader.key}
                  onChange={(e) => setNewHeader(prev => ({ ...prev, key: e.target.value }))}
                  className="flex-1 px-3 py-2 border border-theme rounded-lg bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
                />
                <input
                  type="text"
                  placeholder="Header value (e.g., application/json)"
                  value={newHeader.value}
                  onChange={(e) => setNewHeader(prev => ({ ...prev, value: e.target.value }))}
                  className="flex-1 px-3 py-2 border border-theme rounded-lg bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
                />
                <Button type="button" variant="outline" size="sm" onClick={addHeader}>
                  <Plus className="w-4 h-4" />
                </Button>
              </div>
            </div>

            {/* Request Body */}
            {endpoint.http_method !== 'GET' && endpoint.http_method !== 'HEAD' && (
              <div>
                <div className="flex items-center justify-between mb-4">
                  <h3 className="text-lg font-medium text-theme-primary">Request Body (JSON)</h3>
                  <Button type="button" variant="outline" size="sm" onClick={prettifyJson}>
                    Format JSON
                  </Button>
                </div>
                <textarea
                  value={requestBody}
                  onChange={(e) => setRequestBody(e.target.value)}
                  rows={12}
                  className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-surface text-theme-primary font-mono text-sm focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
                  placeholder="Enter JSON request body..."
                />
              </div>
            )}

            {/* Default Headers Info */}
            <div className="bg-theme-info-background border border-theme-info-border rounded-lg p-4">
              <div className="flex items-start space-x-3">
                <span className="text-lg">💡</span>
                <div>
                  <h4 className="font-medium text-theme-primary">Default Headers</h4>
                  <p className="text-sm text-theme-secondary mt-1">
                    The following headers will be included automatically: Authorization (if required), 
                    Content-Type (for POST/PUT/PATCH), User-Agent.
                  </p>
                </div>
              </div>
            </div>
          </div>
        )}

        {/* Response Tab */}
        {activeTab === 'response' && (
          <div className="space-y-6">
            {testing && (
              <div className="text-center py-12">
                <LoadingSpinner size="lg" />
                <p className="text-theme-secondary mt-4">Testing endpoint...</p>
              </div>
            )}

            {!testing && !testResult && (
              <div className="text-center py-12">
                <div className="w-16 h-16 bg-theme-interactive-primary/10 rounded-full flex items-center justify-center mx-auto mb-4">
                  <span className="text-2xl">🧪</span>
                </div>
                <h3 className="text-lg font-semibold text-theme-primary mb-2">
                  Ready to Test
                </h3>
                <p className="text-theme-secondary">
                  Configure your request parameters and click "Run Test" to see the results
                </p>
              </div>
            )}

            {testResult && (
              <>
                {/* Result Summary */}
                <div className="bg-theme-surface rounded-lg p-4">
                  <div className="flex items-center justify-between mb-4">
                    <h3 className="text-lg font-medium text-theme-primary">Test Results</h3>
                    <Button variant="outline" size="sm" onClick={copyResponse}>
                      <Copy className="w-4 h-4 mr-2" />
                      Copy Response
                    </Button>
                  </div>

                  <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-4">
                    <div className="flex items-center space-x-3">
                      {testResult.status_code >= 200 && testResult.status_code < 300 ? (
                        <CheckCircle className="w-5 h-5 text-theme-success" />
                      ) : (
                        <XCircle className="w-5 h-5 text-theme-error" />
                      )}
                      <div>
                        <div className="text-sm text-theme-tertiary">Status Code</div>
                        <div className={`font-semibold ${getStatusColor(testResult.status_code)}`}>
                          {testResult.status_code}
                        </div>
                      </div>
                    </div>

                    <div className="flex items-center space-x-3">
                      <Clock className="w-5 h-5 text-theme-secondary" />
                      <div>
                        <div className="text-sm text-theme-tertiary">Response Time</div>
                        <div className="font-semibold text-theme-primary">
                          {testResult.response_time_ms}ms
                        </div>
                      </div>
                    </div>

                    <div className="flex items-center space-x-3">
                      <span className="text-lg">🆔</span>
                      <div>
                        <div className="text-sm text-theme-tertiary">Call ID</div>
                        <div className="font-mono text-xs text-theme-secondary">
                          {testResult.call_id.substring(0, 8)}...
                        </div>
                      </div>
                    </div>
                  </div>

                  {testResult.error && (
                    <div className="bg-theme-error-background border border-theme-error-border rounded-lg p-3 mb-4">
                      <h4 className="font-medium text-theme-error mb-1">Error</h4>
                      <p className="text-sm text-theme-error">{testResult.error}</p>
                    </div>
                  )}
                </div>

                {/* Response Body */}
                <div>
                  <h3 className="text-lg font-medium text-theme-primary mb-4">Response Body</h3>
                  <div className="bg-theme-surface rounded-lg p-4 border border-theme">
                    <pre
                      ref={responseRef}
                      className="text-sm font-mono text-theme-primary whitespace-pre-wrap overflow-x-auto max-h-96 overflow-y-auto"
                    >
                      {formatJson(testResult.test_result)}
                    </pre>
                  </div>
                </div>
              </>
            )}
          </div>
        )}

        {/* Modal Actions */}
        <div className="flex items-center justify-end space-x-3 pt-6 border-t border-theme">
          <Button variant="outline" onClick={onClose}>
            Close
          </Button>
          {testResult && (
            <Button onClick={() => setActiveTab('request')}>
              Test Again
            </Button>
          )}
        </div>
      </div>
    </Modal>
  );
};
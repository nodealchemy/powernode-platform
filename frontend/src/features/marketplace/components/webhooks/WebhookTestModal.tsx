import React, { useState } from 'react';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { useAppWebhooks } from '../../hooks/useWebhooks';
import { AppWebhook } from '../../types';
import { X, Send, Copy, Eye, EyeOff } from 'lucide-react';

interface WebhookTestModalProps {
  isOpen: boolean;
  onClose: () => void;
  appId: string;
  webhook: AppWebhook;
}

interface TestResult {
  delivery_id: string;
  event_id: string;
  status: string;
  payload: any;
  response_code?: number;
  response_body?: string;
  response_time?: number;
  error_message?: string;
}

export const WebhookTestModal: React.FC<WebhookTestModalProps> = ({
  isOpen,
  onClose,
  appId,
  webhook
}) => {
  const [testing, setTesting] = useState(false);
  const [testResult, setTestResult] = useState<TestResult | null>(null);
  const [customPayload, setCustomPayload] = useState('');
  const [useCustomPayload, setUseCustomPayload] = useState(false);
  const [showResponse, setShowResponse] = useState(false);

  const { showNotification } = useNotifications();
  const { testWebhook } = useAppWebhooks(appId, {});

  const samplePayloads = {
    'subscription.created': {
      event: 'subscription.created',
      timestamp: new Date().toISOString(),
      data: {
        subscription: {
          id: 'sub_1234567890',
          app_id: appId,
          status: 'active',
          created_at: new Date().toISOString(),
          app_plan: {
            id: 'plan_123',
            name: 'Pro Plan',
            price_cents: 2999
          },
          customer: {
            id: 'cust_123',
            email: 'test@example.com',
            name: 'Test Customer'
          }
        }
      }
    },
    'payment.succeeded': {
      event: 'payment.succeeded',
      timestamp: new Date().toISOString(),
      data: {
        payment: {
          id: 'pay_1234567890',
          amount_cents: 2999,
          currency: 'USD',
          status: 'succeeded',
          subscription_id: 'sub_1234567890'
        }
      }
    },
    'app.installed': {
      event: 'app.installed',
      timestamp: new Date().toISOString(),
      data: {
        app: {
          id: appId,
          name: webhook.name,
          version: '1.0.0'
        },
        installation: {
          id: 'install_123',
          installed_at: new Date().toISOString(),
          customer: {
            id: 'cust_123',
            email: 'test@example.com'
          }
        }
      }
    }
  };

  const handleTest = async () => {
    setTesting(true);
    setTestResult(null);

    try {
      let testData = {};

      if (useCustomPayload && customPayload.trim()) {
        try {
          testData = JSON.parse(customPayload);
        } catch (error) {
          showNotification('Invalid JSON in custom payload', 'error');
          setTesting(false);
          return;
        }
      } else {
        testData = samplePayloads[webhook.event_type as keyof typeof samplePayloads] || {
          event: webhook.event_type,
          timestamp: new Date().toISOString(),
          data: { test: true }
        };
      }

      const result = await testWebhook(webhook.id, testData);
      setTestResult(result as TestResult);
      showNotification('Test webhook sent successfully!', 'success');
    } catch (error: unknown) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error occurred';
      showNotification(`Failed to test webhook: ${errorMessage}`, 'error');
      setTestResult({
        delivery_id: '',
        event_id: '',
        status: 'failed',
        payload: {},
        error_message: errorMessage
      });
    } finally {
      setTesting(false);
    }
  };

  const handleCopyPayload = (payload: string) => {
    navigator.clipboard.writeText(payload);
    showNotification('Payload copied to clipboard', 'success');
  };

  const handleLoadSamplePayload = () => {
    const sample = samplePayloads[webhook.event_type as keyof typeof samplePayloads];
    if (sample) {
      setCustomPayload(JSON.stringify(sample, null, 2));
      setUseCustomPayload(true);
    }
  };

  const getStatusBadgeVariant = (status: string): 'success' | 'warning' | 'danger' => {
    switch (status) {
      case 'delivered':
      case 'success': 
        return 'success';
      case 'pending': 
        return 'warning';
      case 'failed':
      default: 
        return 'danger';
    }
  };

  const formatResponseTime = (ms?: number) => {
    if (!ms) return 'N/A';
    if (ms < 1000) return `${ms}ms`;
    return `${(ms / 1000).toFixed(2)}s`;
  };

  return (
    <Modal 
      isOpen={isOpen} 
      onClose={onClose} 
      title="Test Webhook"
      subtitle={webhook.name}
      maxWidth="4xl"
      showCloseButton={false}
    >
      <div className="flex flex-col h-full max-h-[calc(90vh-120px)]">
        <div className="flex items-center justify-end p-4 border-b border-theme">
          <Button variant="outline" size="sm" onClick={onClose}>
            <X className="w-4 h-4" />
          </Button>
        </div>

        <div className="p-6 max-h-[calc(90vh-200px)] overflow-y-auto space-y-6">
          {/* Webhook Details */}
          <div className="bg-theme-background rounded-lg p-4">
            <h3 className="font-medium text-theme-primary mb-3">Webhook Details</h3>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4 text-sm">
              <div>
                <span className="text-theme-tertiary">URL:</span>
                <p className="font-mono text-theme-secondary break-all">{webhook.url}</p>
              </div>
              <div>
                <span className="text-theme-tertiary">Method:</span>
                <Badge variant="outline" className="ml-2">{webhook.http_method}</Badge>
              </div>
              <div>
                <span className="text-theme-tertiary">Event Type:</span>
                <p className="text-theme-secondary">{webhook.event_type}</p>
              </div>
              <div>
                <span className="text-theme-tertiary">Content Type:</span>
                <p className="text-theme-secondary">{webhook.content_type}</p>
              </div>
            </div>
          </div>

          {/* Payload Configuration */}
          <div className="space-y-4">
            <div className="flex items-center justify-between">
              <h3 className="font-medium text-theme-primary">Test Payload</h3>
              <div className="flex items-center space-x-2">
                <Button
                  variant="outline"
                  size="sm"
                  onClick={handleLoadSamplePayload}
                >
                  Load Sample
                </Button>
                <div className="flex items-center">
                  <input
                    type="checkbox"
                    id="useCustomPayload"
                    checked={useCustomPayload}
                    onChange={(e) => setUseCustomPayload(e.target.checked)}
                    className="checkbox-theme"
                  />
                  <label htmlFor="useCustomPayload" className="ml-2 text-sm text-theme-secondary">
                    Use custom payload
                  </label>
                </div>
              </div>
            </div>

            {useCustomPayload ? (
              <div>
                <textarea
                  value={customPayload}
                  onChange={(e) => setCustomPayload(e.target.value)}
                  className="input-theme w-full font-mono"
                  rows={12}
                  placeholder="Enter custom JSON payload..."
                />
                <p className="text-theme-tertiary text-sm mt-2">
                  Enter a custom JSON payload to send with the test webhook
                </p>
              </div>
            ) : (
              <div className="bg-theme-background rounded-lg p-4">
                <div className="flex items-center justify-between mb-2">
                  <span className="text-sm font-medium text-theme-primary">Default Payload Preview</span>
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={() => {
                      const sample = samplePayloads[webhook.event_type as keyof typeof samplePayloads] || {
                        event: webhook.event_type,
                        timestamp: new Date().toISOString(),
                        data: { test: true }
                      };
                      handleCopyPayload(JSON.stringify(sample, null, 2));
                    }}
                  >
                    <Copy className="w-4 h-4" />
                  </Button>
                </div>
                <pre className="text-sm text-theme-secondary font-mono whitespace-pre-wrap">
                  {JSON.stringify(
                    samplePayloads[webhook.event_type as keyof typeof samplePayloads] || {
                      event: webhook.event_type,
                      timestamp: new Date().toISOString(),
                      data: { test: true }
                    },
                    null,
                    2
                  )}
                </pre>
              </div>
            )}
          </div>

          {/* Test Results */}
          {testResult && (
            <div className="space-y-4">
              <h3 className="font-medium text-theme-primary">Test Result</h3>
              
              <div className="bg-theme-background rounded-lg p-4">
                <div className="flex items-center justify-between mb-4">
                  <div className="flex items-center space-x-3">
                    <Badge variant={getStatusBadgeVariant(testResult.status)}>
                      {testResult.status.toUpperCase()}
                    </Badge>
                    {testResult.response_code && (
                      <Badge variant="outline">
                        HTTP {testResult.response_code}
                      </Badge>
                    )}
                  </div>
                  {testResult.response_time && (
                    <span className="text-sm text-theme-secondary">
                      Response time: {formatResponseTime(testResult.response_time)}
                    </span>
                  )}
                </div>

                <div className="grid grid-cols-1 md:grid-cols-2 gap-4 text-sm">
                  <div>
                    <span className="text-theme-tertiary">Delivery ID:</span>
                    <p className="font-mono text-theme-secondary">{testResult.delivery_id || 'N/A'}</p>
                  </div>
                  <div>
                    <span className="text-theme-tertiary">Event ID:</span>
                    <p className="font-mono text-theme-secondary">{testResult.event_id || 'N/A'}</p>
                  </div>
                </div>

                {testResult.error_message && (
                  <div className="mt-4 p-3 bg-theme-error bg-opacity-10 border border-theme-error border-opacity-20 rounded">
                    <p className="text-theme-error text-sm font-medium">Error:</p>
                    <p className="text-theme-error text-sm">{testResult.error_message}</p>
                  </div>
                )}

                {testResult.response_body && (
                  <div className="mt-4">
                    <div className="flex items-center justify-between mb-2">
                      <span className="text-sm font-medium text-theme-primary">Response Body</span>
                      <div className="flex items-center space-x-2">
                        <Button
                          variant="outline"
                          size="sm"
                          onClick={() => testResult.response_body && handleCopyPayload(testResult.response_body)}
                        >
                          <Copy className="w-4 h-4" />
                        </Button>
                        <Button
                          variant="outline"
                          size="sm"
                          onClick={() => setShowResponse(!showResponse)}
                        >
                          {showResponse ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                        </Button>
                      </div>
                    </div>
                    {showResponse && (
                      <pre className="text-sm text-theme-secondary font-mono whitespace-pre-wrap bg-theme-surface p-3 rounded max-h-48 overflow-y-auto">
                        {testResult.response_body}
                      </pre>
                    )}
                  </div>
                )}
              </div>
            </div>
          )}
        </div>

        <div className="border-t border-theme p-6">
          <div className="flex items-center justify-between">
            <div className="text-sm text-theme-secondary">
              This will send a test event to your webhook endpoint
            </div>
            <div className="flex items-center space-x-3">
              <Button variant="outline" onClick={onClose}>
                Close
              </Button>
              <Button
                variant="primary"
                onClick={handleTest}
                disabled={testing}
                className="min-w-[120px]"
              >
                {testing ? (
                  <>
                    <div className="animate-spin rounded-full h-4 w-4 border-b-2 border-white mr-2"></div>
                    Testing...
                  </>
                ) : (
                  <>
                    <Send className="w-4 h-4 mr-2" />
                    Send Test
                  </>
                )}
              </Button>
            </div>
          </div>
        </div>
      </div>
    </Modal>
  );
};
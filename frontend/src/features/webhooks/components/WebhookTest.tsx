import React, { useState, useEffect } from 'react';
import { Button } from '@/shared/components/ui/Button';
import { 
  TestTube,
  Play,
  CheckCircle,
  AlertTriangle,
  Clock,
  Code,
  Activity,
  Zap,
  Globe,
  ArrowRight
} from 'lucide-react';
import webhooksApi, { WebhookEndpoint } from '@/features/webhooks/services/webhooksApi';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import CodeBlock from '@/shared/components/ui/CodeBlock';

interface WebhookTestProps {
  webhook: WebhookEndpoint;
  onSuccess: (message: string) => void;
  onError: (error: string) => void;
}

interface TestResult {
  success: boolean;
  webhook_id: string;
  test_payload: Record<string, unknown>;
  response: {
    status: number;
    response_time: number;
    success: boolean;
    response_body?: string;
  };
}

const WebhookTest: React.FC<WebhookTestProps> = ({
  webhook,
  onSuccess,
  onError
}) => {
  const [selectedEventType, setSelectedEventType] = useState(
    webhook.event_types.length > 0 ? webhook.event_types[0] : 'test.webhook'
  );
  const [loading, setLoading] = useState(false);
  const [testResult, setTestResult] = useState<TestResult | null>(null);
  const [availableEvents, setAvailableEvents] = useState<string[]>([]);

  // Load available events
  useEffect(() => {
    const loadEvents = async () => {
      try {
        const response = await webhooksApi.getAvailableEvents();
        if (response.success && response.data) {
          setAvailableEvents(response.data.events);
        }
      } catch (err) {
        // Error handled silently - events are optional
      }
    };

    loadEvents();
  }, []);

  // Handle test execution
  const handleTest = async () => {
    setLoading(true);
    setTestResult(null);

    try {
      const response = await webhooksApi.testWebhook(webhook.id, selectedEventType);
      
      if (response.success && response.data) {
        setTestResult({
          ...response.data,
          success: response.success
        });
        onSuccess(`Webhook test completed successfully with status ${response.data.response.status}`);
      } else {
        onError(response.error || 'Webhook test failed');
      }
    } catch (err) {
      onError('An unexpected error occurred during webhook test');
    } finally {
      setLoading(false);
    }
  };

  // Get status color based on HTTP status
  const getStatusColor = (status: number) => {
    if (status >= 200 && status < 300) return 'text-theme-success';
    if (status >= 400 && status < 500) return 'text-theme-warning';
    return 'text-theme-error';
  };

  // Get response time color
  const getResponseTimeColor = (ms: number) => {
    if (ms < 1000) return 'text-theme-success';
    if (ms < 3000) return 'text-theme-warning';
    return 'text-theme-error';
  };

  // Generate sample payload preview
  const generateSamplePayload = () => {
    return {
      event: {
        id: "evt_sample_" + Date.now(),
        type: selectedEventType,
        created_at: new Date().toISOString(),
        test: true
      },
      data: {
        id: "obj_sample_" + Date.now(),
        attributes: {
          message: "This is a test webhook delivery",
          timestamp: new Date().toISOString(),
          environment: "test"
        }
      },
      metadata: {
        webhook_id: webhook.id,
        delivery_attempt: 1,
        signature_version: "v1"
      }
    };
  };

  const samplePayload = generateSamplePayload();

  return (
    <div className="space-y-6">
      {/* Test Configuration */}
      <div className="bg-theme-background rounded-lg border border-theme p-4">
        <h4 className="text-lg font-semibold text-theme-primary mb-4 flex items-center gap-2">
          <TestTube className="w-5 h-5" />
          Test Configuration
        </h4>

        <div className="space-y-4">
          {/* Event Type Selection */}
          <div>
            <label htmlFor="eventType" className="block text-sm font-medium text-theme-secondary mb-2">
              Event Type
            </label>
            <select
              id="eventType"
              value={selectedEventType}
              onChange={(e) => setSelectedEventType(e.target.value)}
              className="w-full px-4 py-2 rounded-lg border border-theme bg-theme-surface text-theme-primary focus:outline-none focus:border-theme-focus"
            >
              {/* Webhook's subscribed events first */}
              {webhook.event_types.map(eventType => (
                <option key={eventType} value={eventType}>
                  {webhooksApi.formatEventType(eventType)} (subscribed)
                </option>
              ))}
              
              {/* Separator if webhook has subscribed events */}
              {webhook.event_types.length > 0 && (
                <option disabled>──────────</option>
              )}
              
              {/* All available events */}
              {availableEvents
                .filter(eventType => !webhook.event_types.includes(eventType))
                .map(eventType => (
                  <option key={eventType} value={eventType}>
                    {webhooksApi.formatEventType(eventType)}
                  </option>
                ))}
            </select>
            <p className="text-xs text-theme-secondary mt-1">
              Select the event type to test. Events marked as "subscribed" are configured for this webhook.
            </p>
          </div>

          {/* Test Button */}
          <div className="flex items-center gap-4">
            <Button onClick={handleTest} disabled={loading || webhook.status !== 'active'} variant="primary">
              {loading ? (
                <>
                  <LoadingSpinner size="sm" />
                  Testing...
                </>
              ) : (
                <>
                  <Play className="w-4 h-4" />
                  Send Test Event
                </>
              )}
            </Button>

            {webhook.status !== 'active' && (
              <div className="flex items-center gap-2 text-theme-warning">
                <AlertTriangle className="w-4 h-4" />
                <span className="text-sm">Webhook must be active to test</span>
              </div>
            )}
          </div>
        </div>
      </div>

      {/* Sample Payload Preview */}
      <div className="bg-theme-background rounded-lg border border-theme p-4">
        <h4 className="text-lg font-semibold text-theme-primary mb-4 flex items-center gap-2">
          <Code className="w-5 h-5" />
          Sample Payload
        </h4>
        <p className="text-sm text-theme-secondary mb-4">
          This is an example of the payload that will be sent to your webhook endpoint:
        </p>
        <CodeBlock
          language="json"
          code={JSON.stringify(samplePayload, null, 2)}
        />
      </div>

      {/* Test Result */}
      {testResult && (
        <div className="bg-theme-background rounded-lg border border-theme p-4">
          <h4 className="text-lg font-semibold text-theme-primary mb-4 flex items-center gap-2">
            <Activity className="w-5 h-5" />
            Test Result
          </h4>

          {/* Result Summary */}
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
            <div className="bg-theme-surface rounded-lg p-4 border border-theme">
              <div className="flex items-center gap-3">
                <div className={`p-2 rounded-lg ${
                  testResult.response.success
                    ? 'bg-theme-success bg-opacity-10'
                    : 'bg-theme-error bg-opacity-10'
                }`}>
                  {testResult.response.success ? (
                    <CheckCircle className="w-5 h-5 text-theme-success" />
                  ) : (
                    <AlertTriangle className="w-5 h-5 text-theme-error" />
                  )}
                </div>
                <div>
                  <p className="text-sm text-theme-secondary">Status</p>
                  <p className={`font-medium ${getStatusColor(testResult.response.status)}`}>
                    {testResult.response.status} {testResult.response.success ? 'Success' : 'Failed'}
                  </p>
                </div>
              </div>
            </div>

            <div className="bg-theme-surface rounded-lg p-4 border border-theme">
              <div className="flex items-center gap-3">
                <div className="p-2 rounded-lg bg-theme-interactive-primary bg-opacity-10">
                  <Clock className="w-5 h-5 text-theme-interactive-primary" />
                </div>
                <div>
                  <p className="text-sm text-theme-secondary">Response Time</p>
                  <p className={`font-medium ${getResponseTimeColor(testResult.response.response_time)}`}>
                    {testResult.response.response_time}ms
                  </p>
                </div>
              </div>
            </div>

            <div className="bg-theme-surface rounded-lg p-4 border border-theme">
              <div className="flex items-center gap-3">
                <div className="p-2 rounded-lg bg-theme-tertiary bg-opacity-10">
                  <Globe className="w-5 h-5 text-theme-tertiary" />
                </div>
                <div>
                  <p className="text-sm text-theme-secondary">Event Type</p>
                  <p className="font-medium text-theme-primary">
                    {webhooksApi.formatEventType(selectedEventType)}
                  </p>
                </div>
              </div>
            </div>
          </div>

          {/* Success/Failure Details */}
          {testResult.response.success ? (
            <div className="bg-theme-success bg-opacity-5 border border-theme-success rounded-lg p-4">
              <div className="flex items-start gap-3">
                <CheckCircle className="w-5 h-5 text-theme-success flex-shrink-0 mt-0.5" />
                <div>
                  <h5 className="font-medium text-theme-success mb-2">Test Successful</h5>
                  <p className="text-sm text-theme-secondary">
                    Your webhook endpoint responded successfully to the test event. 
                    The endpoint is configured correctly and ready to receive real webhook events.
                  </p>
                </div>
              </div>
            </div>
          ) : (
            <div className="bg-theme-error bg-opacity-5 border border-theme-error rounded-lg p-4">
              <div className="flex items-start gap-3">
                <AlertTriangle className="w-5 h-5 text-theme-error flex-shrink-0 mt-0.5" />
                <div>
                  <h5 className="font-medium text-theme-error mb-2">Test Failed</h5>
                  <p className="text-sm text-theme-secondary mb-3">
                    Your webhook endpoint did not respond successfully. Please check the following:
                  </p>
                  <ul className="text-sm text-theme-secondary space-y-1">
                    <li>• Ensure your endpoint is accessible and responding</li>
                    <li>• Check that your endpoint accepts {webhook.content_type}</li>
                    <li>• Verify your endpoint responds within {webhook.timeout_seconds} seconds</li>
                    <li>• Check your server logs for any errors</li>
                  </ul>
                </div>
              </div>
            </div>
          )}

          {/* Response Body */}
          {testResult.response.response_body && (
            <div className="mt-6">
              <h5 className="font-medium text-theme-primary mb-3">Response Body</h5>
              <div className="bg-theme-surface rounded-lg border border-theme p-3">
                <pre className="text-sm text-theme-secondary whitespace-pre-wrap break-all">
                  {testResult.response.response_body}
                </pre>
              </div>
            </div>
          )}

          {/* Request Details */}
          <div className="mt-6 pt-6 border-t border-theme">
            <h5 className="font-medium text-theme-primary mb-3">Request Details</h5>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4 text-sm">
              <div>
                <span className="font-medium text-theme-secondary">Endpoint:</span>
                <span className="ml-2 text-theme-primary break-all">{webhook.url}</span>
              </div>
              <div>
                <span className="font-medium text-theme-secondary">Method:</span>
                <span className="ml-2 text-theme-primary">POST</span>
              </div>
              <div>
                <span className="font-medium text-theme-secondary">Content-Type:</span>
                <span className="ml-2 text-theme-primary">{webhook.content_type}</span>
              </div>
              <div>
                <span className="font-medium text-theme-secondary">Timeout:</span>
                <span className="ml-2 text-theme-primary">{webhook.timeout_seconds}s</span>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Tips */}
      <div className="bg-theme-interactive-primary bg-opacity-5 border border-theme-interactive-primary rounded-lg p-4">
        <h4 className="font-medium text-theme-interactive-primary mb-3 flex items-center gap-2">
          <Zap className="w-5 h-5" />
          Testing Tips
        </h4>
        <div className="text-sm text-theme-secondary space-y-2">
          <div className="flex items-start gap-2">
            <ArrowRight className="w-4 h-4 text-theme-interactive-primary flex-shrink-0 mt-0.5" />
            <span>Use a webhook testing service like ngrok for local development</span>
          </div>
          <div className="flex items-start gap-2">
            <ArrowRight className="w-4 h-4 text-theme-interactive-primary flex-shrink-0 mt-0.5" />
            <span>Ensure your endpoint validates the webhook signature for security</span>
          </div>
          <div className="flex items-start gap-2">
            <ArrowRight className="w-4 h-4 text-theme-interactive-primary flex-shrink-0 mt-0.5" />
            <span>Return a 2xx status code to indicate successful processing</span>
          </div>
          <div className="flex items-start gap-2">
            <ArrowRight className="w-4 h-4 text-theme-interactive-primary flex-shrink-0 mt-0.5" />
            <span>Process webhooks asynchronously to avoid timeouts</span>
          </div>
        </div>
      </div>
    </div>
  );
};

export default WebhookTest;
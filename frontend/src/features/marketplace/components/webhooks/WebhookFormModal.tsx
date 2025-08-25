import React, { useState, useEffect } from 'react';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { TabContainer, TabPanel } from '@/shared/components/layout/TabContainer';
import { useNotification } from '@/shared/hooks/useNotification';
import { useAppWebhooks } from '../../hooks/useWebhooks';
import { AppWebhook, AppWebhookFormData, WebhookMethod } from '../../types';
import { Save, X, TestTube, Shield } from 'lucide-react';

interface WebhookFormModalProps {
  isOpen: boolean;
  onClose: () => void;
  appId: string;
  webhook?: AppWebhook | null;
  onSuccess: (webhook: AppWebhook) => void;
}

export const WebhookFormModal: React.FC<WebhookFormModalProps> = ({
  isOpen,
  onClose,
  appId,
  webhook,
  onSuccess
}) => {
  const [activeTab, setActiveTab] = useState('basic');
  const [submitting, setSubmitting] = useState(false);
  const [formData, setFormData] = useState<AppWebhookFormData>({
    name: '',
    description: '',
    event_type: 'subscription.created',
    url: '',
    http_method: 'POST' as WebhookMethod,
    headers: {},
    payload_template: {},
    authentication: {},
    retry_config: { max_attempts: 3, backoff_factor: 2, initial_delay: 1000 },
    is_active: true,
    timeout_seconds: 30,
    max_retries: 3,
    content_type: 'application/json',
    metadata: {}
  });
  const [errors, setErrors] = useState<Record<string, string>>({});

  const { showNotification } = useNotification();
  const { createWebhook, updateWebhook, testWebhook } = useAppWebhooks(appId, {});

  const eventTypes = [
    { value: 'app.installed', label: 'App Installed', description: 'When a user installs your app' },
    { value: 'app.uninstalled', label: 'App Uninstalled', description: 'When a user uninstalls your app' },
    { value: 'subscription.created', label: 'Subscription Created', description: 'When a new subscription is created' },
    { value: 'subscription.updated', label: 'Subscription Updated', description: 'When a subscription is modified' },
    { value: 'subscription.cancelled', label: 'Subscription Cancelled', description: 'When a subscription is cancelled' },
    { value: 'payment.succeeded', label: 'Payment Succeeded', description: 'When a payment is successfully processed' },
    { value: 'payment.failed', label: 'Payment Failed', description: 'When a payment fails' },
    { value: 'invoice.created', label: 'Invoice Created', description: 'When a new invoice is generated' },
    { value: 'invoice.paid', label: 'Invoice Paid', description: 'When an invoice is marked as paid' }
  ];

  const httpMethods: WebhookMethod[] = ['POST', 'PUT', 'PATCH'];

  const contentTypes = [
    'application/json',
    'application/x-www-form-urlencoded',
    'text/plain'
  ];

  const authTypes = [
    { value: 'none', label: 'No Authentication' },
    { value: 'bearer', label: 'Bearer Token' },
    { value: 'basic', label: 'Basic Auth' },
    { value: 'api_key', label: 'API Key' }
  ];

  // Initialize form data when webhook prop changes
  useEffect(() => {
    if (webhook) {
      setFormData({
        name: webhook.name,
        description: webhook.description || '',
        event_type: webhook.event_type,
        url: webhook.url,
        http_method: webhook.http_method,
        headers: webhook.headers || {},
        payload_template: webhook.payload_template || {},
        authentication: webhook.authentication || {},
        retry_config: webhook.retry_config || { max_attempts: 3, backoff_factor: 2, initial_delay: 1000 },
        is_active: webhook.is_active,
        timeout_seconds: webhook.timeout_seconds,
        max_retries: webhook.max_retries,
        content_type: webhook.content_type,
        metadata: webhook.metadata || {}
      });
    } else {
      // Reset form for new webhook
      setFormData({
        name: '',
        description: '',
        event_type: 'subscription.created',
        url: '',
        http_method: 'POST' as WebhookMethod,
        headers: {},
        payload_template: {},
        authentication: {},
        retry_config: { max_attempts: 3, backoff_factor: 2, initial_delay: 1000 },
        is_active: true,
        timeout_seconds: 30,
        max_retries: 3,
        content_type: 'application/json',
        metadata: {}
      });
    }
    setErrors({});
    setActiveTab('basic');
  }, [webhook]);

  const validateForm = (): boolean => {
    const newErrors: Record<string, string> = {};

    if (!formData.name.trim()) {
      newErrors.name = 'Name is required';
    }

    if (!formData.url.trim()) {
      newErrors.url = 'URL is required';
    } else {
      try {
        new URL(formData.url);
      } catch {
        newErrors.url = 'Please enter a valid URL';
      }
    }

    if (formData.timeout_seconds < 1 || formData.timeout_seconds > 300) {
      newErrors.timeout_seconds = 'Timeout must be between 1 and 300 seconds';
    }

    if (formData.max_retries < 0 || formData.max_retries > 10) {
      newErrors.max_retries = 'Max retries must be between 0 and 10';
    }

    setErrors(newErrors);
    return Object.keys(newErrors).length === 0;
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    
    if (!validateForm()) {
      showNotification('Please fix the form errors', 'error');
      return;
    }

    setSubmitting(true);
    try {
      let result: AppWebhook | null = null;
      
      if (webhook) {
        result = await updateWebhook(webhook.id, formData);
      } else {
        result = await createWebhook(formData);
      }
      
      if (result) {
        onSuccess(result);
      }
    } catch (error: any) {
      showNotification(
        webhook 
          ? `Failed to update webhook: ${error.message}`
          : `Failed to create webhook: ${error.message}`,
        'error'
      );
    } finally {
      setSubmitting(false);
    }
  };

  const handleTestWebhook = async () => {
    if (!webhook) {
      showNotification('Please save the webhook first before testing', 'warning');
      return;
    }

    try {
      const result = await testWebhook(webhook.id, { test_event: true });
      if (result) {
        showNotification(`Test webhook sent successfully. Event ID: ${result.event_id}`, 'success');
      }
    } catch (error: any) {
      showNotification(`Failed to test webhook: ${error.message}`, 'error');
    }
  };

  const handleHeadersChange = (headers: string) => {
    try {
      const parsed = headers ? JSON.parse(headers) : {};
      setFormData({ ...formData, headers: parsed });
      setErrors({ ...errors, headers: '' });
    } catch (e) {
      setErrors({ ...errors, headers: 'Invalid JSON format' });
    }
  };

  const handlePayloadChange = (payload: string) => {
    try {
      const parsed = payload ? JSON.parse(payload) : {};
      setFormData({ ...formData, payload_template: parsed });
      setErrors({ ...errors, payload_template: '' });
    } catch (e) {
      setErrors({ ...errors, payload_template: 'Invalid JSON format' });
    }
  };

  const tabs = [
    { id: 'basic', label: 'Basic Settings', icon: '⚙️' },
    { id: 'payload', label: 'Payload & Headers', icon: '📦' },
    { id: 'security', label: 'Security', icon: '🔐' },
    { id: 'advanced', label: 'Advanced', icon: '🔧' }
  ];

  return (
    <Modal 
      isOpen={isOpen} 
      onClose={onClose} 
      title={webhook ? 'Edit Webhook' : 'Create Webhook'}
      maxWidth="4xl"
      showCloseButton={false}
    >
      <div className="flex flex-col h-full max-h-[calc(90vh-120px)]">
        <div className="flex items-center justify-between p-4 border-b border-theme">
          <div>
            <p className="text-theme-secondary text-sm">
              Configure webhook to receive event notifications
            </p>
          </div>
          <div className="flex items-center space-x-2">
            {webhook && (
              <Button variant="outline" size="sm" onClick={handleTestWebhook}>
                <TestTube className="w-4 h-4 mr-2" />
                Test
              </Button>
            )}
            <Button variant="outline" size="sm" onClick={onClose}>
              <X className="w-4 h-4" />
            </Button>
          </div>
        </div>

        <form onSubmit={handleSubmit} className="flex flex-col flex-1 overflow-hidden">
          <div className="flex-1 overflow-hidden">
            <TabContainer
              tabs={tabs}
              variant="underline"
              className="h-full"
            >
              <TabPanel tabId="basic" activeTab={activeTab}>
                <div className="p-6 space-y-6">
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                    <div className="md:col-span-2">
                      <label className="block text-sm font-medium text-theme-primary mb-2">
                        Name *
                      </label>
                      <input
                        type="text"
                        value={formData.name}
                        onChange={(e) => setFormData({ ...formData, name: e.target.value })}
                        className={`input-theme w-full ${errors.name ? 'border-theme-error' : ''}`}
                        placeholder="e.g., Subscription Created Notification"
                      />
                      {errors.name && (
                        <p className="text-theme-error text-sm mt-1">{errors.name}</p>
                      )}
                    </div>

                    <div className="md:col-span-2">
                      <label className="block text-sm font-medium text-theme-primary mb-2">
                        Description
                      </label>
                      <textarea
                        value={formData.description}
                        onChange={(e) => setFormData({ ...formData, description: e.target.value })}
                        className="input-theme w-full"
                        rows={3}
                        placeholder="Optional description of what this webhook does..."
                      />
                    </div>

                    <div>
                      <label className="block text-sm font-medium text-theme-primary mb-2">
                        Event Type *
                      </label>
                      <select
                        value={formData.event_type}
                        onChange={(e) => setFormData({ ...formData, event_type: e.target.value })}
                        className="input-theme w-full"
                      >
                        {eventTypes.map((eventType) => (
                          <option key={eventType.value} value={eventType.value}>
                            {eventType.label}
                          </option>
                        ))}
                      </select>
                      <p className="text-theme-tertiary text-sm mt-1">
                        {eventTypes.find(et => et.value === formData.event_type)?.description}
                      </p>
                    </div>

                    <div>
                      <label className="block text-sm font-medium text-theme-primary mb-2">
                        HTTP Method
                      </label>
                      <select
                        value={formData.http_method}
                        onChange={(e) => setFormData({ ...formData, http_method: e.target.value as WebhookMethod })}
                        className="input-theme w-full"
                      >
                        {httpMethods.map((method) => (
                          <option key={method} value={method}>
                            {method}
                          </option>
                        ))}
                      </select>
                    </div>

                    <div className="md:col-span-2">
                      <label className="block text-sm font-medium text-theme-primary mb-2">
                        Webhook URL *
                      </label>
                      <input
                        type="url"
                        value={formData.url}
                        onChange={(e) => setFormData({ ...formData, url: e.target.value })}
                        className={`input-theme w-full ${errors.url ? 'border-theme-error' : ''}`}
                        placeholder="https://your-app.com/webhooks/powernode"
                      />
                      {errors.url && (
                        <p className="text-theme-error text-sm mt-1">{errors.url}</p>
                      )}
                    </div>

                    <div>
                      <label className="block text-sm font-medium text-theme-primary mb-2">
                        Content Type
                      </label>
                      <select
                        value={formData.content_type}
                        onChange={(e) => setFormData({ ...formData, content_type: e.target.value })}
                        className="input-theme w-full"
                      >
                        {contentTypes.map((type) => (
                          <option key={type} value={type}>
                            {type}
                          </option>
                        ))}
                      </select>
                    </div>

                    <div>
                      <div className="flex items-center">
                        <input
                          type="checkbox"
                          id="is_active"
                          checked={formData.is_active}
                          onChange={(e) => setFormData({ ...formData, is_active: e.target.checked })}
                          className="checkbox-theme"
                        />
                        <label htmlFor="is_active" className="ml-2 text-sm font-medium text-theme-primary">
                          Active
                        </label>
                      </div>
                      <p className="text-theme-tertiary text-sm mt-1">
                        Inactive webhooks will not receive events
                      </p>
                    </div>
                  </div>
                </div>
              </TabPanel>

              <TabPanel tabId="payload" activeTab={activeTab}>
                <div className="p-6 space-y-6">
                  <div>
                    <label className="block text-sm font-medium text-theme-primary mb-2">
                      Custom Headers
                    </label>
                    <textarea
                      value={JSON.stringify(formData.headers, null, 2)}
                      onChange={(e) => handleHeadersChange(e.target.value)}
                      className={`input-theme w-full font-mono ${errors.headers ? 'border-theme-error' : ''}`}
                      rows={6}
                      placeholder={`{
  "Authorization": "Bearer your-token",
  "X-Custom-Header": "value"
}`}
                    />
                    {errors.headers && (
                      <p className="text-theme-error text-sm mt-1">{errors.headers}</p>
                    )}
                    <p className="text-theme-tertiary text-sm mt-1">
                      Custom headers to include with webhook requests (JSON format)
                    </p>
                  </div>

                  <div>
                    <label className="block text-sm font-medium text-theme-primary mb-2">
                      Payload Template
                    </label>
                    <textarea
                      value={JSON.stringify(formData.payload_template, null, 2)}
                      onChange={(e) => handlePayloadChange(e.target.value)}
                      className={`input-theme w-full font-mono ${errors.payload_template ? 'border-theme-error' : ''}`}
                      rows={10}
                      placeholder={`{
  "event": "{{event_type}}",
  "data": "{{event_data}}",
  "timestamp": "{{timestamp}}",
  "app_id": "{{app_id}}"
}`}
                    />
                    {errors.payload_template && (
                      <p className="text-theme-error text-sm mt-1">{errors.payload_template}</p>
                    )}
                    <p className="text-theme-tertiary text-sm mt-1">
                      Custom payload template using handlebars syntax. Leave empty to use default payload.
                    </p>
                  </div>
                </div>
              </TabPanel>

              <TabPanel tabId="security" activeTab={activeTab}>
                <div className="p-6 space-y-6">
                  <div className="bg-theme-info bg-opacity-10 border border-theme-info border-opacity-20 rounded-lg p-4">
                    <div className="flex items-start space-x-3">
                      <Shield className="w-5 h-5 text-theme-info mt-0.5" />
                      <div>
                        <h4 className="font-medium text-theme-primary">Webhook Security</h4>
                        <p className="text-theme-secondary text-sm mt-1">
                          All webhooks are signed with a secret token. Use this to verify that webhook requests are coming from Powernode.
                        </p>
                      </div>
                    </div>
                  </div>

                  {webhook && (
                    <div>
                      <label className="block text-sm font-medium text-theme-primary mb-2">
                        Secret Token
                      </label>
                      <div className="flex items-center space-x-2">
                        <input
                          type="text"
                          value={webhook.secret_token}
                          readOnly
                          className="input-theme flex-1 font-mono"
                        />
                        <Button
                          type="button"
                          variant="outline"
                          size="sm"
                          onClick={() => {
                            navigator.clipboard.writeText(webhook.secret_token);
                            showNotification('Secret token copied to clipboard', 'success');
                          }}
                        >
                          Copy
                        </Button>
                      </div>
                      <p className="text-theme-tertiary text-sm mt-1">
                        Use this secret to verify webhook authenticity in your endpoint
                      </p>
                    </div>
                  )}

                  <div>
                    <label className="block text-sm font-medium text-theme-primary mb-2">
                      Authentication Type
                    </label>
                    <select
                      value={formData.authentication?.type || 'none'}
                      onChange={(e) => setFormData({
                        ...formData,
                        authentication: e.target.value === 'none' ? {} : { type: e.target.value }
                      })}
                      className="input-theme w-full"
                    >
                      {authTypes.map((auth) => (
                        <option key={auth.value} value={auth.value}>
                          {auth.label}
                        </option>
                      ))}
                    </select>
                  </div>

                  {formData.authentication?.type === 'bearer' && (
                    <div>
                      <label className="block text-sm font-medium text-theme-primary mb-2">
                        Bearer Token
                      </label>
                      <input
                        type="password"
                        value={formData.authentication?.token || ''}
                        onChange={(e) => setFormData({
                          ...formData,
                          authentication: { ...formData.authentication, token: e.target.value }
                        })}
                        className="input-theme w-full font-mono"
                        placeholder="your-bearer-token"
                      />
                    </div>
                  )}

                  {formData.authentication?.type === 'basic' && (
                    <div className="grid grid-cols-2 gap-4">
                      <div>
                        <label className="block text-sm font-medium text-theme-primary mb-2">
                          Username
                        </label>
                        <input
                          type="text"
                          value={formData.authentication?.username || ''}
                          onChange={(e) => setFormData({
                            ...formData,
                            authentication: { ...formData.authentication, username: e.target.value }
                          })}
                          className="input-theme w-full"
                        />
                      </div>
                      <div>
                        <label className="block text-sm font-medium text-theme-primary mb-2">
                          Password
                        </label>
                        <input
                          type="password"
                          value={formData.authentication?.password || ''}
                          onChange={(e) => setFormData({
                            ...formData,
                            authentication: { ...formData.authentication, password: e.target.value }
                          })}
                          className="input-theme w-full"
                        />
                      </div>
                    </div>
                  )}

                  {formData.authentication?.type === 'api_key' && (
                    <div className="grid grid-cols-2 gap-4">
                      <div>
                        <label className="block text-sm font-medium text-theme-primary mb-2">
                          Header Name
                        </label>
                        <input
                          type="text"
                          value={formData.authentication?.header || ''}
                          onChange={(e) => setFormData({
                            ...formData,
                            authentication: { ...formData.authentication, header: e.target.value }
                          })}
                          className="input-theme w-full"
                          placeholder="X-API-Key"
                        />
                      </div>
                      <div>
                        <label className="block text-sm font-medium text-theme-primary mb-2">
                          API Key
                        </label>
                        <input
                          type="password"
                          value={formData.authentication?.key || ''}
                          onChange={(e) => setFormData({
                            ...formData,
                            authentication: { ...formData.authentication, key: e.target.value }
                          })}
                          className="input-theme w-full font-mono"
                        />
                      </div>
                    </div>
                  )}
                </div>
              </TabPanel>

              <TabPanel tabId="advanced" activeTab={activeTab}>
                <div className="p-6 space-y-6">
                  <div className="grid grid-cols-2 gap-6">
                    <div>
                      <label className="block text-sm font-medium text-theme-primary mb-2">
                        Timeout (seconds)
                      </label>
                      <input
                        type="number"
                        min="1"
                        max="300"
                        value={formData.timeout_seconds}
                        onChange={(e) => setFormData({ ...formData, timeout_seconds: parseInt(e.target.value) })}
                        className={`input-theme w-full ${errors.timeout_seconds ? 'border-theme-error' : ''}`}
                      />
                      {errors.timeout_seconds && (
                        <p className="text-theme-error text-sm mt-1">{errors.timeout_seconds}</p>
                      )}
                      <p className="text-theme-tertiary text-sm mt-1">
                        How long to wait for a response (1-300 seconds)
                      </p>
                    </div>

                    <div>
                      <label className="block text-sm font-medium text-theme-primary mb-2">
                        Max Retries
                      </label>
                      <input
                        type="number"
                        min="0"
                        max="10"
                        value={formData.max_retries}
                        onChange={(e) => setFormData({ ...formData, max_retries: parseInt(e.target.value) })}
                        className={`input-theme w-full ${errors.max_retries ? 'border-theme-error' : ''}`}
                      />
                      {errors.max_retries && (
                        <p className="text-theme-error text-sm mt-1">{errors.max_retries}</p>
                      )}
                      <p className="text-theme-tertiary text-sm mt-1">
                        Number of retry attempts for failed deliveries (0-10)
                      </p>
                    </div>
                  </div>

                  <div>
                    <label className="block text-sm font-medium text-theme-primary mb-2">
                      Retry Configuration
                    </label>
                    <textarea
                      value={JSON.stringify(formData.retry_config, null, 2)}
                      onChange={(e) => {
                        try {
                          const parsed = JSON.parse(e.target.value);
                          setFormData({ ...formData, retry_config: parsed });
                        } catch (e) {
                          // Handle invalid JSON
                        }
                      }}
                      className="input-theme w-full font-mono"
                      rows={4}
                      placeholder={`{
  "max_attempts": 3,
  "backoff_factor": 2,
  "initial_delay": 1000
}`}
                    />
                    <p className="text-theme-tertiary text-sm mt-1">
                      Advanced retry configuration with exponential backoff
                    </p>
                  </div>
                </div>
              </TabPanel>
            </TabContainer>
          </div>

          <div className="border-t border-theme p-6">
            <div className="flex items-center justify-between">
              <div className="flex items-center space-x-4">
                <Button type="button" variant="outline" onClick={onClose}>
                  Cancel
                </Button>
              </div>
              <div className="flex items-center space-x-2">
                <Button
                  type="submit"
                  variant="primary"
                  disabled={submitting}
                  className="min-w-[120px]"
                >
                  {submitting ? (
                    <>
                      <div className="animate-spin rounded-full h-4 w-4 border-b-2 border-white mr-2"></div>
                      {webhook ? 'Updating...' : 'Creating...'}
                    </>
                  ) : (
                    <>
                      <Save className="w-4 h-4 mr-2" />
                      {webhook ? 'Update' : 'Create'} Webhook
                    </>
                  )}
                </Button>
              </div>
            </div>
          </div>
        </form>
      </div>
    </Modal>
  );
};
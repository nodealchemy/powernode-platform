import React, { useState, useEffect } from 'react';
import { Button } from '@/shared/components/ui/Button';
import {
  Webhook, Settings, AlertTriangle
} from 'lucide-react';
import { webhooksApi, DetailedWebhookEndpoint, WebhookFormData } from '@/features/webhooks/services/webhooksApi';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';

export interface ConsoleCreateWebhookModalProps {
  isOpen: boolean;
  onClose: () => void;
  onWebhookCreated: (webhook: DetailedWebhookEndpoint) => void;
}

export const ConsoleCreateWebhookModal: React.FC<ConsoleCreateWebhookModalProps> = ({
  isOpen,
  onClose,
  onWebhookCreated
}) => {
  const [formData, setFormData] = useState<WebhookFormData>(webhooksApi.getDefaultFormData());
  const [eventCategories, setEventCategories] = useState<{ [key: string]: string[] }>({});
  const [loading, setLoading] = useState(false);
  const [errors, setErrors] = useState<string[]>([]);
  const [showAdvanced, setShowAdvanced] = useState(false);

  const { showNotification } = useNotifications();

  useEffect(() => {
    if (isOpen) {
      loadAvailableEvents();
    }
  }, [isOpen]);

  const loadAvailableEvents = async () => {
    try {
      const response = await webhooksApi.getAvailableEvents();
      if (response.success && response.data) {
        setEventCategories(response.data.categories);
      }
    } catch (error) {
      // Error handled silently - not critical for UI
    }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    const validationErrors = webhooksApi.validateWebhookData(formData);
    if (validationErrors.length > 0) {
      setErrors(validationErrors);
      return;
    }

    try {
      setLoading(true);
      setErrors([]);
      const response = await webhooksApi.createWebhook(formData);

      if (response.success && response.data) {
        showNotification('Webhook created successfully', 'success');
        onWebhookCreated(response.data);
        onClose();
        setFormData(webhooksApi.getDefaultFormData());
      } else {
        setErrors([response.error || 'Failed to create webhook']);
      }
    } catch (error: unknown) {
      setErrors(['Failed to create webhook']);
    } finally {
      setLoading(false);
    }
  };

  const toggleEventType = (eventType: string) => {
    setFormData(prev => ({
      ...prev,
      event_types: prev.event_types.includes(eventType)
        ? prev.event_types.filter(e => e !== eventType)
        : [...prev.event_types, eventType]
    }));
  };

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center p-4 z-50">
      <div className="bg-theme-surface rounded-lg shadow-xl max-w-3xl w-full max-h-[90vh] overflow-hidden">
        <div className="px-6 py-4 border-b border-theme">
          <h3 className="text-lg font-semibold text-theme-primary">Create Webhook Endpoint</h3>
        </div>

        <form onSubmit={handleSubmit} className="overflow-auto max-h-[calc(90vh-140px)]">
          <div className="px-6 py-4 space-y-6">
            {/* Errors */}
            {errors.length > 0 && (
              <div className="bg-theme-error-background border border-theme-error rounded-lg p-4">
                <div className="flex items-center gap-2 mb-2">
                  <AlertTriangle className="w-5 h-5 text-theme-error" />
                  <span className="font-medium text-theme-error">Please fix the following errors:</span>
                </div>
                <ul className="list-disc list-inside text-sm text-theme-error space-y-1">
                  {errors.map((error, index) => (
                    <li key={index}>{error}</li>
                  ))}
                </ul>
              </div>
            )}

            {/* Basic Info */}
            <div className="space-y-4">
              <div>
                <label className="block text-sm font-medium text-theme-primary mb-2">
                  Endpoint URL *
                </label>
                <input
                  type="url"
                  value={formData.url}
                  onChange={(e) => setFormData(prev => ({ ...prev, url: e.target.value }))}
                  className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
                  placeholder="https://your-app.com/webhooks"
                  required
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-theme-primary mb-2">
                  Description
                </label>
                <textarea
                  value={formData.description || ''}
                  onChange={(e) => setFormData(prev => ({ ...prev, description: e.target.value }))}
                  className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
                  rows={3}
                  placeholder="Optional description of what this webhook does"
                />
              </div>
            </div>

            {/* Event Types */}
            <div>
              <label className="block text-sm font-medium text-theme-primary mb-3">
                Event Types *
              </label>
              <div className="space-y-4 max-h-60 overflow-y-auto border border-theme rounded-lg p-3">
                {Object.entries(eventCategories).map(([category, events]) => (
                  <div key={category}>
                    <h4 className="font-medium text-theme-primary mb-2 capitalize">
                      {category.replace('_', ' ')}
                    </h4>
                    <div className="space-y-2 ml-2">
                      {events.map((eventType) => (
                        <label key={eventType} className="flex items-center gap-2 cursor-pointer">
                          <input
                            type="checkbox"
                            checked={formData.event_types.includes(eventType)}
                            onChange={() => toggleEventType(eventType)}
                            className="w-4 h-4 text-theme-interactive-primary border-theme rounded focus:ring-theme-interactive-primary"
                          />
                          <span className="text-sm text-theme-secondary">{webhooksApi.formatEventType(eventType)}</span>
                        </label>
                      ))}
                    </div>
                  </div>
                ))}
              </div>
            </div>

            {/* Advanced Settings */}
            <div>
              <Button type="button" variant="outline" onClick={() => setShowAdvanced(!showAdvanced)}
                className="flex items-center gap-2 text-theme-link hover:text-theme-link-hover"
              >
                <Settings className="w-4 h-4" />
                {showAdvanced ? 'Hide' : 'Show'} Advanced Settings
              </Button>

              {showAdvanced && (
                <div className="mt-4 space-y-4 p-4 bg-theme-background rounded-lg border border-theme">
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                    <div>
                      <label className="block text-sm font-medium text-theme-primary mb-2">
                        Content Type
                      </label>
                      <select
                        value={formData.content_type || 'application/json'}
                        onChange={(e) => setFormData(prev => ({ ...prev, content_type: e.target.value }))}
                        className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
                      >
                        <option value="application/json">application/json</option>
                        <option value="application/x-www-form-urlencoded">application/x-www-form-urlencoded</option>
                      </select>
                    </div>

                    <div>
                      <label className="block text-sm font-medium text-theme-primary mb-2">
                        Timeout (seconds)
                      </label>
                      <input
                        type="number"
                        min="1"
                        max="300"
                        value={formData.timeout_seconds || 30}
                        onChange={(e) => setFormData(prev => ({ ...prev, timeout_seconds: parseInt(e.target.value) }))}
                        className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
                      />
                    </div>

                    <div>
                      <label className="block text-sm font-medium text-theme-primary mb-2">
                        Retry Limit
                      </label>
                      <input
                        type="number"
                        min="0"
                        max="10"
                        value={formData.retry_limit || 3}
                        onChange={(e) => setFormData(prev => ({ ...prev, retry_limit: parseInt(e.target.value) }))}
                        className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
                      />
                    </div>

                    <div>
                      <label className="block text-sm font-medium text-theme-primary mb-2">
                        Retry Strategy
                      </label>
                      <select
                        value={formData.retry_backoff || 'exponential'}
                        onChange={(e) => setFormData(prev => ({ ...prev, retry_backoff: e.target.value as 'linear' | 'exponential' }))}
                        className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
                      >
                        <option value="exponential">Exponential Backoff</option>
                        <option value="linear">Linear Backoff</option>
                      </select>
                    </div>
                  </div>
                </div>
              )}
            </div>
          </div>
        </form>

        <div className="px-6 py-4 border-t border-theme flex justify-end gap-3">
          <Button onClick={onClose} type="button" variant="outline">
            Cancel
          </Button>
          <Button onClick={handleSubmit} disabled={loading} variant="primary">
            {loading ? (
              <>
                <LoadingSpinner size="sm" />
                Creating...
              </>
            ) : (
              <>
                <Webhook className="w-4 h-4" />
                Create Webhook
              </>
            )}
          </Button>
        </div>
      </div>
    </div>
  );
};

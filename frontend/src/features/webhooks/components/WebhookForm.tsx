import React, { useState, useEffect } from 'react';
import { Button } from '@/shared/components/ui/Button';
import { FormField } from '@/shared/components/ui/FormField';
import { 
  Globe, 
  Settings, 
  Clock, 
  RefreshCw, 
  Info,
  CheckCircle
} from 'lucide-react';
import webhooksApi, { 
  WebhookEndpoint, 
  WebhookFormData,
  WebhookEventCategories
} from '@/features/webhooks/services/webhooksApi';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import ErrorAlert from '@/shared/components/ui/ErrorAlert';
import { useForm, FormValidationRules } from '@/shared/hooks/useForm';

interface WebhookFormProps {
  webhook?: WebhookEndpoint;
  onSubmit: (data: WebhookFormData) => Promise<void>;
  onCancel: () => void;
}

const WebhookForm: React.FC<WebhookFormProps> = ({
  webhook,
  onSubmit,
  onCancel
}) => {
  const defaultValues: WebhookFormData = webhook ? {
    url: webhook.url,
    description: webhook.description || '',
    status: webhook.status,
    event_types: webhook.event_types,
    content_type: webhook.content_type,
    timeout_seconds: webhook.timeout_seconds,
    retry_limit: webhook.retry_limit,
    retry_backoff: (webhook as any).retry_backoff || 'exponential'
  } : webhooksApi.getDefaultFormData();

  const validationRules: FormValidationRules = {
    url: {
      required: true,
      pattern: /^https?:\/\/.+/,
    },
    event_types: {
      custom: (value: string[]) => {
        if (!value || value.length === 0) {
          return 'At least one event type must be selected';
        }
        return null;
      }
    },
    timeout_seconds: {
      custom: (value: number) => {
        if (value < 1 || value > 300) {
          return 'Timeout must be between 1 and 300 seconds';
        }
        return null;
      }
    },
    retry_limit: {
      custom: (value: number) => {
        if (value < 0 || value > 10) {
          return 'Retry limit must be between 0 and 10';
        }
        return null;
      }
    }
  };

  const form = useForm<WebhookFormData>({
    initialValues: defaultValues,
    validationRules,
    onSubmit,
    enableRealTimeValidation: true,
    showSuccessNotification: true,
    successMessage: webhook ? 'Webhook updated successfully' : 'Webhook created successfully',
  });

  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  const [availableEvents, setAvailableEvents] = useState<string[]>([]);
  const [eventCategories, setEventCategories] = useState<WebhookEventCategories>({});
  const [loadingEvents, setLoadingEvents] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Load available events
  useEffect(() => {
    const loadEvents = async () => {
      try {
        const response = await webhooksApi.getAvailableEvents();
        if (response.success && response.data) {
          setAvailableEvents(response.data.events);
          setEventCategories(response.data.categories);
        } else {
          setError(response.error || 'Failed to load available events');
        }
      } catch (err) {
        setError('Failed to load available events');
      } finally {
        setLoadingEvents(false);
      }
    };

    loadEvents();
  }, []);

  // Handle event type selection
  const handleEventTypeToggle = (eventType: string) => {
    const currentEventTypes = form.values.event_types;
    const isSelected = currentEventTypes.includes(eventType);
    
    const newEventTypes = isSelected
      ? currentEventTypes.filter(type => type !== eventType)
      : [...currentEventTypes, eventType];
      
    form.setValue('event_types', newEventTypes);
  };

  // Handle select all events in category
  const handleCategoryToggle = (category: string) => {
    const safeEventCategories = eventCategories || {};
    const categoryEvents = Object.keys(safeEventCategories).includes(category) 
      ? safeEventCategories[category as keyof typeof safeEventCategories] || []
      : [];
    const allSelected = categoryEvents.every(event => form.values.event_types.includes(event));
    
    if (allSelected) {
      // Deselect all in category
      const newEventTypes = form.values.event_types.filter(type => !categoryEvents.includes(type));
      form.setValue('event_types', newEventTypes);
    } else {
      // Select all in category
      const newEventTypes = [...form.values.event_types];
      categoryEvents.forEach(event => {
        if (!newEventTypes.includes(event)) {
          newEventTypes.push(event);
        }
      });
      form.setValue('event_types', newEventTypes);
    }
  };

  if (loadingEvents) {
    return (
      <div className="bg-theme-surface rounded-lg p-8 border border-theme">
        <div className="flex justify-center">
          <LoadingSpinner size="lg" />
        </div>
      </div>
    );
  }

  return (
    <form onSubmit={form.handleSubmit} className="space-y-6">
        {/* Error Alert */}
        {error && (
          <ErrorAlert message={error} onClose={() => setError(null)} />
        )}

        {/* Basic Configuration */}
        <div className="space-y-4">
          <h3 className="text-lg font-semibold text-theme-primary flex items-center gap-2">
            <Globe className="w-5 h-5" />
            Basic Configuration
          </h3>

          {/* URL */}
          <div>
            <FormField 
              label="Webhook URL" 
              type="url" 
              placeholder="https://your-app.com/webhooks" 
              value={form.values.url}
              onChange={(value) => form.setValue('url', value)}
              required 
              disabled={form.isSubmitting} 
            />
            {form.errors.url && (
              <p className="text-theme-error text-sm mt-1">{form.errors.url}</p>
            )}
            <p className="text-xs text-theme-secondary mt-1">
              The URL where webhook events will be delivered
            </p>
          </div>

          {/* Description */}
          <div>
            <label htmlFor="description" className="block text-sm font-medium text-theme-primary mb-2">
              Description
            </label>
            <textarea
              {...form.getFieldProps('description')}
              id="description"
              placeholder="Describe the purpose of this webhook..."
              rows={3}
              className={`w-full px-4 py-2 rounded-lg border bg-theme-background text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:border-theme-focus resize-none ${
                form.errors.description ? 'border-theme-error' : 'border-theme'
              }`}
              disabled={form.isSubmitting}
            />
            {form.errors.description && (
              <p className="text-theme-error text-sm mt-1">{form.errors.description}</p>
            )}
          </div>

          {/* Status */}
          <div>
            <label htmlFor="status" className="block text-sm font-medium text-theme-primary mb-2">
              Status
            </label>
            <select
              {...form.getFieldProps('status')}
              id="status"
              className={`w-full px-4 py-2 rounded-lg border bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus ${
                form.errors.status ? 'border-theme-error' : 'border-theme'
              }`}
              disabled={form.isSubmitting}
            >
              <option value="active">Active</option>
              <option value="inactive">Inactive</option>
            </select>
            {form.errors.status && (
              <p className="text-theme-error text-sm mt-1">{form.errors.status}</p>
            )}
            <p className="text-xs text-theme-secondary mt-1">
              Inactive webhooks will not receive events
            </p>
          </div>
        </div>

        {/* Event Types */}
        <div className="space-y-4">
          <h3 className="text-lg font-semibold text-theme-primary flex items-center gap-2">
            <Settings className="w-5 h-5" />
            Event Types *
          </h3>
          
          <div className="bg-theme-background rounded-lg border border-theme p-4">
            <p className="text-sm text-theme-secondary mb-4">
              Select which events should trigger this webhook
            </p>

            <div className="space-y-4">
              {Object.entries(eventCategories).map(([category, events]) => {
                const selectedInCategory = events.filter(event => form.values.event_types.includes(event)).length;
                const allSelected = selectedInCategory === events.length;
                
                return (
                  <div key={category} className="border border-theme rounded-lg overflow-hidden">
                    {/* Category Header */}
                    <div 
                      className="bg-theme-surface px-4 py-3 cursor-pointer hover:bg-theme-surface-hover transition-colors duration-200"
                      onClick={() => handleCategoryToggle(category)}
                    >
                      <div className="flex items-center justify-between">
                        <div className="flex items-center gap-3">
                          <div className={`w-4 h-4 rounded border-2 flex items-center justify-center transition-colors duration-200 ${
                            allSelected 
                              ? 'bg-theme-interactive-primary border-theme-interactive-primary' 
                              : selectedInCategory > 0
                                ? 'bg-theme-surface-selected border-theme-interactive-primary'
                                : 'border-theme'
                          }`}>
                            {allSelected && <CheckCircle className="w-3 h-3 text-theme-on-primary" />}
                            {selectedInCategory > 0 && selectedInCategory < events.length && (
                              <div className="w-2 h-2 bg-theme-interactive-primary rounded-full" />
                            )}
                          </div>
                          <span className="font-medium text-theme-primary">{category}</span>
                        </div>
                        <span className="text-xs text-theme-secondary">
                          {selectedInCategory}/{events.length} selected
                        </span>
                      </div>
                    </div>

                    {/* Category Events */}
                    <div className="p-4 space-y-2">
                      {events.map(eventType => (
                        <div key={eventType} className="flex items-center gap-3">
                          <input
                            type="checkbox"
                            id={`event-${eventType}`}
                            checked={form.values.event_types.includes(eventType)}
                            onChange={() => handleEventTypeToggle(eventType)}
                            className="w-4 h-4 text-theme-interactive-primary bg-theme-background border-theme rounded focus:ring-theme-interactive-primary focus:ring-2"
                            disabled={form.isSubmitting}
                          />
                          <label 
                            htmlFor={`event-${eventType}`}
                            className="text-sm text-theme-secondary cursor-pointer hover:text-theme-primary transition-colors duration-200"
                          >
                            {webhooksApi.formatEventType(eventType)}
                          </label>
                        </div>
                      ))}
                    </div>
                  </div>
                );
              })}
            </div>

            {form.values.event_types.length > 0 && (
              <div className="mt-4 p-3 bg-theme-success-background rounded-lg">
                <p className="text-sm text-theme-success">
                  <CheckCircle className="w-4 h-4 inline mr-2" />
                  {form.values.event_types.length} event type{form.values.event_types.length !== 1 ? 's' : ''} selected
                </p>
              </div>
            )}
            {form.errors.event_types && (
              <p className="text-theme-error text-sm mt-2">{form.errors.event_types}</p>
            )}
          </div>
        </div>

        {/* Advanced Settings */}
        <div className="space-y-4">
          <h3 className="text-lg font-semibold text-theme-primary flex items-center gap-2">
            <Settings className="w-5 h-5" />
            Advanced Settings
          </h3>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            {/* Content Type */}
            <div>
              <label htmlFor="content_type" className="block text-sm font-medium text-theme-primary mb-2">
                Content Type
              </label>
              <select
                {...form.getFieldProps('content_type')}
                id="content_type"
                className={`w-full px-4 py-2 rounded-lg border bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus ${
                  form.errors.content_type ? 'border-theme-error' : 'border-theme'
                }`}
                disabled={form.isSubmitting}
              >
                <option value="application/json">application/json</option>
                <option value="application/x-www-form-urlencoded">application/x-www-form-urlencoded</option>
              </select>
              {form.errors.content_type && (
                <p className="text-theme-error text-sm mt-1">{form.errors.content_type}</p>
              )}
            </div>

            {/* Timeout */}
            <div>
              <FormField 
                label="Timeout (seconds)" 
                type="number" 
                value={form.values.timeout_seconds?.toString() || ''}
                onChange={(value) => form.setValue('timeout_seconds', parseInt(value) || 0)}
                disabled={form.isSubmitting} 
                icon={<Clock className="w-4 h-4" />}
              />
              {form.errors.timeout_seconds && (
                <p className="text-theme-error text-sm mt-1">{form.errors.timeout_seconds}</p>
              )}
              <p className="text-xs text-theme-secondary mt-1">
                Maximum time to wait for response (1-300 seconds)
              </p>
            </div>

            {/* Retry Limit */}
            <div>
              <FormField 
                label="Retry Limit" 
                type="number" 
                value={form.values.retry_limit?.toString() || ''}
                onChange={(value) => form.setValue('retry_limit', parseInt(value) || 0)}
                disabled={form.isSubmitting} 
                icon={<RefreshCw className="w-4 h-4" />}
              />
              {form.errors.retry_limit && (
                <p className="text-theme-error text-sm mt-1">{form.errors.retry_limit}</p>
              )}
              <p className="text-xs text-theme-secondary mt-1">
                Number of retry attempts for failed deliveries (0-10)
              </p>
            </div>

            {/* Retry Backoff */}
            <div>
              <label htmlFor="retry_backoff" className="block text-sm font-medium text-theme-primary mb-2">
                Retry Strategy
              </label>
              <select
                {...form.getFieldProps('retry_backoff')}
                id="retry_backoff"
                className={`w-full px-4 py-2 rounded-lg border bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus ${
                  form.errors.retry_backoff ? 'border-theme-error' : 'border-theme'
                }`}
                disabled={form.isSubmitting}
              >
                <option value="exponential">Exponential Backoff</option>
                <option value="linear">Linear Backoff</option>
              </select>
              {form.errors.retry_backoff && (
                <p className="text-theme-error text-sm mt-1">{form.errors.retry_backoff}</p>
              )}
              <p className="text-xs text-theme-secondary mt-1">
                {form.values.retry_backoff === 'exponential' 
                  ? 'Delay increases exponentially: 1min, 2min, 4min...'
                  : 'Delay increases linearly: 5min, 10min, 15min...'
                }
              </p>
            </div>
          </div>
        </div>

        {/* Info Box */}
        <div className="bg-theme-info-background border border-theme-info-border rounded-lg p-4">
          <div className="flex items-start gap-3">
            <Info className="w-5 h-5 text-theme-info flex-shrink-0 mt-0.5" />
            <div className="text-sm text-theme-secondary">
              <p className="font-medium text-theme-primary mb-2">Security Considerations:</p>
              <ul className="space-y-1">
                <li>• Your endpoint will receive a secret token in the headers for verification</li>
                <li>• Webhook payloads are signed for authenticity verification</li>
                <li>• Ensure your endpoint can handle the expected request volume</li>
                <li>• Failed deliveries will be retried based on your retry configuration</li>
              </ul>
            </div>
          </div>
        </div>

        {/* Form Actions */}
        <div className="flex items-center justify-between pt-6 border-t border-theme">
          <Button onClick={onCancel} disabled={form.isSubmitting} type="button" variant="outline">
            Cancel
          </Button>

          <Button disabled={form.isSubmitting || form.values.event_types.length === 0 || !form.isValid} type="submit" variant="primary">
            {form.isSubmitting && <LoadingSpinner size="sm" />}
            {webhook ? 'Update Webhook' : 'Create Webhook'}
          </Button>
        </div>
      </form>
  );
};

export default WebhookForm;
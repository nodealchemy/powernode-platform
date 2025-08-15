import React, { useState, useEffect } from 'react';
import { 
  Globe, 
  Settings, 
  Clock, 
  RefreshCw, 
  AlertTriangle,
  Info,
  CheckCircle
} from 'lucide-react';
import webhooksApi, { 
  WebhookEndpoint, 
  WebhookFormData,
  WebhookEventCategories
} from '../../services/webhooksApi';
import { LoadingSpinner } from '../ui/LoadingSpinner';
import ErrorAlert from '../common/ErrorAlert';

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
  const [formData, setFormData] = useState<WebhookFormData>(
    webhook ? {
      url: webhook.url,
      description: webhook.description || '',
      status: webhook.status,
      event_types: webhook.event_types,
      content_type: webhook.content_type,
      timeout_seconds: webhook.timeout_seconds,
      retry_limit: webhook.retry_limit,
      retry_backoff: (webhook as any).retry_backoff || 'exponential'
    } : webhooksApi.getDefaultFormData()
  );

  const [availableEvents, setAvailableEvents] = useState<string[]>([]);
  const [eventCategories, setEventCategories] = useState<WebhookEventCategories>({});
  const [loading, setLoading] = useState(false);
  const [loadingEvents, setLoadingEvents] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [validationErrors, setValidationErrors] = useState<string[]>([]);

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

  // Handle form submission
  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    
    // Validate form
    const errors = webhooksApi.validateWebhookData(formData);
    setValidationErrors(errors);
    
    if (errors.length > 0) {
      return;
    }

    setLoading(true);
    setError(null);

    try {
      await onSubmit(formData);
    } catch (err) {
      setError('Failed to save webhook');
    } finally {
      setLoading(false);
    }
  };

  // Handle input changes
  const handleInputChange = (field: keyof WebhookFormData, value: any) => {
    setFormData(prev => ({
      ...prev,
      [field]: value
    }));
    
    // Clear validation errors when user starts typing
    if (validationErrors.length > 0) {
      setValidationErrors([]);
    }
  };

  // Handle event type selection
  const handleEventTypeToggle = (eventType: string) => {
    const isSelected = formData.event_types.includes(eventType);
    
    handleInputChange(
      'event_types',
      isSelected
        ? formData.event_types.filter(type => type !== eventType)
        : [...formData.event_types, eventType]
    );
  };

  // Handle select all events in category
  const handleCategoryToggle = (category: string) => {
    const safeEventCategories = eventCategories || {};
    const categoryEvents = Object.keys(safeEventCategories).includes(category) 
      ? safeEventCategories[category as keyof typeof safeEventCategories] || []
      : [];
    const allSelected = categoryEvents.every(event => formData.event_types.includes(event));
    
    if (allSelected) {
      // Deselect all in category
      handleInputChange(
        'event_types',
        formData.event_types.filter(type => !categoryEvents.includes(type))
      );
    } else {
      // Select all in category
      const newEventTypes = [...formData.event_types];
      categoryEvents.forEach(event => {
        if (!newEventTypes.includes(event)) {
          newEventTypes.push(event);
        }
      });
      handleInputChange('event_types', newEventTypes);
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
    <form onSubmit={handleSubmit} className="space-y-6">
        {/* Error Alert */}
        {error && (
          <ErrorAlert message={error} onClose={() => setError(null)} />
        )}

        {/* Validation Errors */}
        {validationErrors.length > 0 && (
          <div className="bg-theme-error bg-opacity-10 border border-theme-error rounded-lg p-4">
            <div className="flex items-start gap-3">
              <AlertTriangle className="w-5 h-5 text-theme-error flex-shrink-0 mt-0.5" />
              <div>
                <h4 className="text-sm font-semibold text-theme-error mb-2">
                  Please fix the following errors:
                </h4>
                <ul className="text-sm text-theme-error space-y-1">
                  {validationErrors.map((error, index) => (
                    <li key={index}>• {error}</li>
                  ))}
                </ul>
              </div>
            </div>
          </div>
        )}

        {/* Basic Configuration */}
        <div className="space-y-4">
          <h3 className="text-lg font-semibold text-theme-primary flex items-center gap-2">
            <Globe className="w-5 h-5" />
            Basic Configuration
          </h3>

          {/* URL */}
          <div>
            <label htmlFor="url" className="block text-sm font-medium text-theme-primary mb-2">
              Webhook URL *
            </label>
            <input
              type="url"
              id="url"
              value={formData.url}
              onChange={(e) => handleInputChange('url', e.target.value)}
              placeholder="https://your-app.com/webhooks"
              className="w-full px-4 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:border-theme-focus"
              required
            />
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
              id="description"
              value={formData.description}
              onChange={(e) => handleInputChange('description', e.target.value)}
              placeholder="Describe the purpose of this webhook..."
              rows={3}
              className="w-full px-4 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:border-theme-focus resize-none"
            />
          </div>

          {/* Status */}
          <div>
            <label htmlFor="status" className="block text-sm font-medium text-theme-primary mb-2">
              Status
            </label>
            <select
              id="status"
              value={formData.status}
              onChange={(e) => handleInputChange('status', e.target.value as 'active' | 'inactive')}
              className="w-full px-4 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
            >
              <option value="active">Active</option>
              <option value="inactive">Inactive</option>
            </select>
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
                const selectedInCategory = events.filter(event => formData.event_types.includes(event)).length;
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
                                ? 'bg-theme-interactive-primary bg-opacity-50 border-theme-interactive-primary'
                                : 'border-theme'
                          }`}>
                            {allSelected && <CheckCircle className="w-3 h-3 text-white" />}
                            {selectedInCategory > 0 && selectedInCategory < events.length && (
                              <div className="w-2 h-2 bg-white rounded-full" />
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
                            checked={formData.event_types.includes(eventType)}
                            onChange={() => handleEventTypeToggle(eventType)}
                            className="w-4 h-4 text-theme-interactive-primary bg-theme-background border-theme rounded focus:ring-theme-interactive-primary focus:ring-2"
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

            {formData.event_types.length > 0 && (
              <div className="mt-4 p-3 bg-theme-success bg-opacity-10 rounded-lg">
                <p className="text-sm text-theme-success">
                  <CheckCircle className="w-4 h-4 inline mr-2" />
                  {formData.event_types.length} event type{formData.event_types.length !== 1 ? 's' : ''} selected
                </p>
              </div>
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
                id="content_type"
                value={formData.content_type}
                onChange={(e) => handleInputChange('content_type', e.target.value)}
                className="w-full px-4 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
              >
                <option value="application/json">application/json</option>
                <option value="application/x-www-form-urlencoded">application/x-www-form-urlencoded</option>
              </select>
            </div>

            {/* Timeout */}
            <div>
              <label htmlFor="timeout_seconds" className="block text-sm font-medium text-theme-primary mb-2">
                <Clock className="w-4 h-4 inline mr-1" />
                Timeout (seconds)
              </label>
              <input
                type="number"
                id="timeout_seconds"
                min="1"
                max="300"
                value={formData.timeout_seconds}
                onChange={(e) => handleInputChange('timeout_seconds', parseInt(e.target.value) || 30)}
                className="w-full px-4 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
              />
              <p className="text-xs text-theme-secondary mt-1">
                Maximum time to wait for response (1-300 seconds)
              </p>
            </div>

            {/* Retry Limit */}
            <div>
              <label htmlFor="retry_limit" className="block text-sm font-medium text-theme-primary mb-2">
                <RefreshCw className="w-4 h-4 inline mr-1" />
                Retry Limit
              </label>
              <input
                type="number"
                id="retry_limit"
                min="0"
                max="10"
                value={formData.retry_limit}
                onChange={(e) => handleInputChange('retry_limit', parseInt(e.target.value) || 0)}
                className="w-full px-4 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
              />
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
                id="retry_backoff"
                value={formData.retry_backoff}
                onChange={(e) => handleInputChange('retry_backoff', e.target.value as 'linear' | 'exponential')}
                className="w-full px-4 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
              >
                <option value="exponential">Exponential Backoff</option>
                <option value="linear">Linear Backoff</option>
              </select>
              <p className="text-xs text-theme-secondary mt-1">
                {formData.retry_backoff === 'exponential' 
                  ? 'Delay increases exponentially: 1min, 2min, 4min...'
                  : 'Delay increases linearly: 5min, 10min, 15min...'
                }
              </p>
            </div>
          </div>
        </div>

        {/* Info Box */}
        <div className="bg-theme-interactive-primary bg-opacity-5 border border-theme-interactive-primary rounded-lg p-4">
          <div className="flex items-start gap-3">
            <Info className="w-5 h-5 text-theme-interactive-primary flex-shrink-0 mt-0.5" />
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
          <button
            type="button"
            onClick={onCancel}
            className="px-6 py-2 text-theme-secondary hover:text-theme-primary transition-colors duration-200"
            disabled={loading}
          >
            Cancel
          </button>

          <button
            type="submit"
            disabled={loading || formData.event_types.length === 0}
            className="bg-theme-interactive-primary text-white px-6 py-2 rounded-lg hover:bg-theme-interactive-primary-hover disabled:opacity-50 disabled:cursor-not-allowed transition-all duration-200 flex items-center gap-2"
          >
            {loading && <LoadingSpinner size="sm" />}
            {webhook ? 'Update Webhook' : 'Create Webhook'}
          </button>
        </div>
      </form>
  );
};

export default WebhookForm;
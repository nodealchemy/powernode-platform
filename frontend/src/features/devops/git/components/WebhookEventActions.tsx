import React, { useState } from 'react';
import { GitWebhookEvent } from '../types';
import { webhooksApi } from '../services/git/webhooksApi';

interface WebhookEventActionsProps {
  event: GitWebhookEvent;
  onRetry?: (event: GitWebhookEvent) => void;
  onRedeliver?: (originalEvent: GitWebhookEvent, newEvent: GitWebhookEvent) => void;
  onError?: (message: string) => void;
  showRetry?: boolean;
  showRedeliver?: boolean;
  compact?: boolean;
}

export const WebhookEventActions: React.FC<WebhookEventActionsProps> = ({
  event,
  onRetry,
  onRedeliver,
  onError,
  showRetry = true,
  showRedeliver = true,
  compact = false,
}) => {
  const [isRetrying, setIsRetrying] = useState(false);
  const [isRedelivering, setIsRedelivering] = useState(false);
  const [showRedeliverConfirm, setShowRedeliverConfirm] = useState(false);

  const handleRetry = async () => {
    if (!event.retryable) return;

    setIsRetrying(true);
    try {
      const result = await webhooksApi.retryWebhookEvent(event.id);
      onRetry?.(result.event);
    } catch (err) {
      onError?.(err instanceof Error ? err.message : 'Failed to retry event');
    } finally {
      setIsRetrying(false);
    }
  };

  const handleRedeliver = async () => {
    setIsRedelivering(true);
    setShowRedeliverConfirm(false);
    try {
      const result = await webhooksApi.redeliverWebhookEvent(event.id);
      onRedeliver?.(result.original_event, result.new_event);
    } catch (err) {
      onError?.(err instanceof Error ? err.message : 'Failed to redeliver event');
    } finally {
      setIsRedelivering(false);
    }
  };

  if (compact) {
    return (
      <div className="flex items-center gap-2">
        {showRetry && event.retryable && (
          <button
            onClick={handleRetry}
            disabled={isRetrying}
            title="Retry this event"
            className="p-1.5 text-theme-text-secondary hover:text-theme-primary hover:bg-theme-bg-hover rounded transition-colors disabled:opacity-50"
          >
            {isRetrying ? (
              <svg
                className="w-4 h-4 animate-spin"
                fill="none"
                viewBox="0 0 24 24"
                stroke="currentColor"
              >
                <circle
                  className="opacity-25"
                  cx="12"
                  cy="12"
                  r="10"
                  stroke="currentColor"
                  strokeWidth="4"
                />
                <path
                  className="opacity-75"
                  fill="currentColor"
                  d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
                />
              </svg>
            ) : (
              <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  strokeWidth={2}
                  d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"
                />
              </svg>
            )}
          </button>
        )}
        {showRedeliver && (
          <button
            onClick={() => setShowRedeliverConfirm(true)}
            disabled={isRedelivering}
            title="Redeliver this event (creates a new event)"
            className="p-1.5 text-theme-text-secondary hover:text-theme-primary hover:bg-theme-bg-hover rounded transition-colors disabled:opacity-50"
          >
            {isRedelivering ? (
              <svg
                className="w-4 h-4 animate-spin"
                fill="none"
                viewBox="0 0 24 24"
                stroke="currentColor"
              >
                <circle
                  className="opacity-25"
                  cx="12"
                  cy="12"
                  r="10"
                  stroke="currentColor"
                  strokeWidth="4"
                />
                <path
                  className="opacity-75"
                  fill="currentColor"
                  d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
                />
              </svg>
            ) : (
              <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  strokeWidth={2}
                  d="M8 7h12m0 0l-4-4m4 4l-4 4m0 6H4m0 0l4 4m-4-4l4-4"
                />
              </svg>
            )}
          </button>
        )}

        {/* Redeliver Confirmation Modal */}
        {showRedeliverConfirm && (
          <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
            <div className="bg-theme-bg-primary rounded-lg shadow-xl p-6 max-w-md w-full mx-4">
              <h3 className="text-lg font-semibold text-theme-text-primary mb-2">
                Redeliver Webhook Event?
              </h3>
              <p className="text-sm text-theme-text-secondary mb-4">
                This will create a new webhook event with the same payload and queue it for
                processing. The original event will remain unchanged.
              </p>
              <div className="flex justify-end gap-3">
                <button
                  onClick={() => setShowRedeliverConfirm(false)}
                  className="px-4 py-2 text-sm font-medium text-theme-text-secondary hover:text-theme-text-primary transition-colors"
                >
                  Cancel
                </button>
                <button
                  onClick={handleRedeliver}
                  className="px-4 py-2 text-sm font-medium bg-theme-primary text-white rounded-lg hover:bg-theme-primary-hover transition-colors"
                >
                  Redeliver
                </button>
              </div>
            </div>
          </div>
        )}
      </div>
    );
  }

  return (
    <div className="flex items-center gap-3">
      {showRetry && event.retryable && (
        <button
          onClick={handleRetry}
          disabled={isRetrying}
          className="inline-flex items-center gap-2 px-3 py-1.5 text-sm font-medium text-theme-primary bg-theme-primary/10 hover:bg-theme-primary/20 rounded-lg transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
        >
          {isRetrying ? (
            <>
              <svg
                className="w-4 h-4 animate-spin"
                fill="none"
                viewBox="0 0 24 24"
                stroke="currentColor"
              >
                <circle
                  className="opacity-25"
                  cx="12"
                  cy="12"
                  r="10"
                  stroke="currentColor"
                  strokeWidth="4"
                />
                <path
                  className="opacity-75"
                  fill="currentColor"
                  d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
                />
              </svg>
              Retrying...
            </>
          ) : (
            <>
              <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  strokeWidth={2}
                  d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"
                />
              </svg>
              Retry
            </>
          )}
        </button>
      )}

      {showRedeliver && (
        <>
          <button
            onClick={() => setShowRedeliverConfirm(true)}
            disabled={isRedelivering}
            className="inline-flex items-center gap-2 px-3 py-1.5 text-sm font-medium text-theme-text-secondary bg-theme-bg-tertiary hover:bg-theme-bg-hover rounded-lg transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {isRedelivering ? (
              <>
                <svg
                  className="w-4 h-4 animate-spin"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke="currentColor"
                >
                  <circle
                    className="opacity-25"
                    cx="12"
                    cy="12"
                    r="10"
                    stroke="currentColor"
                    strokeWidth="4"
                  />
                  <path
                    className="opacity-75"
                    fill="currentColor"
                    d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
                  />
                </svg>
                Redelivering...
              </>
            ) : (
              <>
                <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    strokeWidth={2}
                    d="M8 7h12m0 0l-4-4m4 4l-4 4m0 6H4m0 0l4 4m-4-4l4-4"
                  />
                </svg>
                Redeliver
              </>
            )}
          </button>

          {/* Redeliver Confirmation Modal */}
          {showRedeliverConfirm && (
            <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
              <div className="bg-theme-bg-primary rounded-lg shadow-xl p-6 max-w-md w-full mx-4">
                <h3 className="text-lg font-semibold text-theme-text-primary mb-2">
                  Redeliver Webhook Event?
                </h3>
                <p className="text-sm text-theme-text-secondary mb-4">
                  This will create a new webhook event with the same payload and queue it for
                  processing. The original event will remain unchanged.
                </p>
                <div className="p-3 bg-theme-bg-tertiary rounded-lg mb-4">
                  <div className="text-xs text-theme-text-tertiary mb-1">Event Details</div>
                  <div className="text-sm">
                    <span className="font-medium text-theme-text-primary">{event.event_type}</span>
                    {event.action && (
                      <span className="text-theme-text-secondary"> ({event.action})</span>
                    )}
                  </div>
                  {event.branch_name && (
                    <div className="text-xs text-theme-text-secondary mt-1">
                      Branch: {event.branch_name}
                    </div>
                  )}
                </div>
                <div className="flex justify-end gap-3">
                  <button
                    onClick={() => setShowRedeliverConfirm(false)}
                    className="px-4 py-2 text-sm font-medium text-theme-text-secondary hover:text-theme-text-primary transition-colors"
                  >
                    Cancel
                  </button>
                  <button
                    onClick={handleRedeliver}
                    className="px-4 py-2 text-sm font-medium bg-theme-primary text-white rounded-lg hover:bg-theme-primary-hover transition-colors"
                  >
                    Redeliver Event
                  </button>
                </div>
              </div>
            </div>
          )}
        </>
      )}
    </div>
  );
};

export default WebhookEventActions;

import { useEffect, useState, useCallback, useRef } from 'react';
import { useNotifications } from '@/shared/hooks/useNotifications';
import type { WorkflowValidationResult } from '@/shared/types/workflow';

interface UseValidationWebSocketOptions {
  workflowId: string;
  enabled?: boolean;
  onValidationUpdate?: (validation: WorkflowValidationResult) => void;
  onHealthAlert?: (alert: ValidationHealthAlert) => void;
}

interface ValidationHealthAlert {
  workflow_id: string;
  workflow_name: string;
  type: 'stale_validation' | 'health_degradation' | 'persistent_invalid_status' | 'high_error_count';
  severity: 'warning' | 'error';
  message: string;
  metadata: Record<string, any>;
  created_at: string;
}

interface ValidationWebSocketMessage {
  type: 'validation_result' | 'validation_health_alerts' | 'validation_started' | 'validation_progress';
  validation?: WorkflowValidationResult;
  alerts?: ValidationHealthAlert[];
  progress?: {
    current_step: string;
    total_steps: number;
    completed_steps: number;
    percentage: number;
  };
}

/**
 * Custom hook for real-time workflow validation updates via WebSocket
 *
 * Subscribes to the AiOrchestrationChannel for validation-related events:
 * - validation_result: New validation completed
 * - validation_health_alerts: Health degradation alerts
 * - validation_started: Validation process initiated
 * - validation_progress: Validation progress updates
 *
 * @example
 * ```tsx
 * const {
 *   validationResult,
 *   isConnected,
 *   lastUpdate
 * } = useValidationWebSocket({
 *   workflowId: 'workflow-123',
 *   enabled: true,
 *   onValidationUpdate: (validation) => {
 *     console.log('New validation:', validation);
 *   }
 * });
 * ```
 */
export const useValidationWebSocket = ({
  workflowId,
  enabled = true,
  onValidationUpdate,
  onHealthAlert
}: UseValidationWebSocketOptions) => {
  const [validationResult, setValidationResult] = useState<WorkflowValidationResult | null>(null);
  const [isConnected, setIsConnected] = useState(false);
  const [isValidating, setIsValidating] = useState(false);
  const [validationProgress, setValidationProgress] = useState<number>(0);
  const [lastUpdate, setLastUpdate] = useState<Date | null>(null);
  const [healthAlerts, setHealthAlerts] = useState<ValidationHealthAlert[]>([]);

  const { addNotification } = useNotifications();
  const channelRef = useRef<any>(null);
  const mountedRef = useRef(true);

  const handleValidationResult = useCallback((validation: WorkflowValidationResult) => {
    if (!mountedRef.current) return;

    setValidationResult(validation);
    setIsValidating(false);
    setValidationProgress(100);
    setLastUpdate(new Date());

    // Call callback if provided
    if (onValidationUpdate) {
      onValidationUpdate(validation);
    }

    // Show notification based on validation status
    const issueCount = validation.issues.length;
    const errorCount = validation.issues.filter(i => i.severity === 'error').length;

    if (errorCount > 0) {
      addNotification({
        type: 'error',
        title: 'Validation Complete',
        message: `Found ${errorCount} error${errorCount !== 1 ? 's' : ''} in workflow`
      });
    } else if (issueCount > 0) {
      addNotification({
        type: 'warning',
        title: 'Validation Complete',
        message: `Found ${issueCount} warning${issueCount !== 1 ? 's' : ''}`
      });
    } else {
      addNotification({
        type: 'success',
        title: 'Validation Complete',
        message: 'Workflow passed all validation checks'
      });
    }
  }, [onValidationUpdate, addNotification]);

  const handleHealthAlerts = useCallback((alerts: ValidationHealthAlert[]) => {
    if (!mountedRef.current) return;

    setHealthAlerts(prev => [...prev, ...alerts]);

    // Show notifications for each alert
    alerts.forEach(alert => {
      addNotification({
        type: alert.severity === 'error' ? 'error' : 'warning',
        title: 'Validation Health Alert',
        message: alert.message
      });

      // Call callback if provided
      if (onHealthAlert) {
        onHealthAlert(alert);
      }
    });
  }, [onHealthAlert, addNotification]);

  const handleValidationStarted = useCallback(() => {
    if (!mountedRef.current) return;

    setIsValidating(true);
    setValidationProgress(0);

    if (process.env.NODE_ENV === 'development') {
      console.info('[useValidationWebSocket] Validation started for workflow:', workflowId);
    }
  }, [workflowId]);

  const handleValidationProgress = useCallback((progress: ValidationWebSocketMessage['progress']) => {
    if (!mountedRef.current || !progress) return;

    setValidationProgress(progress.percentage);

    if (process.env.NODE_ENV === 'development') {
      console.info('[useValidationWebSocket] Validation progress:', progress);
    }
  }, []);

  const handleMessage = useCallback((data: ValidationWebSocketMessage) => {
    if (!mountedRef.current) return;

    switch (data.type) {
      case 'validation_result':
        if (data.validation) {
          handleValidationResult(data.validation);
        }
        break;

      case 'validation_health_alerts':
        if (data.alerts) {
          handleHealthAlerts(data.alerts);
        }
        break;

      case 'validation_started':
        handleValidationStarted();
        break;

      case 'validation_progress':
        if (data.progress) {
          handleValidationProgress(data.progress);
        }
        break;

      default:
        if (process.env.NODE_ENV === 'development') {
          console.warn('[useValidationWebSocket] Unknown message type:', data.type);
        }
    }
  }, [handleValidationResult, handleHealthAlerts, handleValidationStarted, handleValidationProgress]);

  useEffect(() => {
    if (!enabled || !workflowId) {
      return;
    }

    // Get ActionCable instance from window
    const cable = (window as any).ActionCable;
    if (!cable) {
      if (process.env.NODE_ENV === 'development') {
        console.error('[useValidationWebSocket] ActionCable not found on window');
      }
      return;
    }

    // Create channel subscription
    const channel = cable.subscriptions.create(
      {
        channel: 'AiOrchestrationChannel',
        workflow_id: workflowId
      },
      {
        connected: () => {
          if (process.env.NODE_ENV === 'development') {
            console.info('[useValidationWebSocket] Connected to validation channel:', workflowId);
          }
          setIsConnected(true);
        },

        disconnected: () => {
          if (process.env.NODE_ENV === 'development') {
            console.info('[useValidationWebSocket] Disconnected from validation channel:', workflowId);
          }
          setIsConnected(false);
        },

        received: (data: ValidationWebSocketMessage) => {
          handleMessage(data);
        },

        rejected: () => {
          if (process.env.NODE_ENV === 'development') {
            console.error('[useValidationWebSocket] Subscription rejected for workflow:', workflowId);
          }
          setIsConnected(false);
        }
      }
    );

    channelRef.current = channel;

    // Cleanup on unmount
    return () => {
      if (channelRef.current) {
        if (process.env.NODE_ENV === 'development') {
          console.info('[useValidationWebSocket] Unsubscribing from validation channel:', workflowId);
        }
        channelRef.current.unsubscribe();
        channelRef.current = null;
      }
      setIsConnected(false);
    };
  }, [workflowId, enabled, handleMessage]);

  useEffect(() => {
    // Track component mount state
    mountedRef.current = true;
    return () => {
      mountedRef.current = false;
    };
  }, []);

  // Clear alerts older than 5 minutes
  useEffect(() => {
    const interval = setInterval(() => {
      const fiveMinutesAgo = new Date(Date.now() - 5 * 60 * 1000);
      setHealthAlerts(prev =>
        prev.filter(alert => new Date(alert.created_at) > fiveMinutesAgo)
      );
    }, 60000); // Check every minute

    return () => clearInterval(interval);
  }, []);

  return {
    validationResult,
    isConnected,
    isValidating,
    validationProgress,
    lastUpdate,
    healthAlerts,
    clearAlerts: () => setHealthAlerts([])
  };
};

import { useCallback, useRef, useEffect } from 'react';
import { useSelector } from 'react-redux';
import { RootState } from '@/shared/services';
import { useWebSocket } from '@/shared/hooks/useWebSocket';

// Monitoring event types
type MonitoringEventType =
  | 'subscription.confirmed'
  | 'dashboard_stats'
  | 'active_executions'
  | 'system_alert'
  | 'cost_alert'
  | 'real_time_mode_enabled'
  | 'real_time_mode_disabled'
  | 'error';

// Event payload interfaces
export interface DashboardStats {
  total_workflows: number;
  active_executions: number;
  completed_today: number;
  failed_today: number;
}

export interface WorkflowExecution {
  id: string;
  run_id: string;
  workflow_id: string;
  workflow_name: string;
  status: string;
  started_at: string;
  completed_at: string | null;
  execution_time_ms: number | null;
  total_cost: number | null;
}

export interface SystemAlert {
  id: string;
  severity: 'info' | 'warning' | 'error' | 'critical';
  message: string;
  source: string;
  timestamp: string;
}

export interface CostAlert {
  threshold_type: string;
  current_value: number;
  threshold_value: number;
  message: string;
  timestamp: string;
}

interface AiMonitoringWebSocketOptions {
  onDashboardStats?: (stats: DashboardStats) => void;
  onActiveExecutions?: (executions: WorkflowExecution[]) => void;
  onSystemAlert?: (alert: SystemAlert) => void;
  onCostAlert?: (alert: CostAlert) => void;
  onRealTimeModeChanged?: (enabled: boolean, refreshInterval?: number) => void;
  onError?: (error: string) => void;
}

export const useAiMonitoringWebSocket = ({
  onDashboardStats,
  onActiveExecutions,
  onSystemAlert,
  onCostAlert,
  onRealTimeModeChanged,
  onError
}: AiMonitoringWebSocketOptions) => {
  const { isConnected, subscribe, sendMessage, error: connectionError } = useWebSocket();
  const user = useSelector((state: RootState) => state.auth.user);
  const unsubscribeRef = useRef<(() => void) | null>(null);

  // Store latest callback refs to avoid dependency issues
  const onDashboardStatsRef = useRef(onDashboardStats);
  const onActiveExecutionsRef = useRef(onActiveExecutions);
  const onSystemAlertRef = useRef(onSystemAlert);
  const onCostAlertRef = useRef(onCostAlert);
  const onRealTimeModeChangedRef = useRef(onRealTimeModeChanged);
  const onErrorRef = useRef(onError);

  onDashboardStatsRef.current = onDashboardStats;
  onActiveExecutionsRef.current = onActiveExecutions;
  onSystemAlertRef.current = onSystemAlert;
  onCostAlertRef.current = onCostAlert;
  onRealTimeModeChangedRef.current = onRealTimeModeChanged;
  onErrorRef.current = onError;

  // Type guard for WebSocket message data
  const isWebSocketMessage = (data: unknown): data is { type: MonitoringEventType; [key: string]: unknown } => {
    return typeof data === 'object' && data !== null && 'type' in data;
  };

  // Handle incoming messages
  const handleMessage = useCallback((data: unknown) => {
    if (!isWebSocketMessage(data)) return;

    switch (data.type) {
      case 'subscription.confirmed':
        // Subscription confirmed, no action needed
        break;

      case 'dashboard_stats':
        if (data.stats) {
          onDashboardStatsRef.current?.(data.stats as DashboardStats);
        }
        break;

      case 'active_executions':
        if (data.executions) {
          onActiveExecutionsRef.current?.(data.executions as WorkflowExecution[]);
        }
        break;

      case 'system_alert':
        if (data.alert) {
          onSystemAlertRef.current?.(data.alert as SystemAlert);
        }
        break;

      case 'cost_alert':
        if (data.cost_data) {
          onCostAlertRef.current?.(data.cost_data as CostAlert);
        }
        break;

      case 'real_time_mode_enabled':
        onRealTimeModeChangedRef.current?.(true, data.refresh_interval as number | undefined);
        break;

      case 'real_time_mode_disabled':
        onRealTimeModeChangedRef.current?.(false);
        break;

      case 'error':
        onErrorRef.current?.((data.error as string) || 'Monitoring channel error');
        break;
    }
  }, []);

  // Handle channel errors
  const handleError = useCallback((errorMessage: string) => {
    onErrorRef.current?.(errorMessage);
  }, []);

  // Subscribe to monitoring channel
  const subscribeToMonitoring = useCallback(() => {
    if (unsubscribeRef.current) {
      unsubscribeRef.current();
    }

    // Only subscribe if user has an account
    if (!user?.account?.id) {
      if (process.env.NODE_ENV === 'development') {
        console.warn('[AiMonitoringWebSocket] Cannot subscribe: user account not available');
      }
      return;
    }

    unsubscribeRef.current = subscribe({
      channel: 'AiWorkflowMonitoringChannel',
      params: { account_id: user.account.id },
      onMessage: handleMessage,
      onError: handleError
    });
  }, [subscribe, handleMessage, handleError, user?.account?.id]);

  // Request dashboard stats via WebSocket
  const requestDashboardStats = useCallback(async () => {
    if (!isConnected) {
      return false;
    }

    return sendMessage('AiWorkflowMonitoringChannel', 'get_dashboard_stats', {});
  }, [isConnected, sendMessage]);

  // Request active executions via WebSocket
  const requestActiveExecutions = useCallback(async () => {
    if (!isConnected) {
      return false;
    }

    return sendMessage('AiWorkflowMonitoringChannel', 'get_active_executions', {});
  }, [isConnected, sendMessage]);

  // Start real-time monitoring mode
  const startRealTimeMonitoring = useCallback(async () => {
    if (!isConnected) {
      return false;
    }

    return sendMessage('AiWorkflowMonitoringChannel', 'start_real_time_monitoring', {});
  }, [isConnected, sendMessage]);

  // Stop real-time monitoring mode
  const stopRealTimeMonitoring = useCallback(async () => {
    if (!isConnected) {
      return false;
    }

    return sendMessage('AiWorkflowMonitoringChannel', 'stop_real_time_monitoring', {});
  }, [isConnected, sendMessage]);

  // Auto-subscribe when connected
  useEffect(() => {
    if (isConnected) {
      subscribeToMonitoring();
    }

    return () => {
      if (unsubscribeRef.current) {
        unsubscribeRef.current();
        unsubscribeRef.current = null;
      }
    };
  }, [isConnected, subscribeToMonitoring]);

  // Handle connection errors
  useEffect(() => {
    if (connectionError) {
      onErrorRef.current?.(connectionError);
    }
  }, [connectionError]);

  return {
    isConnected,
    requestDashboardStats,
    requestActiveExecutions,
    startRealTimeMonitoring,
    stopRealTimeMonitoring,
    error: connectionError
  };
};

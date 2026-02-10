import { useCallback, useRef, useEffect } from 'react';
import { useWebSocket } from '@/shared/hooks/useWebSocket';

// AI Orchestration event types
type WorkflowEventType =
  | 'workflow_created'
  | 'workflow_updated'
  | 'workflow_deleted'
  | 'workflow_validation_started'
  | 'workflow_validation_completed'
  | 'workflow_validation_failed';

type WorkflowRunEventType =
  | 'run_started'
  | 'run_completed'
  | 'run_failed'
  | 'run_cancelled'
  | 'run_timeout'
  | 'node_started'
  | 'node_completed'
  | 'node_failed'
  | 'node_skipped'
  | 'checkpoint_created'
  | 'checkpoint_restored';

type AgentEventType =
  | 'agent_created'
  | 'agent_updated'
  | 'agent_deleted'
  | 'agent_execution_started'
  | 'agent_execution_completed'
  | 'agent_execution_failed'
  | 'agent_message_sent'
  | 'agent_message_received';

type AgentTeamEventType =
  | 'team_created'
  | 'team_updated'
  | 'team_deleted'
  | 'team_member_added'
  | 'team_member_removed'
  | 'team_execution_started'
  | 'team_execution_completed';

type BatchEventType =
  | 'batch_started'
  | 'batch_completed'
  | 'batch_failed'
  | 'batch_progress_update';

type CircuitBreakerEventType =
  | 'circuit_opened'
  | 'circuit_closed'
  | 'circuit_half_open'
  | 'circuit_state_changed';

type ProviderEventType =
  | 'provider_health_changed'
  | 'provider_rate_limit_hit'
  | 'provider_credentials_updated';

type AiOrchestrationEventType =
  | WorkflowEventType
  | WorkflowRunEventType
  | AgentEventType
  | AgentTeamEventType
  | BatchEventType
  | CircuitBreakerEventType
  | ProviderEventType;

// Event payload interfaces
interface WorkflowEvent {
  type: WorkflowEventType;
  workflow_id: string;
  data: Record<string, unknown>;
  timestamp: string;
}

interface WorkflowRunEvent {
  type: WorkflowRunEventType;
  workflow_id: string;
  run_id: string;
  node_id?: string;
  data: Record<string, unknown>;
  timestamp: string;
}

interface AgentEvent {
  type: AgentEventType;
  agent_id: string;
  execution_id?: string;
  data: Record<string, unknown>;
  timestamp: string;
}

interface AgentTeamEvent {
  type: AgentTeamEventType;
  team_id: string;
  data: Record<string, unknown>;
  timestamp: string;
}

interface BatchEvent {
  type: BatchEventType;
  batch_id: string;
  data: Record<string, unknown>;
  timestamp: string;
}

interface CircuitBreakerEvent {
  type: CircuitBreakerEventType;
  circuit_breaker_id: string;
  data: Record<string, unknown>;
  timestamp: string;
}

interface ProviderEvent {
  type: ProviderEventType;
  provider_id: string;
  data: Record<string, unknown>;
  timestamp: string;
}

type AiOrchestrationEvent =
  | WorkflowEvent
  | WorkflowRunEvent
  | AgentEvent
  | AgentTeamEvent
  | BatchEvent
  | CircuitBreakerEvent
  | ProviderEvent;

// Subscription types
type SubscriptionType = 'workflow' | 'workflow_run' | 'agent' | 'agent_team' | 'batch' | 'circuit_breaker' | 'provider';

interface Subscription {
  id: string;
  type: SubscriptionType;
  resourceId: string;
  unsubscribe: () => void;
}

// Hook options
interface AiOrchestrationWebSocketOptions {
  onWorkflowEvent?: (event: WorkflowEvent) => void;
  onWorkflowRunEvent?: (event: WorkflowRunEvent) => void;
  onAgentEvent?: (event: AgentEvent) => void;
  onAgentTeamEvent?: (event: AgentTeamEvent) => void;
  onBatchEvent?: (event: BatchEvent) => void;
  onCircuitBreakerEvent?: (event: CircuitBreakerEvent) => void;
  onProviderEvent?: (event: ProviderEvent) => void;
  onError?: (error: string) => void;
}

export const useAiOrchestrationWebSocket = ({
  onWorkflowEvent,
  onWorkflowRunEvent,
  onAgentEvent,
  onAgentTeamEvent,
  onBatchEvent,
  onCircuitBreakerEvent,
  onProviderEvent,
  onError
}: AiOrchestrationWebSocketOptions) => {
  const { isConnected, subscribe, error: connectionError } = useWebSocket();
  const subscriptionsRef = useRef<Map<string, Subscription>>(new Map());

  // Store latest callback refs
  const onWorkflowEventRef = useRef(onWorkflowEvent);
  const onWorkflowRunEventRef = useRef(onWorkflowRunEvent);
  const onAgentEventRef = useRef(onAgentEvent);
  const onAgentTeamEventRef = useRef(onAgentTeamEvent);
  const onBatchEventRef = useRef(onBatchEvent);
  const onCircuitBreakerEventRef = useRef(onCircuitBreakerEvent);
  const onProviderEventRef = useRef(onProviderEvent);
  const onErrorRef = useRef(onError);

  onWorkflowEventRef.current = onWorkflowEvent;
  onWorkflowRunEventRef.current = onWorkflowRunEvent;
  onAgentEventRef.current = onAgentEvent;
  onAgentTeamEventRef.current = onAgentTeamEvent;
  onBatchEventRef.current = onBatchEvent;
  onCircuitBreakerEventRef.current = onCircuitBreakerEvent;
  onProviderEventRef.current = onProviderEvent;
  onErrorRef.current = onError;

  // Type guard for WebSocket message data
  interface WebSocketMessage {
    type?: string;
    event?: string;
    data?: unknown;
    message?: string;
    payload?: Record<string, unknown>;
    resource_type?: string;
    resource_id?: string;
    timestamp?: string;
  }
  const isWebSocketMessage = (data: unknown): data is WebSocketMessage => {
    return typeof data === 'object' && data !== null && ('type' in data || 'event' in data);
  };

  // Map backend event types to frontend event types
  const mapBackendEventType = (backendEvent: string): string => {
    const eventMap: Record<string, string> = {
      'node.execution.started': 'node_started',
      'node.execution.running': 'node_started',
      'node.execution.completed': 'node_completed',
      'node.execution.failed': 'node_failed',
      'node.execution.updated': 'node_completed', // Generic update
      'node.duration.updated': 'node_completed',
      'workflow.run.status.changed': 'run_started',
      'workflow.execution.started': 'run_started',
      'workflow.execution.completed': 'run_completed',
      'workflow.execution.failed': 'run_failed',
      'circuit_breaker.state_changed': 'circuit_state_changed',
      'circuit_breaker.opened': 'circuit_opened',
      'circuit_breaker.closed': 'circuit_closed',
      'circuit_breaker.half_opened': 'circuit_half_open',
    };
    return eventMap[backendEvent] || backendEvent;
  };

  // Route events to appropriate handlers
  const routeEvent = useCallback((event: AiOrchestrationEvent) => {
    // Workflow events
    const workflowEvents: WorkflowEventType[] = [
      'workflow_created',
      'workflow_updated',
      'workflow_deleted',
      'workflow_validation_started',
      'workflow_validation_completed',
      'workflow_validation_failed'
    ];

    // Workflow run events
    const runEvents: WorkflowRunEventType[] = [
      'run_started',
      'run_completed',
      'run_failed',
      'run_cancelled',
      'run_timeout',
      'node_started',
      'node_completed',
      'node_failed',
      'node_skipped',
      'checkpoint_created',
      'checkpoint_restored'
    ];

    // Agent events
    const agentEvents: AgentEventType[] = [
      'agent_created',
      'agent_updated',
      'agent_deleted',
      'agent_execution_started',
      'agent_execution_completed',
      'agent_execution_failed',
      'agent_message_sent',
      'agent_message_received'
    ];

    // Agent team events
    const teamEvents: AgentTeamEventType[] = [
      'team_created',
      'team_updated',
      'team_deleted',
      'team_member_added',
      'team_member_removed',
      'team_execution_started',
      'team_execution_completed'
    ];

    // Batch events
    const batchEvents: BatchEventType[] = [
      'batch_started',
      'batch_completed',
      'batch_failed',
      'batch_progress_update'
    ];

    // Circuit breaker events
    const circuitEvents: CircuitBreakerEventType[] = [
      'circuit_opened',
      'circuit_closed',
      'circuit_half_open',
      'circuit_state_changed'
    ];

    // Provider events
    const providerEvents: ProviderEventType[] = [
      'provider_health_changed',
      'provider_rate_limit_hit',
      'provider_credentials_updated'
    ];

    // Route to appropriate handler
    if (workflowEvents.includes(event.type as WorkflowEventType)) {
      onWorkflowEventRef.current?.(event as WorkflowEvent);
    } else if (runEvents.includes(event.type as WorkflowRunEventType)) {
      onWorkflowRunEventRef.current?.(event as WorkflowRunEvent);
    } else if (agentEvents.includes(event.type as AgentEventType)) {
      onAgentEventRef.current?.(event as AgentEvent);
    } else if (teamEvents.includes(event.type as AgentTeamEventType)) {
      onAgentTeamEventRef.current?.(event as AgentTeamEvent);
    } else if (batchEvents.includes(event.type as BatchEventType)) {
      onBatchEventRef.current?.(event as BatchEvent);
    } else if (circuitEvents.includes(event.type as CircuitBreakerEventType)) {
      onCircuitBreakerEventRef.current?.(event as CircuitBreakerEvent);
    } else if (providerEvents.includes(event.type as ProviderEventType)) {
      onProviderEventRef.current?.(event as ProviderEvent);
    }
  }, []);

  // Handle incoming messages
  const handleMessage = useCallback((data: unknown) => {
    if (!isWebSocketMessage(data)) return;

    // Handle legacy format: { type: 'ai_orchestration_event', data: {...} }
    if (data.type === 'ai_orchestration_event' && data.data) {
      routeEvent(data.data as AiOrchestrationEvent);
      return;
    }

    // Handle error messages
    if (data.type === 'error') {
      onErrorRef.current?.(data.message || 'AI orchestration error');
      return;
    }

    // Handle subscription confirmations (skip routing)
    if (data.type === 'subscription.confirmed') {
      // Subscription confirmed - skip routing
      return;
    }

    // Handle new backend format: { event: 'node.execution.updated', payload: {...}, ... }
    if (data.event) {
      const frontendEventType = mapBackendEventType(data.event);
      const payload = data.payload || {};

      // Extract node execution data from payload
      const nodeExecution = payload.node_execution as Record<string, unknown> | undefined;
      const workflowRun = payload.workflow_run as Record<string, unknown> | undefined;
      const nodeInfo = nodeExecution?.node as Record<string, unknown> | undefined;

      // Build frontend-compatible event
      const event: AiOrchestrationEvent = {
        type: frontendEventType as AiOrchestrationEventType,
        workflow_id: (payload.workflow_id || payload.ai_workflow_id || workflowRun?.ai_workflow_id || '') as string,
        run_id: (payload.run_id || workflowRun?.run_id || data.resource_id || '') as string,
        node_id: (nodeInfo?.node_id as string) || undefined,
        data: {
          ...payload,
          node_execution: nodeExecution,
          workflow_run: workflowRun,
          status: (nodeExecution?.status || workflowRun?.status) as string,
        },
        timestamp: data.timestamp || new Date().toISOString(),
      } as WorkflowRunEvent;

      routeEvent(event);
    }
  }, [routeEvent, mapBackendEventType]);

  // Handle channel errors
  const handleError = useCallback((errorMessage: string) => {
    onErrorRef.current?.(errorMessage);
  }, []);

  // Subscribe to workflow events
  const subscribeToWorkflow = useCallback((workflowId: string): (() => void) => {
    if (!isConnected) {
      if (process.env.NODE_ENV === 'development') {
        console.warn('[AiOrchestrationWebSocket] Cannot subscribe: not connected');
      }
      return () => {};
    }

    const subscriptionId = `workflow_${workflowId}`;

    // Unsubscribe if already subscribed
    if (subscriptionsRef.current.has(subscriptionId)) {
      subscriptionsRef.current.get(subscriptionId)?.unsubscribe();
    }

    const unsubscribe = subscribe({
      channel: 'AiOrchestrationChannel',
      params: { type: 'workflow', workflow_id: workflowId },
      onMessage: handleMessage,
      onError: handleError
    });

    subscriptionsRef.current.set(subscriptionId, {
      id: subscriptionId,
      type: 'workflow',
      resourceId: workflowId,
      unsubscribe
    });

    return () => {
      unsubscribe();
      subscriptionsRef.current.delete(subscriptionId);
    };
  }, [isConnected, subscribe, handleMessage, handleError]);

  // Subscribe to workflow run events
  const subscribeToWorkflowRun = useCallback((workflowId: string, runId: string): (() => void) => {
    if (!isConnected) {
      if (process.env.NODE_ENV === 'development') {
        console.warn('[AiOrchestrationWebSocket] Cannot subscribe: not connected');
      }
      return () => {};
    }

    const subscriptionId = `workflow_run_${runId}`;

    if (subscriptionsRef.current.has(subscriptionId)) {
      subscriptionsRef.current.get(subscriptionId)?.unsubscribe();
    }

    const unsubscribe = subscribe({
      channel: 'AiOrchestrationChannel',
      params: { type: 'workflow_run', workflow_id: workflowId, run_id: runId },
      onMessage: handleMessage,
      onError: handleError
    });

    subscriptionsRef.current.set(subscriptionId, {
      id: subscriptionId,
      type: 'workflow_run',
      resourceId: runId,
      unsubscribe
    });

    return () => {
      unsubscribe();
      subscriptionsRef.current.delete(subscriptionId);
    };
  }, [isConnected, subscribe, handleMessage, handleError]);

  // Subscribe to agent events
  const subscribeToAgent = useCallback((agentId: string): (() => void) => {
    if (!isConnected) {
      if (process.env.NODE_ENV === 'development') {
        console.warn('[AiOrchestrationWebSocket] Cannot subscribe: not connected');
      }
      return () => {};
    }

    const subscriptionId = `agent_${agentId}`;

    if (subscriptionsRef.current.has(subscriptionId)) {
      subscriptionsRef.current.get(subscriptionId)?.unsubscribe();
    }

    const unsubscribe = subscribe({
      channel: 'AiOrchestrationChannel',
      params: { type: 'agent', agent_id: agentId },
      onMessage: handleMessage,
      onError: handleError
    });

    subscriptionsRef.current.set(subscriptionId, {
      id: subscriptionId,
      type: 'agent',
      resourceId: agentId,
      unsubscribe
    });

    return () => {
      unsubscribe();
      subscriptionsRef.current.delete(subscriptionId);
    };
  }, [isConnected, subscribe, handleMessage, handleError]);

  // Subscribe to agent team events
  const subscribeToAgentTeam = useCallback((teamId: string): (() => void) => {
    if (!isConnected) {
      if (process.env.NODE_ENV === 'development') {
        console.warn('[AiOrchestrationWebSocket] Cannot subscribe: not connected');
      }
      return () => {};
    }

    const subscriptionId = `agent_team_${teamId}`;

    if (subscriptionsRef.current.has(subscriptionId)) {
      subscriptionsRef.current.get(subscriptionId)?.unsubscribe();
    }

    const unsubscribe = subscribe({
      channel: 'AiOrchestrationChannel',
      params: { type: 'agent_team', team_id: teamId },
      onMessage: handleMessage,
      onError: handleError
    });

    subscriptionsRef.current.set(subscriptionId, {
      id: subscriptionId,
      type: 'agent_team',
      resourceId: teamId,
      unsubscribe
    });

    return () => {
      unsubscribe();
      subscriptionsRef.current.delete(subscriptionId);
    };
  }, [isConnected, subscribe, handleMessage, handleError]);

  // Subscribe to batch execution events
  const subscribeToBatch = useCallback((batchId: string): (() => void) => {
    if (!isConnected) {
      if (process.env.NODE_ENV === 'development') {
        console.warn('[AiOrchestrationWebSocket] Cannot subscribe: not connected');
      }
      return () => {};
    }

    const subscriptionId = `batch_${batchId}`;

    if (subscriptionsRef.current.has(subscriptionId)) {
      subscriptionsRef.current.get(subscriptionId)?.unsubscribe();
    }

    const unsubscribe = subscribe({
      channel: 'AiOrchestrationChannel',
      params: { type: 'batch', batch_id: batchId },
      onMessage: handleMessage,
      onError: handleError
    });

    subscriptionsRef.current.set(subscriptionId, {
      id: subscriptionId,
      type: 'batch',
      resourceId: batchId,
      unsubscribe
    });

    return () => {
      unsubscribe();
      subscriptionsRef.current.delete(subscriptionId);
    };
  }, [isConnected, subscribe, handleMessage, handleError]);

  // Subscribe to circuit breaker events
  const subscribeToCircuitBreaker = useCallback((circuitBreakerId: string): (() => void) => {
    if (!isConnected) {
      if (process.env.NODE_ENV === 'development') {
        console.warn('[AiOrchestrationWebSocket] Cannot subscribe: not connected');
      }
      return () => {};
    }

    const subscriptionId = `circuit_breaker_${circuitBreakerId}`;

    if (subscriptionsRef.current.has(subscriptionId)) {
      subscriptionsRef.current.get(subscriptionId)?.unsubscribe();
    }

    const unsubscribe = subscribe({
      channel: 'AiOrchestrationChannel',
      params: { type: 'circuit_breaker', circuit_breaker_id: circuitBreakerId },
      onMessage: handleMessage,
      onError: handleError
    });

    subscriptionsRef.current.set(subscriptionId, {
      id: subscriptionId,
      type: 'circuit_breaker',
      resourceId: circuitBreakerId,
      unsubscribe
    });

    return () => {
      unsubscribe();
      subscriptionsRef.current.delete(subscriptionId);
    };
  }, [isConnected, subscribe, handleMessage, handleError]);

  // Subscribe to provider events
  const subscribeToProvider = useCallback((providerId: string): (() => void) => {
    if (!isConnected) {
      if (process.env.NODE_ENV === 'development') {
        console.warn('[AiOrchestrationWebSocket] Cannot subscribe: not connected');
      }
      return () => {};
    }

    const subscriptionId = `provider_${providerId}`;

    if (subscriptionsRef.current.has(subscriptionId)) {
      subscriptionsRef.current.get(subscriptionId)?.unsubscribe();
    }

    const unsubscribe = subscribe({
      channel: 'AiOrchestrationChannel',
      params: { type: 'provider', provider_id: providerId },
      onMessage: handleMessage,
      onError: handleError
    });

    subscriptionsRef.current.set(subscriptionId, {
      id: subscriptionId,
      type: 'provider',
      resourceId: providerId,
      unsubscribe
    });

    return () => {
      unsubscribe();
      subscriptionsRef.current.delete(subscriptionId);
    };
  }, [isConnected, subscribe, handleMessage, handleError]);

  // Cleanup all subscriptions
  useEffect(() => {
    const subscriptions = subscriptionsRef.current;
    return () => {
      subscriptions.forEach(sub => sub.unsubscribe());
      subscriptions.clear();
    };
  }, []);

  // Handle connection errors
  useEffect(() => {
    if (connectionError) {
      onErrorRef.current?.(connectionError);
    }
  }, [connectionError]);

  return {
    isConnected,
    subscribeToWorkflow,
    subscribeToWorkflowRun,
    subscribeToAgent,
    subscribeToAgentTeam,
    subscribeToBatch,
    subscribeToCircuitBreaker,
    subscribeToProvider,
    error: connectionError
  };
};

// Export types for consumers
export type {
  WorkflowEvent,
  WorkflowRunEvent,
  AgentEvent,
  AgentTeamEvent,
  BatchEvent,
  CircuitBreakerEvent,
  ProviderEvent,
  AiOrchestrationEvent,
  WorkflowEventType,
  WorkflowRunEventType,
  AgentEventType,
  AgentTeamEventType,
  BatchEventType,
  CircuitBreakerEventType,
  ProviderEventType,
  AiOrchestrationEventType
};

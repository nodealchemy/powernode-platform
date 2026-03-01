import { useState, useEffect, useCallback, useRef } from 'react';
import { useWebSocket } from '@/shared/hooks/useWebSocket';
import type { CircuitBreakerState } from '../components/circuit-breaker/CircuitBreakerDashboard';

export interface CircuitBreakerMessage {
  event: string;
  payload: {
    breaker?: CircuitBreakerState;
    breaker_id?: string;
    state?: 'closed' | 'open' | 'half_open';
    previous_state?: 'closed' | 'open' | 'half_open';
    metadata?: Record<string, unknown>;
  };
}

export interface UseCircuitBreakerOptions {
  autoConnect?: boolean;
  breakerId?: string; // Subscribe to specific breaker
  service?: string; // Subscribe to all breakers for a service
  onBreakerStateChange?: (breaker: CircuitBreakerState) => void;
  onBreakerOpen?: (breaker: CircuitBreakerState) => void;
  onBreakerClosed?: (breaker: CircuitBreakerState) => void;
  onBreakerHalfOpen?: (breaker: CircuitBreakerState) => void;
  onFailure?: (breakerId: string, error: unknown) => void;
}

export interface UseCircuitBreakerReturn {
  breakers: CircuitBreakerState[];
  isConnected: boolean;
  subscribe: (breakerId?: string) => void;
  unsubscribe: () => void;
  getBreakerById: (breakerId: string) => CircuitBreakerState | undefined;
  getBreakersByService: (service: string) => CircuitBreakerState[];
}

/**
 * Custom hook for managing circuit breaker state with real-time WebSocket updates
 *
 * @example
 * ```tsx
 * const { breakers, isConnected } = useCircuitBreaker({
 *   autoConnect: true,
 *   onBreakerStateChange: (breaker) => {
 *   },
 *   onBreakerOpen: (breaker) => {
 *     showNotification(`Circuit breaker ${breaker.name} opened!`);
 *   }
 * });
 * ```
 */
export const useCircuitBreaker = (options: UseCircuitBreakerOptions = {}): UseCircuitBreakerReturn => {
  const {
    autoConnect = false,
    breakerId,
    service,
    onBreakerStateChange,
    onBreakerOpen,
    onBreakerClosed,
    onBreakerHalfOpen,
    onFailure
  } = options;

  const [breakers, setBreakers] = useState<Map<string, CircuitBreakerState>>(new Map());
  const callbacksRef = useRef({ onBreakerStateChange, onBreakerOpen, onBreakerClosed, onBreakerHalfOpen, onFailure });

  // Update callbacks ref when they change
  useEffect(() => {
    callbacksRef.current = { onBreakerStateChange, onBreakerOpen, onBreakerClosed, onBreakerHalfOpen, onFailure };
  }, [onBreakerStateChange, onBreakerOpen, onBreakerClosed, onBreakerHalfOpen, onFailure]);

  // Handle incoming circuit breaker messages
  const handleMessage = useCallback((message: CircuitBreakerMessage) => {
    const { event, payload } = message;

    switch (event) {
      case 'circuit_breaker.state_changed':
      case 'breaker_state_changed': {
        if (!payload.breaker) break;

        setBreakers(prev => {
          const updated = new Map(prev);
          const oldBreaker = updated.get(payload.breaker!.id);
          updated.set(payload.breaker!.id, payload.breaker!);

          // Trigger state-specific callbacks
          if (payload.breaker!.state !== oldBreaker?.state) {
            callbacksRef.current.onBreakerStateChange?.(payload.breaker!);

            if (payload.breaker!.state === 'open') {
              callbacksRef.current.onBreakerOpen?.(payload.breaker!);
            } else if (payload.breaker!.state === 'closed') {
              callbacksRef.current.onBreakerClosed?.(payload.breaker!);
            } else if (payload.breaker!.state === 'half_open') {
              callbacksRef.current.onBreakerHalfOpen?.(payload.breaker!);
            }
          }

          return updated;
        });
        break;
      }

      case 'circuit_breaker.failure':
      case 'breaker_failure': {
        if (!payload.breaker_id) break;

        callbacksRef.current.onFailure?.(payload.breaker_id, payload.metadata);

        // Update failure count
        setBreakers(prev => {
          const updated = new Map(prev);
          const breaker = updated.get(payload.breaker_id!);
          if (breaker) {
            updated.set(payload.breaker_id!, {
              ...breaker,
              failure_count: breaker.failure_count + 1,
              total_failures: breaker.total_failures + 1,
              last_failure_at: new Date().toISOString()
            });
          }
          return updated;
        });
        break;
      }

      case 'circuit_breaker.success':
      case 'breaker_success': {
        if (!payload.breaker_id) break;

        // Update success count
        setBreakers(prev => {
          const updated = new Map(prev);
          const breaker = updated.get(payload.breaker_id!);
          if (breaker) {
            updated.set(payload.breaker_id!, {
              ...breaker,
              success_count: breaker.success_count + 1,
              total_successes: breaker.total_successes + 1,
              failure_count: 0, // Reset consecutive failures on success
              last_success_at: new Date().toISOString()
            });
          }
          return updated;
        });
        break;
      }

      case 'circuit_breaker.opened': {
        if (!payload.breaker) break;

        setBreakers(prev => {
          const updated = new Map(prev);
          updated.set(payload.breaker!.id, {
            ...payload.breaker!,
            state: 'open',
            opened_at: new Date().toISOString()
          });
          return updated;
        });

        callbacksRef.current.onBreakerOpen?.(payload.breaker!);
        break;
      }

      case 'circuit_breaker.closed': {
        if (!payload.breaker) break;

        setBreakers(prev => {
          const updated = new Map(prev);
          updated.set(payload.breaker!.id, {
            ...payload.breaker!,
            state: 'closed',
            closed_at: new Date().toISOString(),
            failure_count: 0,
            success_count: 0
          });
          return updated;
        });

        callbacksRef.current.onBreakerClosed?.(payload.breaker!);
        break;
      }

      case 'circuit_breaker.half_opened': {
        if (!payload.breaker) break;

        setBreakers(prev => {
          const updated = new Map(prev);
          updated.set(payload.breaker!.id, {
            ...payload.breaker!,
            state: 'half_open',
            success_count: 0
          });
          return updated;
        });

        callbacksRef.current.onBreakerHalfOpen?.(payload.breaker!);
        break;
      }

      case 'circuit_breaker.reset': {
        if (!payload.breaker) break;

        setBreakers(prev => {
          const updated = new Map(prev);
          updated.set(payload.breaker!.id, {
            ...payload.breaker!,
            state: 'closed',
            failure_count: 0,
            success_count: 0,
            closed_at: new Date().toISOString()
          });
          return updated;
        });
        break;
      }

      default:
        // Unknown message type - ignored
        break;
    }
  }, []);

  // WebSocket connection
  const { isConnected, subscribe: wsSubscribe } = useWebSocket();

  // Store unsubscribe function
  const unsubscribeRef = useRef<(() => void) | null>(null);

  // Subscribe to circuit breakers on mount
  useEffect(() => {
    if (autoConnect && isConnected) {
    let subscriptionParams: Record<string, string> = {};

      if (breakerId) {
        // Subscribe to specific breaker
        subscriptionParams = {
          type: 'circuit_breaker',
          resource_id: breakerId
        };
      } else if (service) {
        // Subscribe to all breakers for a service
        subscriptionParams = {
          type: 'circuit_breaker_service',
          service_name: service
        };
      } else {
        // Subscribe to all circuit breakers
        subscriptionParams = {
          type: 'circuit_breaker',
          resource_id: 'all'
        };
      }

      // Subscribe and store cleanup function
      unsubscribeRef.current = wsSubscribe({
        channel: 'AiOrchestrationChannel',
        params: subscriptionParams,
        onMessage: (data) => handleMessage(data as CircuitBreakerMessage)
      });
    }

    return () => {
      if (unsubscribeRef.current) {
        unsubscribeRef.current();
        unsubscribeRef.current = null;
      }
    };
  }, [autoConnect, isConnected, breakerId, service, wsSubscribe, handleMessage]);

  // Get breaker by ID
  const getBreakerById = useCallback((id: string): CircuitBreakerState | undefined => {
    return breakers.get(id);
  }, [breakers]);

  // Get breakers by service
  const getBreakersByService = useCallback((serviceName: string): CircuitBreakerState[] => {
    return Array.from(breakers.values()).filter(b => b.service === serviceName);
  }, [breakers]);

  // Wrapper subscribe function for external use
  const subscribe = useCallback((targetBreakerId?: string) => {
    if (!isConnected) return;

    const subscriptionParams: Record<string, string> = targetBreakerId
      ? { type: 'circuit_breaker', resource_id: targetBreakerId }
      : { type: 'circuit_breaker', resource_id: 'all' };

    unsubscribeRef.current = wsSubscribe({
      channel: 'AiOrchestrationChannel',
      params: subscriptionParams,
      onMessage: (data) => handleMessage(data as CircuitBreakerMessage)
    });
  }, [isConnected, wsSubscribe, handleMessage]);

  // Wrapper unsubscribe function for external use
  const unsubscribe = useCallback(() => {
    if (unsubscribeRef.current) {
      unsubscribeRef.current();
      unsubscribeRef.current = null;
    }
  }, []);

  return {
    breakers: Array.from(breakers.values()),
    isConnected,
    subscribe,
    unsubscribe,
    getBreakerById,
    getBreakersByService
  };
};

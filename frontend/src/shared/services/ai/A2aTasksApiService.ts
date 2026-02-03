import { BaseApiService, PaginatedResponse } from './BaseApiService';
import type {
  A2aTask,
  A2aTaskFilters,
  SubmitA2aTaskRequest,
  A2aTaskResponse,
  A2aTaskJson,
  A2aTaskEventsResponse,
  A2aArtifact,
} from './types/a2a-types';

/**
 * A2aTasksApiService - A2A Tasks API Client
 *
 * Provides access to A2A task submission, status, and event streaming endpoints.
 *
 * Endpoint structure:
 * - GET    /api/v1/ai/a2a/tasks
 * - POST   /api/v1/ai/a2a/tasks
 * - GET    /api/v1/ai/a2a/tasks/:task_id
 * - POST   /api/v1/ai/a2a/tasks/:task_id/cancel
 * - POST   /api/v1/ai/a2a/tasks/:task_id/input
 * - GET    /api/v1/ai/a2a/tasks/:task_id/events
 * - GET    /api/v1/ai/a2a/tasks/:task_id/events/poll
 * - GET    /api/v1/ai/a2a/tasks/:task_id/artifacts
 * - GET    /api/v1/ai/a2a/tasks/:task_id/artifacts/:artifact_id
 * - POST   /api/v1/ai/a2a/tasks/:task_id/push_notifications
 */

class A2aTasksApiService extends BaseApiService {
  private basePath = '/ai/a2a/tasks';

  // ===================================================================
  // Task Operations
  // ===================================================================

  /**
   * Get list of A2A tasks with optional filters
   * GET /api/v1/ai/a2a/tasks
   */
  async getTasks(filters?: A2aTaskFilters): Promise<PaginatedResponse<A2aTask>> {
    const queryString = this.buildQueryString(filters);
    return this.get<PaginatedResponse<A2aTask>>(this.basePath + queryString);
  }

  /**
   * Get single task by task_id
   * GET /api/v1/ai/a2a/tasks/:task_id
   */
  async getTask(taskId: string): Promise<{ task: A2aTaskJson }> {
    return this.get<{ task: A2aTaskJson }>(`${this.basePath}/${taskId}`);
  }

  /**
   * Get task details
   * GET /api/v1/ai/a2a/tasks/:task_id
   */
  async getTaskDetails(taskId: string): Promise<{ task: A2aTask }> {
    return this.get<{ task: A2aTask }>(`${this.basePath}/${taskId}`);
  }

  /**
   * Submit a new A2A task (tasks/send)
   * POST /api/v1/ai/a2a/tasks
   */
  async submitTask(request: SubmitA2aTaskRequest): Promise<A2aTaskResponse> {
    return this.post<A2aTaskResponse>(this.basePath, request);
  }

  /**
   * Cancel a task
   * POST /api/v1/ai/a2a/tasks/:task_id/cancel
   */
  async cancelTask(taskId: string, reason?: string): Promise<{ task: A2aTaskJson }> {
    return this.post<{ task: A2aTaskJson }>(`${this.basePath}/${taskId}/cancel`, { reason });
  }

  /**
   * Provide input for a task requiring input
   * POST /api/v1/ai/a2a/tasks/:task_id/input
   */
  async provideInput(taskId: string, input: unknown): Promise<{ task: A2aTaskJson }> {
    return this.post<{ task: A2aTaskJson }>(`${this.basePath}/${taskId}/input`, { input });
  }

  // ===================================================================
  // Event Streaming
  // ===================================================================

  /**
   * Get task events (polling alternative)
   * GET /api/v1/ai/a2a/tasks/:task_id/events/poll
   */
  async pollEvents(taskId: string, since?: string, limit?: number): Promise<A2aTaskEventsResponse> {
    const params = new URLSearchParams();
    if (since) params.append('since', since);
    if (limit) params.append('limit', String(limit));
    const queryString = params.toString() ? `?${params.toString()}` : '';

    return this.get<A2aTaskEventsResponse>(`${this.basePath}/${taskId}/events/poll${queryString}`);
  }

  /**
   * Create SSE connection for task events
   * GET /api/v1/ai/a2a/tasks/:task_id/events
   *
   * Returns an EventSource for real-time event streaming
   */
  createEventSource(taskId: string, lastEventId?: string): EventSource {
    const url = `/api/v1${this.basePath}/${taskId}/events`;
    const eventSource = new EventSource(url);

    if (lastEventId) {
      // Set Last-Event-ID header for resumption
      // Note: EventSource doesn't support custom headers directly
      // The server should handle reconnection via query params if needed
    }

    return eventSource;
  }

  /**
   * Subscribe to task events with callbacks
   */
  subscribeToTask(
    taskId: string,
    callbacks: {
      onStatus?: (task: A2aTaskJson) => void;
      onProgress?: (progress: { current: number; total: number; message?: string }) => void;
      onArtifact?: (artifact: { artifactId: string; name: string; mimeType?: string }) => void;
      onError?: (error: unknown) => void;
      onComplete?: (status: string) => void;
    }
  ): { eventSource: EventSource; close: () => void } {
    const eventSource = this.createEventSource(taskId);

    eventSource.addEventListener('task.status', (event) => {
      const data = JSON.parse((event as MessageEvent).data);
      callbacks.onStatus?.(data);
    });

    eventSource.addEventListener('task.progress', (event) => {
      const data = JSON.parse((event as MessageEvent).data);
      callbacks.onProgress?.(data);
    });

    eventSource.addEventListener('task.artifact', (event) => {
      const data = JSON.parse((event as MessageEvent).data);
      callbacks.onArtifact?.(data);
    });

    eventSource.addEventListener('task.complete', (event) => {
      const data = JSON.parse((event as MessageEvent).data);
      callbacks.onComplete?.(data.status);
      eventSource.close();
    });

    eventSource.onerror = (error) => {
      callbacks.onError?.(error);
    };

    return {
      eventSource,
      close: () => eventSource.close(),
    };
  }

  // ===================================================================
  // Artifacts
  // ===================================================================

  /**
   * Get task artifacts
   * GET /api/v1/ai/a2a/tasks/:task_id/artifacts
   */
  async getArtifacts(taskId: string): Promise<{ artifacts: A2aArtifact[] }> {
    return this.get<{ artifacts: A2aArtifact[] }>(`${this.basePath}/${taskId}/artifacts`);
  }

  /**
   * Get specific artifact
   * GET /api/v1/ai/a2a/tasks/:task_id/artifacts/:artifact_id
   */
  async getArtifact(taskId: string, artifactId: string): Promise<{ artifact: A2aArtifact }> {
    return this.get<{ artifact: A2aArtifact }>(`${this.basePath}/${taskId}/artifacts/${artifactId}`);
  }

  // ===================================================================
  // Push Notifications
  // ===================================================================

  /**
   * Configure push notifications for a task
   * POST /api/v1/ai/a2a/tasks/:task_id/push_notifications
   */
  async configurePushNotifications(
    taskId: string,
    config: {
      url: string;
      token?: string;
      authentication?: Record<string, unknown>;
      events?: string[];
    }
  ): Promise<{ task_id: string; push_configured: boolean }> {
    return this.post<{ task_id: string; push_configured: boolean }>(
      `${this.basePath}/${taskId}/push_notifications`,
      config
    );
  }
}

// Export singleton instance
export const a2aTasksApiService = new A2aTasksApiService();
export default a2aTasksApiService;

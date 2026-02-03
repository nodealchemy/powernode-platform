import { BaseApiService, PaginatedResponse } from './BaseApiService';
import type {
  RalphLoop,
  RalphLoopSummary,
  RalphTask,
  RalphTaskSummary,
  RalphIteration,
  RalphIterationSummary,
  CreateRalphLoopRequest,
  UpdateRalphLoopRequest,
  UpdateRalphTaskExecutorRequest,
  RalphLoopFilters,
  RalphTaskFilters,
  RalphIterationFilters,
  ParsePrdRequest,
  RalphStatistics,
  RalphProgress,
  PauseScheduleResponse,
  ResumeScheduleResponse,
  RegenerateWebhookTokenResponse,
} from './types/ralph-types';

/**
 * RalphLoopsApiService - Ralph Loops API Client
 *
 * Provides access to Ralph autonomous AI agent loop execution.
 *
 * Endpoint structure:
 * - GET    /api/v1/ai/ralph_loops
 * - POST   /api/v1/ai/ralph_loops
 * - GET    /api/v1/ai/ralph_loops/:id
 * - PATCH  /api/v1/ai/ralph_loops/:id
 * - DELETE /api/v1/ai/ralph_loops/:id
 * - POST   /api/v1/ai/ralph_loops/:id/start
 * - POST   /api/v1/ai/ralph_loops/:id/pause
 * - POST   /api/v1/ai/ralph_loops/:id/resume
 * - POST   /api/v1/ai/ralph_loops/:id/cancel
 * - POST   /api/v1/ai/ralph_loops/:id/run_iteration
 * - POST   /api/v1/ai/ralph_loops/:id/parse_prd
 * - GET    /api/v1/ai/ralph_loops/:id/tasks
 * - GET    /api/v1/ai/ralph_loops/:id/tasks/:task_id
 * - GET    /api/v1/ai/ralph_loops/:id/iterations
 * - GET    /api/v1/ai/ralph_loops/:id/iterations/:iteration_id
 * - GET    /api/v1/ai/ralph_loops/:id/learnings
 * - GET    /api/v1/ai/ralph_loops/:id/progress
 * - GET    /api/v1/ai/ralph_loops/statistics
 */

class RalphLoopsApiService extends BaseApiService {
  private basePath = '/ai/ralph_loops';

  // ===================================================================
  // Loop Operations
  // ===================================================================

  /**
   * Get list of Ralph loops
   */
  async getLoops(filters?: RalphLoopFilters): Promise<PaginatedResponse<RalphLoopSummary>> {
    const queryString = this.buildQueryString(filters);
    return this.get<PaginatedResponse<RalphLoopSummary>>(this.basePath + queryString);
  }

  /**
   * Get single loop by ID
   */
  async getLoop(loopId: string): Promise<{ ralph_loop: RalphLoop }> {
    return this.get<{ ralph_loop: RalphLoop }>(`${this.basePath}/${loopId}`);
  }

  /**
   * Create a new Ralph loop
   */
  async createLoop(request: CreateRalphLoopRequest): Promise<{ ralph_loop: RalphLoop }> {
    return this.post<{ ralph_loop: RalphLoop }>(this.basePath, { ralph_loop: request });
  }

  /**
   * Update a Ralph loop
   */
  async updateLoop(loopId: string, request: UpdateRalphLoopRequest): Promise<{ ralph_loop: RalphLoop }> {
    return this.patch<{ ralph_loop: RalphLoop }>(`${this.basePath}/${loopId}`, { ralph_loop: request });
  }

  /**
   * Delete a Ralph loop
   */
  async deleteLoop(loopId: string): Promise<{ message: string }> {
    return this.delete<{ message: string }>(`${this.basePath}/${loopId}`);
  }

  // ===================================================================
  // Execution Control
  // ===================================================================

  /**
   * Start loop execution
   */
  async startLoop(loopId: string): Promise<{ ralph_loop: RalphLoop; message: string }> {
    return this.post<{ ralph_loop: RalphLoop; message: string }>(`${this.basePath}/${loopId}/start`);
  }

  /**
   * Pause loop execution
   */
  async pauseLoop(loopId: string): Promise<{ ralph_loop: RalphLoop; message: string }> {
    return this.post<{ ralph_loop: RalphLoop; message: string }>(`${this.basePath}/${loopId}/pause`);
  }

  /**
   * Resume paused loop
   */
  async resumeLoop(loopId: string): Promise<{ ralph_loop: RalphLoop; message: string }> {
    return this.post<{ ralph_loop: RalphLoop; message: string }>(`${this.basePath}/${loopId}/resume`);
  }

  /**
   * Cancel loop execution
   */
  async cancelLoop(loopId: string, reason?: string): Promise<{ ralph_loop: RalphLoop; message: string }> {
    return this.post<{ ralph_loop: RalphLoop; message: string }>(`${this.basePath}/${loopId}/cancel`, { reason });
  }

  /**
   * Reset a terminal loop back to pending
   */
  async resetLoop(loopId: string): Promise<{ ralph_loop: RalphLoop; message: string }> {
    return this.post<{ ralph_loop: RalphLoop; message: string }>(`${this.basePath}/${loopId}/reset`);
  }

  /**
   * Run a single iteration
   */
  async runIteration(loopId: string): Promise<{ iteration: RalphIteration; ralph_loop: RalphLoop }> {
    return this.post<{ iteration: RalphIteration; ralph_loop: RalphLoop }>(`${this.basePath}/${loopId}/run_iteration`);
  }

  /**
   * Parse PRD and create/update tasks
   */
  async parsePrd(loopId: string, request: ParsePrdRequest): Promise<{ tasks: RalphTask[]; message: string }> {
    // Backend expects { prd: { tasks: [...] } }
    return this.post<{ tasks: RalphTask[]; message: string }>(`${this.basePath}/${loopId}/parse_prd`, {
      prd: request.prd_json,
    });
  }

  // ===================================================================
  // Task Operations
  // ===================================================================

  /**
   * Get tasks for a loop
   */
  async getTasks(loopId: string, filters?: RalphTaskFilters): Promise<PaginatedResponse<RalphTaskSummary>> {
    const queryString = this.buildQueryString(filters);
    return this.get<PaginatedResponse<RalphTaskSummary>>(`${this.basePath}/${loopId}/tasks${queryString}`);
  }

  /**
   * Get single task
   */
  async getTask(loopId: string, taskId: string): Promise<{ task: RalphTask }> {
    return this.get<{ task: RalphTask }>(`${this.basePath}/${loopId}/tasks/${taskId}`);
  }

  /**
   * Update task executor configuration
   */
  async updateTask(loopId: string, taskId: string, request: UpdateRalphTaskExecutorRequest): Promise<{ task: RalphTask }> {
    return this.patch<{ task: RalphTask }>(`${this.basePath}/${loopId}/tasks/${taskId}`, { task: request });
  }

  // ===================================================================
  // Iteration Operations
  // ===================================================================

  /**
   * Get iterations for a loop
   */
  async getIterations(loopId: string, filters?: RalphIterationFilters): Promise<PaginatedResponse<RalphIterationSummary>> {
    const queryString = this.buildQueryString(filters);
    return this.get<PaginatedResponse<RalphIterationSummary>>(`${this.basePath}/${loopId}/iterations${queryString}`);
  }

  /**
   * Get single iteration
   */
  async getIteration(loopId: string, iterationId: string): Promise<{ iteration: RalphIteration }> {
    return this.get<{ iteration: RalphIteration }>(`${this.basePath}/${loopId}/iterations/${iterationId}`);
  }

  // ===================================================================
  // Progress & Learnings
  // ===================================================================

  /**
   * Get learnings for a loop
   */
  async getLearnings(loopId: string): Promise<{ learnings: string[] }> {
    return this.get<{ learnings: string[] }>(`${this.basePath}/${loopId}/learnings`);
  }

  /**
   * Get progress for a loop
   */
  async getProgress(loopId: string): Promise<RalphProgress> {
    return this.get<RalphProgress>(`${this.basePath}/${loopId}/progress`);
  }

  // ===================================================================
  // Statistics
  // ===================================================================

  /**
   * Get Ralph loops statistics
   */
  async getStatistics(): Promise<RalphStatistics> {
    return this.get<RalphStatistics>(`${this.basePath}/statistics`);
  }

  // ===================================================================
  // Scheduling Operations
  // ===================================================================

  /**
   * Pause schedule for a loop
   */
  async pauseSchedule(loopId: string, reason?: string): Promise<PauseScheduleResponse> {
    return this.post<PauseScheduleResponse>(`${this.basePath}/${loopId}/pause_schedule`, { reason });
  }

  /**
   * Resume schedule for a loop
   */
  async resumeSchedule(loopId: string): Promise<ResumeScheduleResponse> {
    return this.post<ResumeScheduleResponse>(`${this.basePath}/${loopId}/resume_schedule`);
  }

  /**
   * Regenerate webhook token for event-triggered loops
   */
  async regenerateWebhookToken(loopId: string): Promise<RegenerateWebhookTokenResponse> {
    return this.post<RegenerateWebhookTokenResponse>(`${this.basePath}/${loopId}/regenerate_webhook_token`);
  }
}

export const ralphLoopsApi = new RalphLoopsApiService();

import { BaseApiService, type QueryFilters } from '@/shared/services/ai/BaseApiService';
import type { TraceData } from '../components/TraceViewer';

/**
 * Summary row returned by the execution_traces index endpoint.
 * (Distinct from TraceViewer's detail `TraceSummary`, which is the
 * per-trace span rollup.)
 */
export interface ExecutionTraceSummary {
  trace_id: string;
  name: string;
  type: string;
  status: 'pending' | 'running' | 'completed' | 'failed' | 'cancelled';
  started_at: string | null;
  completed_at: string | null;
  duration_ms: number | null;
  span_count: number;
  total_tokens: number;
  total_cost: number;
  error: boolean;
}

export interface ExecutionTraceFilters {
  type?: string;
  status?: string;
  limit?: number;
}

/**
 * executionTracesApi — distributed-trace read API.
 *
 * Replaces the previous raw `fetch('/api/v1/ai/execution_traces')` in
 * TraceList, which bypassed the shared auth interceptor (JWT Bearer +
 * token refresh) and relied on cookie auth that the platform does not use.
 * Extends BaseApiService so all calls flow through the authenticated `api`
 * client and the standard `{ success, data }` envelope unwrapping.
 *
 * Backend: GET /api/v1/ai/execution_traces (index → data: TraceSummary[])
 *          GET /api/v1/ai/execution_traces/:id (show → data: TraceData)
 */
class ExecutionTracesApiService extends BaseApiService {
  async listTraces(filters: ExecutionTraceFilters = {}): Promise<ExecutionTraceSummary[]> {
    const queryString = this.buildQueryString(filters as QueryFilters);
    return this.get<ExecutionTraceSummary[]>(`${this.baseNamespace}/execution_traces${queryString}`);
  }

  async getTrace(traceId: string): Promise<TraceData> {
    return this.get<TraceData>(`${this.baseNamespace}/execution_traces/${traceId}`);
  }
}

export const executionTracesApi = new ExecutionTracesApiService();
export default executionTracesApi;

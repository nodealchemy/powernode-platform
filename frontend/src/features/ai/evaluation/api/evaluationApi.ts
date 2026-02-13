import { apiClient } from '@/shared/services/apiClient';
import type { EvaluationResult, PerformanceBenchmark, AgentScoreTrend } from '../types/evaluation';

export async function fetchEvaluationResults(params?: {
  agent_id?: string;
  from?: string;
  to?: string;
  limit?: number;
}): Promise<EvaluationResult[]> {
  const response = await apiClient.get('/ai/learning/evaluation_results', { params });
  return response.data?.results || [];
}

export async function fetchAgentTrends(): Promise<AgentScoreTrend[]> {
  const response = await apiClient.get('/ai/learning/agent_trends');
  return response.data?.trends || [];
}

export async function fetchBenchmarks(params?: {
  status?: string;
  agent_id?: string;
  limit?: number;
}): Promise<PerformanceBenchmark[]> {
  const response = await apiClient.get('/ai/learning/benchmarks', { params });
  return response.data?.benchmarks || [];
}

export async function createBenchmark(data: {
  name: string;
  agent_id?: string;
  workflow_id?: string;
  thresholds?: Record<string, number>;
}): Promise<PerformanceBenchmark> {
  const response = await apiClient.post('/ai/learning/benchmarks', data);
  return response.data?.benchmark;
}

export async function runBenchmark(id: string): Promise<{
  benchmark: PerformanceBenchmark;
  results: Record<string, unknown>;
}> {
  const response = await apiClient.post(`/ai/learning/benchmarks/${id}/run`);
  return response.data;
}

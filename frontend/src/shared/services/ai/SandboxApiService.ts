/**
 * Sandbox API Service
 * Phase 4: Enterprise AI Agent Testing Infrastructure
 *
 * Revenue Model: Sandbox environments + testing infrastructure
 * - Basic sandbox: included
 * - Advanced testing: $99/mo (recording, playback)
 * - Performance profiling: $199/mo
 * - Enterprise (dedicated environments): $499/mo
 */

import { BaseApiService, PaginatedResponse, QueryFilters } from './BaseApiService';

// Types
export interface Sandbox {
  id: string;
  name: string;
  description: string | null;
  sandbox_type: 'standard' | 'isolated' | 'production_mirror' | 'performance' | 'security';
  status: 'inactive' | 'active' | 'paused' | 'expired' | 'deleted';
  is_isolated: boolean;
  recording_enabled: boolean;
  test_runs_count: number;
  total_executions: number;
  last_used_at: string | null;
  expires_at: string | null;
  created_at: string;
  // Detailed fields
  configuration?: Record<string, unknown>;
  mock_providers?: Record<string, unknown>;
  environment_variables?: Record<string, unknown>;
  resource_limits?: Record<string, unknown>;
}

export interface TestScenario {
  id: string;
  name: string;
  description: string | null;
  scenario_type: 'unit' | 'integration' | 'regression' | 'performance' | 'security' | 'chaos' | 'custom';
  status: 'draft' | 'active' | 'disabled' | 'archived';
  target_type: 'workflow' | 'agent' | null;
  target_workflow_id: string | null;
  target_agent_id: string | null;
  input_data: Record<string, unknown>;
  expected_output: Record<string, unknown>;
  assertions: unknown[];
  timeout_seconds: number;
  run_count: number;
  pass_count: number;
  fail_count: number;
  pass_rate: number | null;
  last_run_at: string | null;
  created_at: string;
}

export interface MockResponse {
  id: string;
  name: string;
  provider_type: string;
  model_name: string | null;
  endpoint: string | null;
  match_type: 'exact' | 'contains' | 'regex' | 'semantic' | 'always';
  match_criteria: Record<string, unknown>;
  response_data: Record<string, unknown>;
  latency_ms: number;
  error_rate: number;
  is_active: boolean;
  priority: number;
  hit_count: number;
  last_hit_at: string | null;
  created_at: string;
}

export interface TestRun {
  id: string;
  run_id: string;
  run_type: 'manual' | 'scheduled' | 'ci_triggered' | 'regression' | 'smoke';
  status: 'pending' | 'running' | 'completed' | 'failed' | 'cancelled' | 'timeout';
  total_scenarios: number;
  passed_scenarios: number;
  failed_scenarios: number;
  skipped_scenarios: number;
  pass_rate: number;
  duration_ms: number | null;
  started_at: string | null;
  completed_at: string | null;
  created_at: string;
  // Detailed fields
  scenario_ids?: string[];
  total_assertions?: number;
  passed_assertions?: number;
  failed_assertions?: number;
  summary?: Record<string, unknown>;
  environment?: Record<string, unknown>;
  results?: TestResult[];
}

export interface TestResult {
  id: string;
  result_id: string;
  status: 'passed' | 'failed' | 'skipped' | 'error' | 'timeout';
  scenario_id: string;
  input_used: Record<string, unknown>;
  actual_output: Record<string, unknown>;
  assertion_results: unknown[];
  error_details: Record<string, unknown>;
  duration_ms: number | null;
  tokens_used: number;
  cost_usd: number;
  retry_attempt: number;
}

export interface PerformanceBenchmark {
  id: string;
  benchmark_id: string;
  name: string;
  description: string | null;
  status: 'active' | 'paused' | 'archived';
  target_workflow_id: string | null;
  target_agent_id: string | null;
  baseline_metrics: Record<string, unknown>;
  thresholds: Record<string, unknown>;
  sample_size: number;
  run_count: number;
  latest_results: Record<string, unknown>;
  latest_score: number | null;
  trend: 'improving' | 'stable' | 'degrading' | null;
  last_run_at: string | null;
  created_at: string;
}

export interface AbTest {
  id: string;
  test_id: string;
  name: string;
  description: string | null;
  status: 'draft' | 'running' | 'paused' | 'completed' | 'cancelled';
  target_type: 'workflow' | 'agent' | 'prompt' | 'model' | 'provider';
  target_id: string;
  variants: unknown[];
  traffic_allocation: Record<string, number>;
  success_metrics: string[];
  total_impressions: number;
  total_conversions: number;
  winning_variant: string | null;
  statistical_significance: number | null;
  started_at: string | null;
  ended_at: string | null;
  created_at: string;
}

export interface AbTestResults {
  test_id: string;
  status: string;
  total_impressions: number;
  total_conversions: number;
  variants: Record<string, {
    name: string;
    impressions: number;
    conversions: number;
    conversion_rate: number;
  }>;
  has_sufficient_data: boolean;
  statistical_significance: number | null;
  winning_variant: string | null;
}

export interface SandboxAnalytics {
  test_runs: {
    total: number;
    by_status: Record<string, number>;
    recent: TestRun[];
  };
  scenarios: {
    total: number;
    active: number;
    by_type: Record<string, number>;
    average_pass_rate: number | null;
  };
  recordings: {
    total: number;
    by_type: Record<string, number>;
  };
  usage: {
    total_executions: number;
    last_used_at: string | null;
  };
}

export interface SandboxFilters extends QueryFilters {
  sandbox_type?: string;
}

class SandboxApiService extends BaseApiService {
  private basePath = '/ai/sandboxes';
  private abTestsPath = '/ai/ab_tests';

  // Sandboxes
  async getSandboxes(filters: SandboxFilters = {}): Promise<PaginatedResponse<Sandbox>> {
    const queryString = this.buildQueryString(filters);
    return this.get<PaginatedResponse<Sandbox>>(`${this.basePath}${queryString}`);
  }

  async createSandbox(data: {
    name: string;
    sandbox_type?: string;
    description?: string;
    configuration?: Record<string, unknown>;
    expires_at?: string;
  }): Promise<{ sandbox: Sandbox }> {
    return this.post(`${this.basePath}`, data);
  }

  async getSandbox(id: string): Promise<{ sandbox: Sandbox }> {
    return this.get(`${this.basePath}/${id}`);
  }

  async updateSandbox(
    id: string,
    data: Partial<Pick<Sandbox, 'name' | 'description' | 'sandbox_type' | 'configuration' | 'expires_at'>>
  ): Promise<{ sandbox: Sandbox }> {
    return this.put(`${this.basePath}/${id}`, data);
  }

  async deleteSandbox(id: string): Promise<{ message: string }> {
    return this.delete(`${this.basePath}/${id}`);
  }

  async activateSandbox(id: string): Promise<{ sandbox: Sandbox }> {
    return this.put(`${this.basePath}/${id}/activate`);
  }

  async deactivateSandbox(id: string): Promise<{ sandbox: Sandbox }> {
    return this.put(`${this.basePath}/${id}/deactivate`);
  }

  async getSandboxAnalytics(id: string): Promise<{ analytics: SandboxAnalytics }> {
    return this.get(`${this.basePath}/${id}/analytics`);
  }

  // Scenarios
  async getScenarios(sandboxId: string, page = 1, perPage = 20): Promise<PaginatedResponse<TestScenario>> {
    const queryString = this.buildQueryString({ page, per_page: perPage });
    return this.get<PaginatedResponse<TestScenario>>(`${this.basePath}/${sandboxId}/scenarios${queryString}`);
  }

  async createScenario(
    sandboxId: string,
    data: {
      name: string;
      scenario_type: string;
      target_workflow_id?: string;
      target_agent_id?: string;
      description?: string;
      input_data?: Record<string, unknown>;
      expected_output?: Record<string, unknown>;
      assertions?: unknown[];
      timeout_seconds?: number;
    }
  ): Promise<{ scenario: TestScenario }> {
    return this.post(`${this.basePath}/${sandboxId}/scenarios`, data);
  }

  // Mocks
  async getMocks(sandboxId: string, page = 1, perPage = 20): Promise<PaginatedResponse<MockResponse>> {
    const queryString = this.buildQueryString({ page, per_page: perPage });
    return this.get<PaginatedResponse<MockResponse>>(`${this.basePath}/${sandboxId}/mocks${queryString}`);
  }

  async createMock(
    sandboxId: string,
    data: {
      name: string;
      provider_type: string;
      match_type?: string;
      match_criteria?: Record<string, unknown>;
      response_data?: Record<string, unknown>;
      latency_ms?: number;
      error_rate?: number;
    }
  ): Promise<{ mock: MockResponse }> {
    return this.post(`${this.basePath}/${sandboxId}/mocks`, data);
  }

  // Test Runs
  async getRuns(sandboxId: string, page = 1, perPage = 20): Promise<PaginatedResponse<TestRun>> {
    const queryString = this.buildQueryString({ page, per_page: perPage });
    return this.get<PaginatedResponse<TestRun>>(`${this.basePath}/${sandboxId}/runs${queryString}`);
  }

  async createRun(
    sandboxId: string,
    data: {
      scenario_ids?: string[];
      run_type?: string;
      environment?: Record<string, unknown>;
    }
  ): Promise<{ run: TestRun }> {
    return this.post(`${this.basePath}/${sandboxId}/runs`, data);
  }

  async getRun(sandboxId: string, runId: string): Promise<{ run: TestRun }> {
    return this.get(`${this.basePath}/${sandboxId}/runs/${runId}`);
  }

  async executeRun(sandboxId: string, runId: string): Promise<{ run: TestRun }> {
    return this.post(`${this.basePath}/${sandboxId}/runs/${runId}/execute`);
  }

  // Benchmarks
  async getBenchmarks(sandboxId: string, page = 1, perPage = 20): Promise<PaginatedResponse<PerformanceBenchmark>> {
    const queryString = this.buildQueryString({ page, per_page: perPage });
    return this.get<PaginatedResponse<PerformanceBenchmark>>(`${this.basePath}/${sandboxId}/benchmarks${queryString}`);
  }

  async createBenchmark(
    sandboxId: string,
    data: {
      name: string;
      target_workflow_id?: string;
      target_agent_id?: string;
      baseline_metrics?: Record<string, unknown>;
      thresholds?: Record<string, unknown>;
      description?: string;
    }
  ): Promise<{ benchmark: PerformanceBenchmark }> {
    return this.post(`${this.basePath}/${sandboxId}/benchmarks`, data);
  }

  async runBenchmark(
    sandboxId: string,
    benchmarkId: string,
    sampleSize?: number
  ): Promise<{
    benchmark: PerformanceBenchmark;
    results: Record<string, unknown>;
    violations: unknown[];
    comparison: Record<string, unknown>;
  }> {
    return this.post(`${this.basePath}/${sandboxId}/benchmarks/${benchmarkId}/run`, { sample_size: sampleSize });
  }

  // A/B Tests (account-level)
  async getAbTests(page = 1, perPage = 20): Promise<PaginatedResponse<AbTest>> {
    const queryString = this.buildQueryString({ page, per_page: perPage });
    return this.get<PaginatedResponse<AbTest>>(`${this.abTestsPath}${queryString}`);
  }

  async createAbTest(data: {
    name: string;
    target_type: string;
    target_id: string;
    variants: unknown[];
    traffic_allocation?: Record<string, number>;
    success_metrics?: string[];
    description?: string;
  }): Promise<{ ab_test: AbTest }> {
    return this.post(`${this.abTestsPath}`, data);
  }

  async startAbTest(id: string): Promise<{ ab_test: AbTest }> {
    return this.put(`${this.abTestsPath}/${id}/start`);
  }

  async getAbTestResults(id: string): Promise<{ results: AbTestResults }> {
    return this.get(`${this.abTestsPath}/${id}/results`);
  }
}

export const sandboxApi = new SandboxApiService();

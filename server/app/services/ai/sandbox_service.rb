# frozen_string_literal: true

module Ai
  class SandboxService
    attr_reader :account

    def initialize(account)
      @account = account
    end

    # Sandbox Management
    def create_sandbox(name:, sandbox_type: "standard", user: nil, description: nil, configuration: {}, expires_at: nil)
      Ai::Sandbox.create!(
        account: account,
        created_by: user,
        name: name,
        sandbox_type: sandbox_type,
        description: description,
        configuration: configuration,
        expires_at: expires_at,
        status: "inactive"
      )
    end

    def activate_sandbox(sandbox)
      return { success: false, error: "Sandbox expired" } if sandbox.expired?

      sandbox.activate!
      { success: true, sandbox: sandbox }
    end

    def get_sandbox(id)
      account.ai_sandboxes.find(id)
    end

    # Test Scenarios
    def create_scenario(sandbox:, name:, scenario_type:, target_workflow: nil, target_agent: nil, user: nil, description: nil, input_data: {}, expected_output: {}, assertions: [], timeout_seconds: 300)
      Ai::TestScenario.create!(
        account: account,
        sandbox: sandbox,
        created_by: user,
        target_workflow: target_workflow,
        target_agent: target_agent,
        name: name,
        scenario_type: scenario_type,
        description: description,
        input_data: input_data,
        expected_output: expected_output,
        assertions: assertions,
        timeout_seconds: timeout_seconds,
        status: "draft"
      )
    end

    # Mock Responses
    def create_mock(sandbox:, name:, provider_type:, match_type: "exact", match_criteria: {}, response_data: {}, user: nil, latency_ms: 100, error_rate: 0)
      Ai::MockResponse.create!(
        account: account,
        sandbox: sandbox,
        created_by: user,
        name: name,
        provider_type: provider_type,
        match_type: match_type,
        match_criteria: match_criteria,
        response_data: response_data,
        latency_ms: latency_ms,
        error_rate: error_rate,
        is_active: true
      )
    end

    # Test Runs
    def create_test_run(sandbox:, scenario_ids: [], run_type: "manual", user: nil, environment: {})
      run = Ai::TestRun.create!(
        account: account,
        sandbox: sandbox,
        triggered_by: user,
        run_type: run_type,
        status: "pending",
        scenario_ids: scenario_ids,
        total_scenarios: scenario_ids.length,
        environment: environment
      )

      { success: true, run: run }
    end

    def execute_test_run(run)
      return { success: false, error: "Run not pending" } unless run.pending?
      return { success: false, error: "Sandbox not active" } unless run.sandbox.active?

      run.start!

      # Execute each scenario
      scenarios = Ai::TestScenario.where(id: run.scenario_ids)
      scenarios.each do |scenario|
        execute_scenario(run, scenario)
      end

      run.complete!
      { success: true, run: run.reload }
    end

    def execute_scenario(run, scenario)
      result = Ai::TestResult.create!(
        test_run: run,
        scenario: scenario,
        status: "skipped",
        input_used: scenario.input_data,
        started_at: Time.current
      )

      begin
        # Execute the target (workflow or agent)
        output = execute_target(run.sandbox, scenario)

        # Evaluate assertions
        assertion_results = scenario.evaluate_assertions(output)
        all_passed = assertion_results.all? { |r| r[:passed] }

        result.complete!(
          status: all_passed ? "passed" : "failed",
          actual_output: output,
          assertion_results: assertion_results
        )
      rescue Timeout::Error
        result.complete!(
          status: "timeout",
          actual_output: {},
          error_details: { message: "Scenario timed out after #{scenario.timeout_seconds} seconds" }
        )
      rescue StandardError => e
        result.complete!(
          status: "error",
          actual_output: {},
          error_details: { message: e.message, backtrace: e.backtrace&.first(5) }
        )
      end

      result
    end

    # Recording
    def start_recording(sandbox)
      sandbox.enable_recording!
      { success: true, sandbox: sandbox }
    end

    def stop_recording(sandbox)
      sandbox.disable_recording!
      { success: true, sandbox: sandbox }
    end

    def record_interaction(sandbox:, interaction_type:, request_data:, response_data:, provider_type: nil, model_name: nil, workflow_run: nil, latency_ms: nil, tokens_input: 0, tokens_output: 0, cost: 0)
      return unless sandbox.recording_enabled

      Ai::RecordedInteraction.record!(
        sandbox: sandbox,
        account: account,
        interaction_type: interaction_type,
        provider_type: provider_type,
        model_name: model_name,
        source_workflow_run: workflow_run,
        request_data: request_data,
        response_data: response_data,
        latency_ms: latency_ms,
        tokens_input: tokens_input,
        tokens_output: tokens_output,
        cost: cost,
        sequence_number: next_sequence_number(sandbox, workflow_run)
      )
    end

    def replay_recording(sandbox, workflow_run)
      interactions = sandbox.recorded_interactions.for_workflow_run(workflow_run)
      interactions.map(&:replay_data)
    end

    # Performance Benchmarks
    def create_benchmark(name:, sandbox: nil, target_workflow: nil, target_agent: nil, baseline_metrics: {}, thresholds: {}, user: nil, description: nil)
      Ai::PerformanceBenchmark.create!(
        account: account,
        sandbox: sandbox,
        target_workflow: target_workflow,
        target_agent: target_agent,
        created_by: user,
        name: name,
        description: description,
        baseline_metrics: baseline_metrics,
        thresholds: thresholds,
        status: "active"
      )
    end

    def run_benchmark(benchmark, sample_size: nil)
      return { success: false, error: "Benchmark not active" } unless benchmark.active?

      samples = sample_size || benchmark.sample_size
      results = collect_benchmark_samples(benchmark, samples)
      aggregated = aggregate_results(results)

      benchmark.record_results!(aggregated)

      violations = benchmark.threshold_violations(aggregated)
      comparison = benchmark.compare_to_baseline(aggregated)

      {
        success: true,
        benchmark: benchmark.reload,
        results: aggregated,
        violations: violations,
        comparison: comparison
      }
    end

    # A/B Tests
    def create_ab_test(name:, target_type:, target_id:, variants:, traffic_allocation: {}, success_metrics: [], user: nil, description: nil)
      Ai::AbTest.create!(
        account: account,
        created_by: user,
        name: name,
        description: description,
        target_type: target_type,
        target_id: target_id,
        variants: variants,
        traffic_allocation: traffic_allocation,
        success_metrics: success_metrics,
        status: "draft"
      )
    end

    def start_ab_test(test)
      return { success: false, error: "Insufficient variants" } if test.variants.length < 2

      test.start!
      { success: true, test: test }
    end

    def get_variant(test, identifier = nil)
      return nil unless test.running?

      variant = test.assign_variant(identifier)
      test.record_impression!(variant["id"]) if variant

      variant
    end

    def record_conversion(test, variant_id, value = 1)
      test.record_conversion!(variant_id, value)
    end

    def get_ab_test_results(test)
      {
        test_id: test.test_id,
        status: test.status,
        total_impressions: test.total_impressions,
        total_conversions: test.total_conversions,
        variants: test.variant_results,
        has_sufficient_data: test.has_sufficient_data?,
        statistical_significance: test.statistical_significance,
        winning_variant: test.winning_variant
      }
    end

    # Analytics
    def get_sandbox_analytics(sandbox)
      {
        test_runs: {
          total: sandbox.test_runs.count,
          by_status: sandbox.test_runs.group(:status).count,
          recent: sandbox.test_runs.recent.limit(10)
        },
        scenarios: {
          total: sandbox.test_scenarios.count,
          active: sandbox.test_scenarios.active.count,
          by_type: sandbox.test_scenarios.group(:scenario_type).count,
          average_pass_rate: sandbox.test_scenarios.average(:pass_rate)
        },
        recordings: {
          total: sandbox.recorded_interactions.count,
          by_type: sandbox.recorded_interactions.group(:interaction_type).count
        },
        usage: {
          total_executions: sandbox.total_executions,
          last_used_at: sandbox.last_used_at
        }
      }
    end

    private

    def execute_target(sandbox, scenario)
      sandbox.record_usage!

      # Check for mock responses first
      mock = sandbox.get_mock_response(
        provider_type: determine_provider_type(scenario),
        request_data: scenario.input_data
      )

      return mock.get_response if mock

      # Execute the actual target
      if scenario.target_workflow.present?
        execute_workflow_in_sandbox(sandbox, scenario)
      elsif scenario.target_agent.present?
        execute_agent_in_sandbox(sandbox, scenario)
      else
        { error: "No target specified" }
      end
    end

    def execute_workflow_in_sandbox(sandbox, scenario)
      # In a real implementation, execute workflow with sandbox context
      { executed: true, workflow_id: scenario.target_workflow_id, sandbox_id: sandbox.id }
    end

    def execute_agent_in_sandbox(sandbox, scenario)
      # In a real implementation, execute agent with sandbox context
      { executed: true, agent_id: scenario.target_agent_id, sandbox_id: sandbox.id }
    end

    def determine_provider_type(scenario)
      if scenario.target_workflow.present?
        "workflow"
      elsif scenario.target_agent.present?
        "agent"
      else
        "unknown"
      end
    end

    def next_sequence_number(sandbox, workflow_run)
      return nil unless workflow_run

      max = sandbox.recorded_interactions.for_workflow_run(workflow_run).maximum(:sequence_number)
      (max || 0) + 1
    end

    def collect_benchmark_samples(benchmark, count)
      results = []
      count.times do
        start_time = Time.current
        # Execute target and collect metrics
        latency = (Time.current - start_time) * 1000

        results << {
          latency_ms: latency,
          tokens_used: 0, # Would be populated from actual execution
          cost_usd: 0
        }
      end
      results
    end

    def aggregate_results(results)
      return {} if results.empty?

      {
        latency_ms: {
          avg: results.sum { |r| r[:latency_ms] } / results.length,
          min: results.map { |r| r[:latency_ms] }.min,
          max: results.map { |r| r[:latency_ms] }.max,
          p95: percentile(results.map { |r| r[:latency_ms] }, 95)
        },
        tokens_used: results.sum { |r| r[:tokens_used] },
        cost_usd: results.sum { |r| r[:cost_usd] },
        sample_count: results.length
      }
    end

    def percentile(values, p)
      return 0 if values.empty?

      sorted = values.sort
      index = (p / 100.0 * (sorted.length - 1)).round
      sorted[index]
    end
  end
end

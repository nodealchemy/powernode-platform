# frozen_string_literal: true

module Api
  module V1
    module Ai
      class SandboxesController < ApplicationController
        before_action :set_service
        before_action :set_sandbox, only: %i[show update destroy activate deactivate analytics scenarios mocks runs benchmarks ab_tests]

        # GET /api/v1/ai/sandboxes
        def index
          sandboxes = current_account.ai_sandboxes
                                     .order(created_at: :desc)
                                     .page(params[:page])
                                     .per(params[:per_page] || 20)

          sandboxes = sandboxes.by_type(params[:sandbox_type]) if params[:sandbox_type].present?
          sandboxes = sandboxes.where(status: params[:status]) if params[:status].present?

          render_success(
            sandboxes: sandboxes.map { |s| sandbox_json(s) },
            pagination: pagination_meta(sandboxes)
          )
        end

        # POST /api/v1/ai/sandboxes
        def create
          sandbox = @service.create_sandbox(
            name: params[:name],
            sandbox_type: params[:sandbox_type] || "standard",
            user: current_user,
            description: params[:description],
            configuration: params[:configuration] || {},
            expires_at: params[:expires_at]
          )

          render_success(sandbox: sandbox_json(sandbox), status: :created)
        end

        # GET /api/v1/ai/sandboxes/:id
        def show
          render_success(sandbox: sandbox_json(@sandbox, detailed: true))
        end

        # PUT /api/v1/ai/sandboxes/:id
        def update
          @sandbox.update!(sandbox_params)
          render_success(sandbox: sandbox_json(@sandbox))
        end

        # DELETE /api/v1/ai/sandboxes/:id
        def destroy
          @sandbox.update!(status: "deleted")
          render_success(message: "Sandbox deleted successfully")
        end

        # PUT /api/v1/ai/sandboxes/:id/activate
        def activate
          result = @service.activate_sandbox(@sandbox)

          if result[:success]
            render_success(sandbox: sandbox_json(result[:sandbox]))
          else
            render_error(result[:error], :unprocessable_entity)
          end
        end

        # PUT /api/v1/ai/sandboxes/:id/deactivate
        def deactivate
          @sandbox.deactivate!
          render_success(sandbox: sandbox_json(@sandbox))
        end

        # GET /api/v1/ai/sandboxes/:id/analytics
        def analytics
          analytics = @service.get_sandbox_analytics(@sandbox)
          render_success(analytics: analytics)
        end

        # Test Scenarios
        # GET /api/v1/ai/sandboxes/:sandbox_id/scenarios
        def scenarios
          scenarios = @sandbox.test_scenarios
                             .order(created_at: :desc)
                             .page(params[:page])
                             .per(params[:per_page] || 20)

          render_success(
            scenarios: scenarios.map { |s| scenario_json(s) },
            pagination: pagination_meta(scenarios)
          )
        end

        # POST /api/v1/ai/sandboxes/:sandbox_id/scenarios
        def create_scenario
          target_workflow = params[:target_workflow_id].present? ?
            current_account.ai_workflows.find(params[:target_workflow_id]) : nil
          target_agent = params[:target_agent_id].present? ?
            current_account.ai_agents.find(params[:target_agent_id]) : nil

          scenario = @service.create_scenario(
            sandbox: @sandbox,
            name: params[:name],
            scenario_type: params[:scenario_type],
            target_workflow: target_workflow,
            target_agent: target_agent,
            user: current_user,
            description: params[:description],
            input_data: params[:input_data] || {},
            expected_output: params[:expected_output] || {},
            assertions: params[:assertions] || [],
            timeout_seconds: params[:timeout_seconds] || 300
          )

          render_success(scenario: scenario_json(scenario), status: :created)
        end

        # Mock Responses
        # GET /api/v1/ai/sandboxes/:sandbox_id/mocks
        def mocks
          mocks = @sandbox.mock_responses
                         .order(priority: :desc, created_at: :desc)
                         .page(params[:page])
                         .per(params[:per_page] || 20)

          render_success(
            mocks: mocks.map { |m| mock_json(m) },
            pagination: pagination_meta(mocks)
          )
        end

        # POST /api/v1/ai/sandboxes/:sandbox_id/mocks
        def create_mock
          mock = @service.create_mock(
            sandbox: @sandbox,
            name: params[:name],
            provider_type: params[:provider_type],
            match_type: params[:match_type] || "exact",
            match_criteria: params[:match_criteria] || {},
            response_data: params[:response_data] || {},
            user: current_user,
            latency_ms: params[:latency_ms] || 100,
            error_rate: params[:error_rate] || 0
          )

          render_success(mock: mock_json(mock), status: :created)
        end

        # Test Runs
        # GET /api/v1/ai/sandboxes/:sandbox_id/runs
        def runs
          runs = @sandbox.test_runs
                        .order(created_at: :desc)
                        .page(params[:page])
                        .per(params[:per_page] || 20)

          render_success(
            runs: runs.map { |r| run_json(r) },
            pagination: pagination_meta(runs)
          )
        end

        # POST /api/v1/ai/sandboxes/:sandbox_id/runs
        def create_run
          result = @service.create_test_run(
            sandbox: @sandbox,
            scenario_ids: params[:scenario_ids] || [],
            run_type: params[:run_type] || "manual",
            user: current_user,
            environment: params[:environment] || {}
          )

          if result[:success]
            render_success(run: run_json(result[:run]), status: :created)
          else
            render_error(result[:error], :unprocessable_entity)
          end
        end

        # POST /api/v1/ai/sandboxes/:sandbox_id/runs/:run_id/execute
        def execute_run
          run = @sandbox.test_runs.find(params[:run_id])
          result = @service.execute_test_run(run)

          if result[:success]
            render_success(run: run_json(result[:run], detailed: true))
          else
            render_error(result[:error], :unprocessable_entity)
          end
        end

        # GET /api/v1/ai/sandboxes/:sandbox_id/runs/:run_id
        def show_run
          run = @sandbox.test_runs.find(params[:run_id])
          render_success(run: run_json(run, detailed: true))
        end

        # Performance Benchmarks
        # GET /api/v1/ai/sandboxes/:sandbox_id/benchmarks
        def benchmarks
          benchmarks = @sandbox.performance_benchmarks
                              .order(created_at: :desc)
                              .page(params[:page])
                              .per(params[:per_page] || 20)

          render_success(
            benchmarks: benchmarks.map { |b| benchmark_json(b) },
            pagination: pagination_meta(benchmarks)
          )
        end

        # POST /api/v1/ai/sandboxes/:sandbox_id/benchmarks
        def create_benchmark
          target_workflow = params[:target_workflow_id].present? ?
            current_account.ai_workflows.find(params[:target_workflow_id]) : nil
          target_agent = params[:target_agent_id].present? ?
            current_account.ai_agents.find(params[:target_agent_id]) : nil

          benchmark = @service.create_benchmark(
            name: params[:name],
            sandbox: @sandbox,
            target_workflow: target_workflow,
            target_agent: target_agent,
            baseline_metrics: params[:baseline_metrics] || {},
            thresholds: params[:thresholds] || {},
            user: current_user,
            description: params[:description]
          )

          render_success(benchmark: benchmark_json(benchmark), status: :created)
        end

        # POST /api/v1/ai/sandboxes/:sandbox_id/benchmarks/:benchmark_id/run
        def run_benchmark
          benchmark = @sandbox.performance_benchmarks.find(params[:benchmark_id])
          result = @service.run_benchmark(benchmark, sample_size: params[:sample_size])

          if result[:success]
            render_success(
              benchmark: benchmark_json(result[:benchmark]),
              results: result[:results],
              violations: result[:violations],
              comparison: result[:comparison]
            )
          else
            render_error(result[:error], :unprocessable_entity)
          end
        end

        # A/B Tests
        # GET /api/v1/ai/sandboxes/:sandbox_id/ab_tests
        def ab_tests
          tests = current_account.ai_ab_tests
                                .order(created_at: :desc)
                                .page(params[:page])
                                .per(params[:per_page] || 20)

          render_success(
            ab_tests: tests.map { |t| ab_test_json(t) },
            pagination: pagination_meta(tests)
          )
        end

        # POST /api/v1/ai/sandboxes/ab_tests
        def create_ab_test
          test = @service.create_ab_test(
            name: params[:name],
            target_type: params[:target_type],
            target_id: params[:target_id],
            variants: params[:variants] || [],
            traffic_allocation: params[:traffic_allocation] || {},
            success_metrics: params[:success_metrics] || [],
            user: current_user,
            description: params[:description]
          )

          render_success(ab_test: ab_test_json(test), status: :created)
        end

        # PUT /api/v1/ai/sandboxes/ab_tests/:id/start
        def start_ab_test
          test = current_account.ai_ab_tests.find(params[:id])
          result = @service.start_ab_test(test)

          if result[:success]
            render_success(ab_test: ab_test_json(result[:test]))
          else
            render_error(result[:error], :unprocessable_entity)
          end
        end

        # GET /api/v1/ai/sandboxes/ab_tests/:id/results
        def ab_test_results
          test = current_account.ai_ab_tests.find(params[:id])
          results = @service.get_ab_test_results(test)

          render_success(results: results)
        end

        private

        def set_service
          @service = ::Ai::SandboxService.new(current_account)
        end

        def set_sandbox
          @sandbox = current_account.ai_sandboxes.find(params[:id] || params[:sandbox_id])
        end

        def sandbox_params
          params.permit(:name, :description, :sandbox_type, :configuration, :resource_limits, :expires_at)
        end

        def sandbox_json(sandbox, detailed: false)
          json = {
            id: sandbox.id,
            name: sandbox.name,
            description: sandbox.description,
            sandbox_type: sandbox.sandbox_type,
            status: sandbox.status,
            is_isolated: sandbox.is_isolated,
            recording_enabled: sandbox.recording_enabled,
            test_runs_count: sandbox.test_runs_count,
            total_executions: sandbox.total_executions,
            last_used_at: sandbox.last_used_at,
            expires_at: sandbox.expires_at,
            created_at: sandbox.created_at
          }

          if detailed
            json.merge!(
              configuration: sandbox.configuration,
              mock_providers: sandbox.mock_providers,
              environment_variables: sandbox.environment_variables,
              resource_limits: sandbox.resource_limits
            )
          end

          json
        end

        def scenario_json(scenario)
          {
            id: scenario.id,
            name: scenario.name,
            description: scenario.description,
            scenario_type: scenario.scenario_type,
            status: scenario.status,
            target_type: scenario.target_type,
            target_workflow_id: scenario.target_workflow_id,
            target_agent_id: scenario.target_agent_id,
            input_data: scenario.input_data,
            expected_output: scenario.expected_output,
            assertions: scenario.assertions,
            timeout_seconds: scenario.timeout_seconds,
            run_count: scenario.run_count,
            pass_count: scenario.pass_count,
            fail_count: scenario.fail_count,
            pass_rate: scenario.pass_rate,
            last_run_at: scenario.last_run_at,
            created_at: scenario.created_at
          }
        end

        def mock_json(mock)
          {
            id: mock.id,
            name: mock.name,
            provider_type: mock.provider_type,
            model_name: mock.model_name,
            endpoint: mock.endpoint,
            match_type: mock.match_type,
            match_criteria: mock.match_criteria,
            response_data: mock.response_data,
            latency_ms: mock.latency_ms,
            error_rate: mock.error_rate,
            is_active: mock.is_active,
            priority: mock.priority,
            hit_count: mock.hit_count,
            last_hit_at: mock.last_hit_at,
            created_at: mock.created_at
          }
        end

        def run_json(run, detailed: false)
          json = {
            id: run.id,
            run_id: run.run_id,
            run_type: run.run_type,
            status: run.status,
            total_scenarios: run.total_scenarios,
            passed_scenarios: run.passed_scenarios,
            failed_scenarios: run.failed_scenarios,
            skipped_scenarios: run.skipped_scenarios,
            pass_rate: run.pass_rate,
            duration_ms: run.duration_ms,
            started_at: run.started_at,
            completed_at: run.completed_at,
            created_at: run.created_at
          }

          if detailed
            json.merge!(
              scenario_ids: run.scenario_ids,
              total_assertions: run.total_assertions,
              passed_assertions: run.passed_assertions,
              failed_assertions: run.failed_assertions,
              summary: run.summary,
              environment: run.environment,
              results: run.test_results.map { |r| result_json(r) }
            )
          end

          json
        end

        def result_json(result)
          {
            id: result.id,
            result_id: result.result_id,
            status: result.status,
            scenario_id: result.scenario_id,
            input_used: result.input_used,
            actual_output: result.actual_output,
            assertion_results: result.assertion_results,
            error_details: result.error_details,
            duration_ms: result.duration_ms,
            tokens_used: result.tokens_used,
            cost_usd: result.cost_usd,
            retry_attempt: result.retry_attempt
          }
        end

        def benchmark_json(benchmark)
          {
            id: benchmark.id,
            benchmark_id: benchmark.benchmark_id,
            name: benchmark.name,
            description: benchmark.description,
            status: benchmark.status,
            target_workflow_id: benchmark.target_workflow_id,
            target_agent_id: benchmark.target_agent_id,
            baseline_metrics: benchmark.baseline_metrics,
            thresholds: benchmark.thresholds,
            sample_size: benchmark.sample_size,
            run_count: benchmark.run_count,
            latest_results: benchmark.latest_results,
            latest_score: benchmark.latest_score,
            trend: benchmark.trend,
            last_run_at: benchmark.last_run_at,
            created_at: benchmark.created_at
          }
        end

        def ab_test_json(test)
          {
            id: test.id,
            test_id: test.test_id,
            name: test.name,
            description: test.description,
            status: test.status,
            target_type: test.target_type,
            target_id: test.target_id,
            variants: test.variants,
            traffic_allocation: test.traffic_allocation,
            success_metrics: test.success_metrics,
            total_impressions: test.total_impressions,
            total_conversions: test.total_conversions,
            winning_variant: test.winning_variant,
            statistical_significance: test.statistical_significance,
            started_at: test.started_at,
            ended_at: test.ended_at,
            created_at: test.created_at
          }
        end

        def pagination_meta(collection)
          {
            current_page: collection.current_page,
            total_pages: collection.total_pages,
            total_count: collection.total_count,
            per_page: collection.limit_value
          }
        end
      end
    end
  end
end

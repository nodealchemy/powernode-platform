# frozen_string_literal: true

module Api
  module V1
    module Ai
      class SandboxTestingController < ApplicationController
        before_action :set_service
        before_action :set_sandbox, only: %i[runs create_run execute_run show_run benchmarks create_benchmark run_benchmark]
        before_action :validate_permissions

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
            render_error(result[:error], :unprocessable_content)
          end
        end

        # POST /api/v1/ai/sandboxes/:sandbox_id/runs/:run_id/execute
        def execute_run
          run = @sandbox.test_runs.find(params[:run_id])
          result = @service.execute_test_run(run)

          if result[:success]
            render_success(run: run_json(result[:run], detailed: true))
          else
            render_error(result[:error], :unprocessable_content)
          end
        end

        # GET /api/v1/ai/sandboxes/:sandbox_id/runs/:run_id
        def show_run
          run = @sandbox.test_runs.find(params[:run_id])
          render_success(run: run_json(run, detailed: true))
        end

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
            render_error(result[:error], :unprocessable_content)
          end
        end

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
            render_error(result[:error], :unprocessable_content)
          end
        end

        # GET /api/v1/ai/sandboxes/ab_tests/:id/results
        def ab_test_results
          test = current_account.ai_ab_tests.find(params[:id])
          results = @service.get_ab_test_results(test)

          render_success(results: results)
        end

        private

        def validate_permissions
          return if current_worker

          case action_name
          when "runs", "show_run", "ab_tests", "ab_test_results"
            require_permission("ai.sandboxes.test")
          when "create_run", "execute_run", "create_ab_test", "start_ab_test"
            require_permission("ai.sandboxes.test")
          when "benchmarks", "create_benchmark", "run_benchmark"
            require_permission("ai.sandboxes.benchmark")
          end
        end

        def set_service
          @service = ::Ai::SandboxService.new(current_account)
        end

        def set_sandbox
          @sandbox = current_account.ai_sandboxes.find(params[:id] || params[:sandbox_id])
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

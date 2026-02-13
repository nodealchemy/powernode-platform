# frozen_string_literal: true

module Api
  module V1
    module Ai
      class SandboxScenariosController < ApplicationController
        before_action :set_service
        before_action :set_sandbox

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

        private

        def set_service
          @service = ::Ai::SandboxService.new(current_account)
        end

        def set_sandbox
          @sandbox = current_account.ai_sandboxes.find(params[:id] || params[:sandbox_id])
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

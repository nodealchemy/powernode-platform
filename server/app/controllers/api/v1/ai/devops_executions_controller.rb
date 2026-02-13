# frozen_string_literal: true

module Api
  module V1
    module Ai
      class DevopsExecutionsController < ApplicationController
        before_action :set_service

        # GET /api/v1/ai/devops/executions
        def executions
          authorize_action!("ai.devops.read")
          return if performed?

          executions = current_account.ai_pipeline_executions
                                     .order(created_at: :desc)
                                     .page(params[:page])
                                     .per(params[:per_page] || 20)

          executions = executions.by_type(params[:pipeline_type]) if params[:pipeline_type].present?
          executions = executions.where(status: params[:status]) if params[:status].present?
          executions = executions.for_repository(params[:repository_id]) if params[:repository_id].present?

          render_success(
            executions: executions.map { |e| execution_json(e) },
            pagination: pagination_meta(executions)
          )
        end

        # POST /api/v1/ai/devops/executions
        def create_execution
          authorize_action!("ai.devops.manage")
          return if performed?

          installation = params[:installation_id].present? ?
            current_account.ai_devops_template_installations.find(params[:installation_id]) : nil

          result = @service.execute_pipeline(
            installation: installation,
            pipeline_type: params[:pipeline_type],
            user: current_user,
            input_data: params[:input_data] || {},
            trigger_source: params[:trigger_source],
            trigger_event: params[:trigger_event],
            repository_id: params[:repository_id],
            branch: params[:branch],
            commit_sha: params[:commit_sha],
            pull_request_number: params[:pull_request_number]
          )

          if result[:success]
            render_success(execution: execution_json(result[:execution]), status: :created)
          else
            render_error(result[:error], :unprocessable_content)
          end
        end

        # GET /api/v1/ai/devops/executions/:id
        def show_execution
          authorize_action!("ai.devops.read")
          return if performed?

          execution = current_account.ai_pipeline_executions.find(params[:id])
          render_success(execution: execution_json(execution, detailed: true))
        end

        # GET /api/v1/ai/devops/analytics
        def analytics
          authorize_action!("ai.devops.read")
          return if performed?

          analytics = @service.get_pipeline_analytics(
            start_date: params[:start_date]&.to_datetime || 30.days.ago,
            end_date: params[:end_date]&.to_datetime || Time.current
          )

          render_success(analytics: analytics)
        end

        private

        def set_service
          @service = ::Ai::DevopsService.new(current_account)
        end

        def authorize_action!(permission)
          unless current_user.has_permission?(permission)
            render_forbidden("Insufficient permissions")
          end
        end

        def execution_json(execution, detailed: false)
          json = {
            id: execution.id,
            execution_id: execution.execution_id,
            pipeline_type: execution.pipeline_type,
            status: execution.status,
            trigger_source: execution.trigger_source,
            trigger_event: execution.trigger_event,
            repository_id: execution.repository_id,
            branch: execution.branch,
            commit_sha: execution.commit_sha,
            pull_request_number: execution.pull_request_number,
            duration_ms: execution.duration_ms,
            started_at: execution.started_at,
            completed_at: execution.completed_at,
            created_at: execution.created_at
          }

          if detailed
            json.merge!(
              input_data: execution.input_data,
              output_data: execution.output_data,
              ai_analysis: execution.ai_analysis,
              metrics: execution.metrics
            )
          end

          json
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

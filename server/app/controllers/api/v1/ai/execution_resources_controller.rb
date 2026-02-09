# frozen_string_literal: true

module Api
  module V1
    module Ai
      class ExecutionResourcesController < ApplicationController
        include AuditLogging

        before_action :validate_permissions

        # GET /api/v1/ai/execution_resources
        def index
          service = ::Ai::ExecutionResourceAggregatorService.new(account: current_user.account)
          resources = service.aggregate(filter_params)

          # Pagination
          page = (params[:page] || 1).to_i
          per_page = (params[:per_page] || 25).to_i
          total = resources.count
          paginated = resources.slice((page - 1) * per_page, per_page) || []

          render_success(
            items: paginated,
            pagination: {
              current_page: page,
              total_pages: (total.to_f / per_page).ceil,
              total_count: total,
              per_page: per_page
            }
          )
        end

        # GET /api/v1/ai/execution_resources/counts
        def counts
          service = ::Ai::ExecutionResourceAggregatorService.new(account: current_user.account)
          render_success(counts: service.counts(filter_params))
        end

        # GET /api/v1/ai/execution_resources/:resource_type/:id
        def show
          service = ::Ai::ExecutionResourceDetailService.new(account: current_user.account)
          resource = service.fetch(params[:resource_type], params[:id])

          if resource
            render_success(resource: resource)
          else
            render_error("Resource not found", status: :not_found)
          end
        rescue ActiveRecord::RecordNotFound
          render_error("Resource not found", status: :not_found)
        end

        private

        def validate_permissions
          return if current_worker || current_service

          require_permission("ai.agents.read")
        end

        def filter_params
          {
            type: params[:type],
            execution_id: params[:execution_id],
            team_id: params[:team_id],
            agent_id: params[:agent_id],
            status: params[:status],
            search: params[:search],
            start_date: params[:start_date],
            end_date: params[:end_date]
          }.compact
        end
      end
    end
  end
end

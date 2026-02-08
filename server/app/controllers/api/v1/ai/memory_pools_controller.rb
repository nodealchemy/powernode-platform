# frozen_string_literal: true

module Api
  module V1
    module Ai
      class MemoryPoolsController < ApplicationController
        before_action :authenticate_request
        before_action :set_pool, only: %i[show update destroy read_data write_data query]
        before_action :authorize_read!, only: %i[index show read_data query]
        before_action :authorize_manage!, only: %i[create update destroy write_data]

        # GET /api/v1/ai/memory_pools
        def index
          pools = current_account.ai_memory_pools.order(created_at: :desc)
          pools = pools.where(scope: params[:scope]) if params[:scope].present?
          pools = pools.where(pool_type: params[:pool_type]) if params[:pool_type].present?

          render_success(pools.map(&:pool_summary))
        end

        # GET /api/v1/ai/memory_pools/:id
        def show
          render_success(@pool.pool_details)
        end

        # POST /api/v1/ai/memory_pools
        def create
          pool = current_account.ai_memory_pools.build(pool_params)

          if pool.save
            render_success(pool.pool_details, status: :created)
          else
            render_validation_error(pool.errors)
          end
        end

        # PATCH/PUT /api/v1/ai/memory_pools/:id
        def update
          if @pool.update(pool_params)
            render_success(@pool.pool_details)
          else
            render_validation_error(@pool.errors)
          end
        end

        # DELETE /api/v1/ai/memory_pools/:id
        def destroy
          if @pool.destroy
            render_success({ message: "Memory pool deleted" })
          else
            render_error("Failed to delete memory pool", status: :unprocessable_content)
          end
        end

        # GET /api/v1/ai/memory_pools/:id/data/*key
        def read_data
          key = params[:key]
          value = @pool.read_data(key, agent_id: params[:agent_id])
          render_success({ key: key, value: value })
        rescue ArgumentError => e
          render_error(e.message, status: :forbidden)
        end

        # POST /api/v1/ai/memory_pools/:id/write_data
        def write_data
          @pool.write_data(params[:key], params[:value], agent_id: params[:agent_id])
          render_success(@pool.pool_summary)
        rescue ArgumentError => e
          render_error(e.message, status: :forbidden)
        end

        # POST /api/v1/ai/memory_pools/:id/query
        def query
          pools = current_account.ai_memory_pools
          pools = pools.where(scope: params[:scope]) if params[:scope].present?
          pools = pools.where(pool_type: params[:pool_type]) if params[:pool_type].present?
          pools = pools.where(owner_agent_id: params[:agent_id]) if params[:agent_id].present?

          render_success(pools.map(&:pool_summary))
        end

        private

        def set_pool
          @pool = current_account.ai_memory_pools.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_not_found("Memory Pool")
        end

        def authorize_read!
          return if current_user.has_permission?("ai.memory_pools.read")

          render_forbidden
        end

        def authorize_manage!
          return if current_user.has_permission?("ai.memory_pools.manage")

          render_forbidden
        end

        def pool_params
          params.permit(:name, :pool_type, :scope, :owner_agent_id, :team_id,
                        :task_execution_id, :persist_across_executions, :expires_at,
                        data: {}, access_control: {}, metadata: {}, retention_policy: {})
        end
      end
    end
  end
end

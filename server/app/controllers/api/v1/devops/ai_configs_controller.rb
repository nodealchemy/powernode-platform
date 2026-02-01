# frozen_string_literal: true

module Api
  module V1
    module Devops
      class AiConfigsController < ApplicationController
        before_action :authenticate_request
        before_action :require_devops_permission
        before_action :set_ai_config, only: [:show, :update, :destroy, :set_default]

        # GET /api/v1/devops/ai_configs
        def index
          @configs = current_account.devops_ai_configs
                                    .includes(:created_by)
                                    .order(is_default: :desc, name: :asc)

          @configs = @configs.where(status: params[:status]) if params[:status].present?
          @configs = @configs.where(config_type: params[:type]) if params[:type].present?
          @configs = @configs.where(provider: params[:provider]) if params[:provider].present?

          @configs = paginate(@configs)

          render_success(
            { ai_configs: @configs.map { |c| serialize_config(c) } },
            meta: pagination_meta
          )
        end

        # GET /api/v1/devops/ai_configs/:id
        def show
          render_success({ ai_config: serialize_config(@config, include_details: true) })
        end

        # POST /api/v1/devops/ai_configs
        def create
          @config = current_account.devops_ai_configs.build(config_params)
          @config.created_by = current_user
          @config.status = "active"

          if @config.save
            render_success({ ai_config: serialize_config(@config) }, status: :created)
          else
            render_error(@config.errors.full_messages.join(", "), status: :unprocessable_content)
          end
        end

        # PATCH/PUT /api/v1/devops/ai_configs/:id
        def update
          if @config.update(config_params)
            render_success({ ai_config: serialize_config(@config) })
          else
            render_error(@config.errors.full_messages.join(", "), status: :unprocessable_content)
          end
        end

        # DELETE /api/v1/devops/ai_configs/:id
        def destroy
          if @config.is_default?
            return render_error("Cannot delete default configuration", status: :unprocessable_content)
          end

          @config.destroy
          render_success(message: "AI configuration deleted")
        end

        # POST /api/v1/devops/ai_configs/:id/set_default
        def set_default
          # Remove default from other configs of the same type
          current_account.devops_ai_configs
                         .where(config_type: @config.config_type, is_default: true)
                         .update_all(is_default: false)

          @config.update!(is_default: true)

          render_success(
            { ai_config: serialize_config(@config) },
            message: "#{@config.name} set as default"
          )
        end

        private

        def require_devops_permission
          return if current_user.has_permission?("devops.ai.manage")

          render_error("Insufficient permissions", status: :forbidden)
        end

        def set_ai_config
          @config = current_account.devops_ai_configs.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_error("AI configuration not found", status: :not_found)
        end

        def config_params
          params.require(:ai_config).permit(
            :name, :description, :config_type, :provider, :model,
            :status, :max_tokens, :temperature, :top_p,
            :frequency_penalty, :presence_penalty, :timeout_seconds,
            system_prompt: {}, settings: {}, rate_limits: {}, metadata: {}
          )
        end

        def serialize_config(config, include_details: false)
          data = {
            id: config.id,
            name: config.name,
            description: config.description,
            config_type: config.config_type,
            provider: config.provider,
            model: config.model,
            status: config.status,
            is_default: config.is_default,
            created_by: config.created_by ? {
              id: config.created_by.id,
              name: config.created_by.name
            } : nil,
            created_at: config.created_at,
            updated_at: config.updated_at
          }

          if include_details
            data[:max_tokens] = config.max_tokens
            data[:temperature] = config.temperature
            data[:top_p] = config.top_p
            data[:frequency_penalty] = config.frequency_penalty
            data[:presence_penalty] = config.presence_penalty
            data[:timeout_seconds] = config.timeout_seconds
            data[:system_prompt] = config.system_prompt
            data[:settings] = config.settings
            data[:rate_limits] = config.rate_limits
            data[:usage_stats] = {
              total_requests: config.total_requests || 0,
              total_tokens: config.total_tokens || 0,
              last_used_at: config.last_used_at
            }
            data[:metadata] = config.metadata
          end

          data
        end

        def paginate(scope)
          page = (params[:page] || 1).to_i
          per_page = (params[:per_page] || 20).to_i.clamp(1, 100)
          @total_count = scope.count
          @page = page
          @per_page = per_page
          scope.offset((page - 1) * per_page).limit(per_page)
        end

        def pagination_meta
          {
            current_page: @page,
            per_page: @per_page,
            total_count: @total_count,
            total_pages: (@total_count.to_f / @per_page).ceil
          }
        end
      end
    end
  end
end

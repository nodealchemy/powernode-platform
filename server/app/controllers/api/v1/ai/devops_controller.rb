# frozen_string_literal: true

module Api
  module V1
    module Ai
      class DevopsController < ApplicationController
        before_action :set_service

        # GET /api/v1/ai/devops/templates
        def templates
          authorize_action!("ai.devops.read")
          return if performed?

          templates = @service.search_templates(
            query: params[:query],
            category: params[:category],
            template_type: params[:template_type],
            page: params[:page] || 1,
            per_page: params[:per_page] || 20
          )

          render_success(
            templates: templates.map { |t| template_json(t) },
            pagination: pagination_meta(templates)
          )
        end

        # GET /api/v1/ai/devops/templates/:id
        def show_template
          authorize_action!("ai.devops.read")
          return if performed?

          template = ::Ai::DevopsTemplate.find(params[:id])
          render_success(template: template_json(template, detailed: true))
        end

        # POST /api/v1/ai/devops/templates
        def create_template
          authorize_action!("ai.devops.manage")
          return if performed?

          template = @service.create_template(
            name: params[:name],
            category: params[:category],
            template_type: params[:template_type],
            workflow_definition: params[:workflow_definition],
            user: current_user,
            description: params[:description],
            trigger_config: params[:trigger_config] || {},
            variables: params[:variables] || [],
            secrets_required: params[:secrets_required] || []
          )

          render_success(template: template_json(template), status: :created)
        end

        # PATCH /api/v1/ai/devops/templates/:id
        def update_template
          authorize_action!("ai.devops.manage")
          return if performed?

          template = ::Ai::DevopsTemplate.find(params[:id])

          permitted = {}
          permitted[:name] = params[:name] if params.key?(:name)
          permitted[:description] = params[:description] if params.key?(:description)
          permitted[:category] = params[:category] if params.key?(:category)
          permitted[:template_type] = params[:template_type] if params.key?(:template_type)
          permitted[:status] = params[:status] if params.key?(:status)
          permitted[:visibility] = params[:visibility] if params.key?(:visibility)
          permitted[:workflow_definition] = params[:workflow_definition] if params.key?(:workflow_definition)
          permitted[:trigger_config] = params[:trigger_config] if params.key?(:trigger_config)
          permitted[:input_schema] = params[:input_schema] if params.key?(:input_schema)
          permitted[:output_schema] = params[:output_schema] if params.key?(:output_schema)
          permitted[:variables] = params[:variables] if params.key?(:variables)
          permitted[:secrets_required] = params[:secrets_required] if params.key?(:secrets_required)
          permitted[:integrations_required] = params[:integrations_required] if params.key?(:integrations_required)
          permitted[:tags] = params[:tags] if params.key?(:tags)
          permitted[:usage_guide] = params[:usage_guide] if params.key?(:usage_guide)

          template.update!(permitted)
          render_success(template: template_json(template, detailed: true))
        end

        # GET /api/v1/ai/devops/installations
        def installations
          authorize_action!("ai.devops.read")
          return if performed?

          installations = current_account.ai_devops_template_installations
                                         .includes(:devops_template)
                                         .order(created_at: :desc)
                                         .page(params[:page])
                                         .per(params[:per_page] || 20)

          render_success(
            installations: installations.map { |i| installation_json(i) },
            pagination: pagination_meta(installations)
          )
        end

        # POST /api/v1/ai/devops/templates/:template_id/install
        def install
          authorize_action!("ai.devops.manage")
          return if performed?

          template = ::Ai::DevopsTemplate.find(params[:template_id])
          result = @service.install_template(
            template: template,
            user: current_user,
            variable_values: params[:variable_values] || {},
            custom_config: params[:custom_config] || {}
          )

          if result[:success]
            render_success(installation: installation_json(result[:installation]))
          else
            render_error(result[:error], :unprocessable_content)
          end
        end

        # DELETE /api/v1/ai/devops/installations/:id
        def uninstall
          authorize_action!("ai.devops.manage")
          return if performed?

          installation = current_account.ai_devops_template_installations.find(params[:id])
          installation.destroy!

          render_success(message: "Template uninstalled successfully")
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

        def template_json(template, detailed: false)
          json = {
            id: template.id,
            name: template.name,
            slug: template.slug,
            description: template.description,
            category: template.category,
            template_type: template.template_type,
            status: template.status,
            visibility: template.visibility,
            version: template.version,
            installation_count: template.installation_count,
            average_rating: template.average_rating,
            is_system: template.is_system,
            is_featured: template.is_featured,
            price_usd: template.price_usd,
            published_at: template.published_at,
            is_owner: template.account_id == current_account.id
          }

          if detailed
            json.merge!(
              workflow_definition: template.workflow_definition,
              trigger_config: template.trigger_config,
              input_schema: template.input_schema,
              output_schema: template.output_schema,
              variables: template.variables,
              secrets_required: template.secrets_required,
              integrations_required: template.integrations_required,
              tags: template.tags,
              usage_guide: template.usage_guide
            )
          end

          json
        end

        def installation_json(installation)
          {
            id: installation.id,
            status: installation.status,
            installed_version: installation.installed_version,
            execution_count: installation.execution_count,
            success_count: installation.success_count,
            failure_count: installation.failure_count,
            success_rate: installation.success_rate,
            last_executed_at: installation.last_executed_at,
            created_at: installation.created_at,
            template: {
              id: installation.devops_template.id,
              name: installation.devops_template.name
            }
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

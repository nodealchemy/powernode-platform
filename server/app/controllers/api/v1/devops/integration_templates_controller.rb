# frozen_string_literal: true

module Api
  module V1
    module Devops
      class IntegrationTemplatesController < ApplicationController
        before_action :authenticate_request
        before_action :set_template, only: [:show, :update, :destroy]

        # GET /api/v1/devops/integration_templates
        def index
          authorize_action!("devops.integrations.read")

          templates = ::Devops::RegistryService.list_templates(
            filters: template_filters,
            **pagination_params
          )

          render_success({
            templates: templates.map(&:template_summary),
            pagination: pagination_meta(templates)
          })
        end

        # GET /api/v1/devops/integration_templates/:id
        def show
          authorize_action!("devops.integrations.read")

          render_success({ template: @template.template_details })
        end

        # POST /api/v1/devops/integration_templates
        def create
          authorize_action!("admin.devops.integration_templates.create")

          template = ::Devops::RegistryService.create_template(template_params)

          render_success({ template: template.template_details }, status: :created)
        rescue ::Devops::RegistryService::ValidationError => e
          render_error(e.message, status: :unprocessable_content)
        end

        # PATCH /api/v1/devops/integration_templates/:id
        def update
          authorize_action!("admin.devops.integration_templates.update")

          template = ::Devops::RegistryService.update_template(@template.id, template_params)

          render_success({ template: template.template_details })
        rescue ::Devops::RegistryService::ValidationError => e
          render_error(e.message, status: :unprocessable_content)
        end

        # DELETE /api/v1/devops/integration_templates/:id
        def destroy
          authorize_action!("admin.devops.integration_templates.delete")

          @template.destroy!

          render_success(message: "Template deleted")
        end

        # GET /api/v1/devops/integration_templates/search
        def search
          authorize_action!("devops.integrations.read")

          templates = ::Devops::RegistryService.search_templates(
            query: params[:q],
            filters: template_filters,
            **pagination_params
          )

          render_success({
            templates: templates.map(&:template_summary),
            pagination: pagination_meta(templates)
          })
        end

        # GET /api/v1/devops/integration_templates/categories
        def categories
          authorize_action!("devops.integrations.read")

          render_success({ categories: ::Devops::RegistryService.template_categories })
        end

        # GET /api/v1/devops/integration_templates/types
        def types
          authorize_action!("devops.integrations.read")

          render_success({ types: ::Devops::RegistryService.integration_types })
        end

        private

        def set_template
          @template = ::Devops::RegistryService.find_template(params[:id])
        rescue ::Devops::RegistryService::TemplateNotFoundError
          render_not_found("Template")
        end

        def template_params
          params.require(:template).permit(
            :name, :slug, :description, :integration_type, :category, :version,
            :is_public, :is_featured,
            configuration_schema: {},
            credential_requirements: {},
            capabilities: [],
            input_schema: {},
            output_schema: {},
            default_configuration: {}
          )
        end

        def template_filters
          {
            type: params[:type],
            category: params[:category],
            public_only: params[:public_only] == "true",
            featured: params[:featured] == "true",
            active_only: params[:active_only] != "false"
          }.compact
        end

        def authorize_action!(permission)
          unless current_user.has_permission?(permission)
            render_forbidden("You don't have permission to perform this action")
          end
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

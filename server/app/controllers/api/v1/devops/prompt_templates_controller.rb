# frozen_string_literal: true

module Api
  module V1
    module Devops
      class PromptTemplatesController < ApplicationController
        include AuditLogging

        before_action :authenticate_request
        before_action :require_read_permission, only: [ :index, :show, :preview ]
        before_action :require_write_permission, only: [ :create, :update, :destroy, :duplicate ]
        before_action :set_prompt_template, only: [ :show, :update, :destroy, :preview, :duplicate ]

        # GET /api/v1/devops/prompt_templates
        def index
          templates = prompt_templates_scope.order(created_at: :desc)

          # Filter by category if provided
          templates = templates.where(category: params[:category]) if params[:category].present?

          # Filter by active status if provided
          templates = templates.where(is_active: params[:is_active]) if params[:is_active].present?

          # Filter for root templates only (no parent) if requested
          templates = templates.where(parent_template_id: nil) if params[:root_only] == "true"

          render_success({
            prompt_templates: serialize_collection(templates),
            meta: {
              total: templates.count,
              by_category: prompt_templates_scope.group(:category).count
            }
          })

          log_audit_event("devops.prompt_templates.list", current_user.account)
        rescue StandardError => e
          Rails.logger.error "Failed to list prompt templates: #{e.message}"
          render_error("Failed to list prompt templates", status: :internal_server_error)
        end

        # GET /api/v1/devops/prompt_templates/:id
        def show
          render_success({
            prompt_template: serialize_prompt_template(@prompt_template, include_versions: params[:include_versions])
          })

          log_audit_event("devops.prompt_templates.read", @prompt_template)
        rescue StandardError => e
          Rails.logger.error "Failed to get prompt template: #{e.message}"
          render_error("Failed to get prompt template", status: :internal_server_error)
        end

        # POST /api/v1/devops/prompt_templates
        def create
          template = prompt_templates_scope.new(prompt_template_params)
          template.created_by = current_user
          template.domain = "cicd" # Ensure domain is set for DevOps templates

          if template.save
            render_success({
              prompt_template: serialize_prompt_template(template),
              message: "Prompt template created successfully"
            }, status: :created)

            log_audit_event("devops.prompt_templates.create", template)
          else
            render_validation_error(template.errors)
          end
        rescue StandardError => e
          Rails.logger.error "Failed to create prompt template: #{e.message}"
          render_error("Failed to create prompt template", status: :internal_server_error)
        end

        # PATCH/PUT /api/v1/devops/prompt_templates/:id
        def update
          if @prompt_template.update(prompt_template_params)
            render_success({
              prompt_template: serialize_prompt_template(@prompt_template),
              message: "Prompt template updated successfully"
            })

            log_audit_event("devops.prompt_templates.update", @prompt_template)
          else
            render_validation_error(@prompt_template.errors)
          end
        rescue StandardError => e
          Rails.logger.error "Failed to update prompt template: #{e.message}"
          render_error("Failed to update prompt template", status: :internal_server_error)
        end

        # DELETE /api/v1/devops/prompt_templates/:id
        def destroy
          # Check if template is in use by any pipeline steps
          if @prompt_template.ci_cd_pipeline_steps.exists?
            render_error("Cannot delete template that is in use by pipeline steps", status: :unprocessable_content)
            return
          end

          @prompt_template.destroy!

          render_success({
            message: "Prompt template deleted successfully"
          })

          log_audit_event("devops.prompt_templates.delete", @prompt_template)
        rescue StandardError => e
          Rails.logger.error "Failed to delete prompt template: #{e.message}"
          render_error("Failed to delete prompt template", status: :internal_server_error)
        end

        # POST /api/v1/devops/prompt_templates/:id/preview
        def preview
          variables = params[:variables]
          variables = variables.respond_to?(:to_unsafe_h) ? variables.to_unsafe_h : (variables || {}).to_h

          # Validate syntax first to catch ::Liquid::SyntaxError
          syntax_result = @prompt_template.validate_syntax
          unless syntax_result[:valid]
            return render_error("Template syntax error: #{syntax_result[:errors].join(', ')}", status: :unprocessable_content)
          end

          rendered = @prompt_template.render(variables)

          render_success({
            prompt_template_id: @prompt_template.id,
            rendered_content: rendered,
            variables_used: @prompt_template.extract_variables,
            rendered_at: Time.current
          })

          log_audit_event("devops.prompt_templates.preview", @prompt_template)
        rescue ::Liquid::SyntaxError => e
          render_error("Template syntax error: #{e.message}", status: :unprocessable_content)
        rescue StandardError => e
          render_internal_error("Failed to preview template", exception: e)
        end

        # POST /api/v1/devops/prompt_templates/:id/duplicate
        def duplicate
          new_template = @prompt_template.duplicate("#{@prompt_template.name} (Copy)", created_by: current_user)

          render_success({
            prompt_template: serialize_prompt_template(new_template),
            message: "Prompt template duplicated successfully"
          }, status: :created)

          log_audit_event("devops.prompt_templates.duplicate", new_template)
        rescue StandardError => e
          Rails.logger.error "Failed to duplicate prompt template: #{e.message}"
          render_error("Failed to duplicate template", status: :internal_server_error)
        end

        private

        # Scope to DevOps-accessible templates (devops domain + general)
        def prompt_templates_scope
          current_user.account.shared_prompt_templates.for_cicd
        end

        def set_prompt_template
          @prompt_template = prompt_templates_scope.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_error("Prompt template not found", status: :not_found)
        end

        def require_read_permission
          return if current_user.has_permission?("devops.prompt_templates.read")

          render_error("Insufficient permissions to view prompt templates", status: :forbidden)
        end

        def require_write_permission
          return if current_user.has_permission?("devops.prompt_templates.write")

          render_error("Insufficient permissions to manage prompt templates", status: :forbidden)
        end

        def prompt_template_params
          params.require(:prompt_template).permit(
            :name,
            :description,
            :category,
            :content,
            :is_active,
            :parent_template_id,
            variables: {}
          )
        end

        def serialize_collection(templates)
          templates.map { |t| serialize_prompt_template(t) }
        end

        def serialize_prompt_template(template, include_versions: false)
          result = ::Shared::PromptTemplateSerializer.new(template).serializable_hash[:data][:attributes]
          result[:id] = template.id

          if include_versions == "true" || include_versions == true
            result[:versions] = template.versions.order(created_at: :desc).limit(10).map do |version|
              ::Shared::PromptTemplateSerializer.new(version).serializable_hash[:data][:attributes].merge(id: version.id)
            end
          end

          result
        end
      end
    end
  end
end

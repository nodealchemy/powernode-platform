# frozen_string_literal: true

module Api
  module V1
    module Ai
      class WorkflowTemplatesController < ApplicationController
        include AuditLogging
        include ::Ai::WorkflowSerialization

        before_action :set_workflow, only: %i[convert_to_template create_from_template convert_to_workflow]
        before_action :validate_permissions

        # GET /api/v1/ai/workflows/templates
        def templates
          templates_scope = ::Ai::Workflow.templates
                                      .where(visibility: %w[public account])
                                      .or(::Ai::Workflow.templates.where(account_id: current_user.account_id))
                                      .includes(:creator, :nodes)

          templates_scope = templates_scope.where(template_category: params[:category]) if params[:category].present?
          templates_scope = templates_scope.search_by_text(params[:search]) if params[:search].present?

          db_templates = templates_scope.order(created_at: :desc).map { |t| serialize_template(t) }
          builtin_templates = build_workflow_templates
          db_ids = db_templates.map { |t| t[:id] }
          all_templates = db_templates + builtin_templates.reject { |t| db_ids.include?(t[:id]) }

          render_success(templates: all_templates)
        end

        # POST /api/v1/ai/workflows/:id/convert_to_template
        def convert_to_template
          result = template_service.convert_to_template(@workflow,
                                                        category: params[:category] || "custom",
                                                        visibility: params[:visibility] || "account")

          if result.success?
            render_success(template: serialize_template(result.workflow), message: "Workflow converted to template successfully")
            log_audit_event("ai.workflows.convert_to_template", @workflow)
          else
            render_error(result.error, status: :unprocessable_content)
          end
        end

        # POST /api/v1/ai/workflows/:id/create_from_template
        def create_from_template
          source = ::Ai::Workflow.find(params[:id])

          unless source.is_template? && (source.visibility == "public" || source.account_id == current_user.account_id)
            return render_error("Template not found or not accessible", status: :not_found)
          end

          result = template_service.create_workflow_from_source(source, name: params[:name])

          if result.success?
            render_success({ workflow: serialize_workflow_detail(result.workflow), message: "Workflow created from template successfully" }, status: :created)
            log_audit_event("ai.workflows.create_from_template", result.workflow, source_template_id: source.id)
          else
            render_error(result.error, status: :unprocessable_content)
          end
        rescue ActiveRecord::RecordNotFound
          render_error("Template not found", status: :not_found)
        end

        # POST /api/v1/ai/workflows/:id/convert_to_workflow
        def convert_to_workflow
          unless @workflow.is_template?
            return render_error("This workflow is not a template", status: :unprocessable_content)
          end

          @workflow.update!(is_template: false, template_category: nil)
          render_success(workflow: serialize_workflow_detail(@workflow), message: "Template converted to workflow successfully")
          log_audit_event("ai.workflows.convert_to_workflow", @workflow)
        rescue ActiveRecord::RecordInvalid => e
          render_validation_error(e.record.errors)
        end

        private

        def template_service
          @template_service ||= ::Ai::Workflows::TemplateService.new(
            account: current_user.account, user: current_user
          )
        end

        def set_workflow
          @workflow = current_user.account.ai_workflows
                                  .includes(:creator, :nodes, :edges, :triggers, :variables)
                                  .find(params[:workflow_id] || params[:id])
        rescue ActiveRecord::RecordNotFound
          render_error("Workflow not found", status: :not_found)
        end

        def validate_permissions
          return if current_worker || current_service

          case action_name
          when "templates"
            require_permission("ai.workflows.read")
          when "convert_to_template", "create_from_template", "convert_to_workflow"
            require_permission("ai.workflows.update")
          end
        end
      end
    end
  end
end

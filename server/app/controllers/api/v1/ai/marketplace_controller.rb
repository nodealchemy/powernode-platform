# frozen_string_literal: true

module Api
  module V1
    module Ai
      class MarketplaceController < ApplicationController
        include AuditLogging

        skip_before_action :authenticate_request, only: [ :index, :show, :validate_template ]
        before_action :authenticate_request, except: [ :index, :show, :validate_template ]
        before_action :set_template, only: [ :show, :update, :destroy, :publish, :validate_template ]
        before_action :validate_permissions, except: [ :index, :show, :validate_template ]

        # GET /api/v1/ai/marketplace/templates
        def index
          result = discovery_service.discover(
            category: params[:category],
            difficulty: params[:difficulty_level],
            tags: parse_tags(params[:tags]),
            featured: params[:is_featured] == "true",
            highly_rated: params[:highly_rated] == "true",
            sort_by: params[:sort_by] || "recent",
            limit: params[:per_page]&.to_i || 25,
            offset: ((params[:page]&.to_i || 1) - 1) * (params[:per_page]&.to_i || 25)
          )

          render_success({
            items: result[:templates].map { |t| serialize_template(t) },
            pagination: {
              current_page: params[:page]&.to_i || 1,
              per_page: params[:per_page]&.to_i || 25,
              total_count: result[:total_count]
            }
          })
        end

        # GET /api/v1/ai/marketplace/templates/:id
        def show
          analytics = begin
            ActiveRecord::Base.transaction(requires_new: true) do
              discovery_service.template_analytics(@template.id)
            end
          rescue StandardError
            nil
          end

          render_success({
            template: serialize_template_detail(@template),
            analytics: analytics
          })
        end

        # POST /api/v1/ai/marketplace/templates
        def create
          template_data = prepare_template_params

          @template = ::Ai::WorkflowTemplate.new(template_data)

          if @template.save
            log_audit_event("ai.marketplace.template_created", @template)

            render_success({
              template: serialize_template_detail(@template),
              message: "Template created successfully"
            }, status: :created)
          else
            render_validation_error(@template.errors)
          end
        end

        # PATCH /api/v1/ai/marketplace/templates/:id
        def update
          unless @template.can_edit?(current_user, current_user.account)
            return render_error("You do not have permission to edit this template", status: :forbidden)
          end

          if @template.update(template_params)
            log_audit_event("ai.marketplace.template_updated", @template)

            render_success({
              template: serialize_template_detail(@template),
              message: "Template updated successfully"
            })
          else
            render_validation_error(@template.errors)
          end
        end

        # DELETE /api/v1/ai/marketplace/templates/:id
        def destroy
          unless @template.can_delete?(current_user, current_user.account)
            return render_error("Cannot delete template with active installations", status: :unprocessable_content)
          end

          @template.destroy
          log_audit_event("ai.marketplace.template_deleted", @template)

          render_success({ message: "Template deleted successfully" })
        end

        # POST /api/v1/ai/marketplace/templates/:id/publish
        def publish
          unless @template.can_publish?(current_user, current_user.account)
            return render_error("You do not have permission to publish this template", status: :forbidden)
          end

          if @template.publish!
            log_audit_event("ai.marketplace.template_published", @template)

            render_success({
              template: serialize_template_detail(@template),
              message: "Template published successfully"
            })
          else
            render_validation_error(@template.errors)
          end
        end

        # GET /api/v1/ai/marketplace/templates/:id/validate
        def validate_template
          validation_result = {
            valid: @template.valid?,
            errors: @template.errors.full_messages,
            warnings: [],
            suggestions: []
          }

          validation_result[:warnings] << "Template data is empty" if @template.workflow_definition.blank?

          tags = @template.tags || []
          validation_result[:suggestions] << "Add tags to improve discoverability" if tags.empty?
          validation_result[:suggestions] << "Add a more detailed description (minimum 50 characters recommended)" if @template.description.to_s.length < 50

          render_success({ validation: validation_result })
        end

        # POST /api/v1/ai/marketplace/templates/from_workflow
        def create_from_workflow
          actor = current_user || current_worker
          workflow = actor.account.ai_workflows.find(params[:workflow_id])

          template = build_template_from_workflow(workflow)

          if template.persisted?
            log_audit_event("ai.marketplace.template_created_from_workflow", template)

            render_success({
              template: serialize_template_detail(template),
              message: "Template created from workflow successfully"
            }, status: :created)
          else
            render_validation_error(template.errors)
          end
        rescue ActiveRecord::RecordNotFound
          render_error("Workflow not found", status: :not_found)
        end

        private

        def discovery_service
          @discovery_service ||= ::Ai::Marketplace::TemplateDiscoveryService.new(
            account: current_user&.account,
            user: current_user
          )
        end

        def set_template
          if current_user
            @template = ::Ai::WorkflowTemplate
                          .includes(:created_by_user)
                          .accessible_to_account(current_user.account.id)
                          .find(params[:id])
          else
            @template = ::Ai::WorkflowTemplate
                          .includes(:created_by_user)
                          .public_templates
                          .find(params[:id])
          end
        rescue ActiveRecord::RecordNotFound
          render_error("Template not found", status: :not_found)
        end

        def validate_permissions
          return if current_worker

          case action_name
          when "create", "create_from_workflow"
            require_permission("ai.workflows.create")
          when "update", "publish"
            require_permission("ai.workflows.update")
          when "destroy"
            require_permission("ai.workflows.delete")
          end
        end

        def template_params
          template_params = params.require(:template)

          permitted = template_params.permit(
            :name, :description, :category, :visibility, :version,
            :source_workflow_id, :is_featured, :is_public, :difficulty_level, :license,
            tags: [],
            metadata: {}
          ).to_h.with_indifferent_access

          permitted[:template_data] = template_params[:template_data].to_unsafe_h if template_params[:template_data].present?
          permitted[:configuration_schema] = template_params[:configuration_schema].to_unsafe_h if template_params[:configuration_schema].present?

          permitted
        rescue ActionController::ParameterMissing
          params.permit(
            :name, :description, :category, :visibility, :version,
            :source_workflow_id, :is_featured, :is_public, :difficulty_level, :license,
            tags: [],
            metadata: {}
          ).to_h.with_indifferent_access
        end

        def prepare_template_params
          data = template_params

          data[:workflow_definition] = data.delete(:template_data) if data[:template_data]
          data.delete(:configuration_schema)

          data[:account_id] = current_user.account_id
          data[:created_by_user_id] = current_user.id
          data[:author_name] = current_user.full_name if current_user.full_name.present?
          data[:author_email] = current_user.email

          data
        end

        def parse_tags(tags_param)
          return nil if tags_param.blank?
          tags_param.is_a?(Array) ? tags_param : tags_param.split(",")
        end

        def build_template_from_workflow(workflow)
          ::Ai::WorkflowTemplate.create(
            name: params[:name] || "#{workflow.name} Template",
            description: params[:description] || workflow.description || "Template created from #{workflow.name}",
            category: params[:category] || "custom",
            difficulty_level: params[:difficulty_level] || "intermediate",
            tags: params[:tags] || workflow.metadata&.dig("tags") || [],
            is_public: params[:is_public] || false,
            version: params[:version] || "1.0.0",
            license: params[:license] || "private",
            account_id: workflow.account_id,
            created_by_user_id: current_user&.id,
            workflow_definition: extract_workflow_data(workflow),
            metadata: {
              node_count: workflow.nodes.count,
              edge_count: workflow.edges.count,
              complexity_score: calculate_complexity_score(workflow),
              has_ai_agents: workflow.nodes.where(node_type: "ai_agent").exists?,
              has_webhooks: workflow.nodes.where(node_type: "webhook").exists?,
              has_schedules: workflow.triggers.where(trigger_type: "schedule").exists?,
              source_workflow_id: workflow.id
            }
          )
        end

        def extract_workflow_data(workflow)
          {
            workflow: { name: workflow.name, description: workflow.description, version: workflow.version },
            nodes: workflow.nodes.map { |n| { node_id: n.node_id, node_type: n.node_type, name: n.name, description: n.description, configuration: n.configuration || {}, position: n.position } },
            edges: workflow.edges.map { |e| { source_node_id: e.source_node_id, target_node_id: e.target_node_id, edge_type: e.edge_type, condition: e.condition, configuration: e.configuration || {} } },
            triggers: workflow.triggers.map { |t| { trigger_type: t.trigger_type, name: t.name, configuration: t.configuration, is_active: t.is_active } },
            variables: workflow.variables.map { |v| { key: v.key, value: v.value, variable_type: v.variable_type, description: v.description, is_required: v.is_required } }
          }
        end

        def calculate_complexity_score(workflow)
          (workflow.nodes.count * 1.0) + (workflow.edges.count * 0.5) + (workflow.triggers.count * 1.5)
        end

        def serialize_template(template)
          {
            id: template.id,
            name: template.name,
            slug: template.slug,
            description: template.description,
            category: template.category,
            difficulty_level: template.difficulty_level,
            visibility: template.visibility,
            version: template.version,
            tags: template.tags,
            install_count: template.install_count,
            rating: template.rating,
            rating_count: template.rating_count,
            is_featured: template.is_featured,
            created_at: template.created_at.iso8601,
            created_by: template.created_by_user ? { id: template.created_by_user.id, name: template.created_by_user.full_name } : nil,
            can_install: template.can_install?(current_user&.account),
            can_edit: template.can_edit?(current_user, current_user&.account)
          }
        end

        def serialize_template_detail(template)
          serialize_template(template).merge(
            template_data: template.workflow_definition,
            configuration_schema: template.metadata&.dig("configuration_schema") || {},
            license: template.license,
            updated_at: template.updated_at.iso8601,
            can_delete: template.can_delete?(current_user, current_user&.account),
            can_publish: template.can_publish?(current_user, current_user&.account)
          )
        end
      end
    end
  end
end

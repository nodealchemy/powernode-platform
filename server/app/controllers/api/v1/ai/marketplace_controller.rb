# frozen_string_literal: true

module Api
  module V1
    module Ai
      # ==================================================================
      # MARKETPLACE CONTROLLER - Consolidated AI Template Marketplace
      # ==================================================================
      #
      # Manages AI workflow template marketplace operations.
      # Delegates business logic to:
      # - Ai::Marketplace::TemplateDiscoveryService (discovery, search, recommendations)
      # - Ai::Marketplace::InstallationService (installations, updates, ratings)
      #
      # RESTful Resource Structure:
      # - Templates (primary resource): CRUD, publishing, discovery
      # - Installations (nested resource): template installations and tracking
      # - Ratings (nested resource): template ratings and reviews
      #
      class MarketplaceController < ApplicationController
        include AuditLogging

        skip_before_action :authenticate_request, only: [ :index, :show, :discover, :search, :featured, :popular, :categories, :tags, :statistics, :validate_template ]
        before_action :authenticate_request, except: [ :index, :show, :discover, :search, :featured, :popular, :categories, :tags, :statistics, :validate_template ]
        before_action :set_template, only: [ :show, :update, :destroy, :install, :publish, :rate, :validate_template, :template_analytics ]
        before_action :validate_permissions, except: [ :index, :show, :discover, :search, :featured, :popular, :categories, :tags, :statistics, :validate_template ]

        # ===================================================================
        # TEMPLATES - PRIMARY RESOURCE CRUD
        # ===================================================================

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
          # Use a savepoint for analytics to prevent transaction corruption if analytics query fails
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

        # ===================================================================
        # TEMPLATES - CUSTOM ACTIONS
        # ===================================================================

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

        # POST /api/v1/ai/marketplace/templates/:id/install
        def install
          result = installation_service.install(
            template_id: @template.id,
            custom_configuration: params[:custom_configuration] || params[:customizations] || {},
            installation_notes: params[:installation_notes]
          )

          if result[:success]
            log_audit_event("ai.marketplace.template_installed", @template,
              subscription_id: result[:subscription].id,
              workflow_id: result[:workflow].id
            )

            render_success({
              installation: serialize_installation(result[:subscription]),
              workflow: serialize_workflow(result[:workflow]),
              message: result[:message]
            }, status: :created)
          else
            render_error(result[:error], status: :unprocessable_content)
          end
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

        # ===================================================================
        # MARKETPLACE - DISCOVERY & SEARCH
        # ===================================================================

        # GET /api/v1/ai/marketplace/discover
        def discover
          result = discovery_service.discover(
            category: params[:category],
            difficulty: params[:difficulty],
            tags: parse_tags(params[:tags]),
            featured: params[:featured] == "true",
            highly_rated: params[:highly_rated] == "true",
            sort_by: params[:sort_by],
            limit: params[:limit]&.to_i || 20,
            offset: params[:offset]&.to_i || 0,
            include_recommendations: true
          )

          render_success({
            templates: result[:templates].map { |t| serialize_template(t) },
            total_count: result[:total_count],
            recommendations: serialize_recommendations(result[:recommendations])
          })
        end

        # POST /api/v1/ai/marketplace/search
        def search
          query_params = request.post? ? params : request.query_parameters

          result = discovery_service.advanced_search(
            query: query_params[:query] || query_params[:q],
            categories: query_params[:categories],
            difficulty_levels: query_params[:difficulty_levels],
            tags: query_params[:tags],
            min_complexity: query_params[:min_complexity]&.to_i,
            max_complexity: query_params[:max_complexity]&.to_i,
            has_ai_agents: query_params[:has_ai_agents] == "true",
            has_webhooks: query_params[:has_webhooks] == "true",
            has_schedules: query_params[:has_schedules] == "true",
            min_rating: query_params[:min_rating]&.to_f,
            min_usage: query_params[:min_usage]&.to_i
          )

          render_success({
            templates: result[:templates].map { |t| serialize_template(t) },
            total_count: result[:total_count],
            suggestions: result[:suggestions]
          })
        end

        # GET /api/v1/ai/marketplace/recommendations
        def recommendations
          result = discovery_service.get_recommendations(limit: params[:limit]&.to_i || 5)

          render_success({ recommendations: serialize_recommendations(result) })
        end

        # POST /api/v1/ai/marketplace/compare
        def compare
          template_ids = params[:template_ids] || []

          unless template_ids.size.between?(2, 5)
            return render_error("Please provide 2-5 template IDs to compare", status: :bad_request)
          end

          result = discovery_service.compare_templates(template_ids)

          render_success({ comparison: result })
        end

        # ===================================================================
        # MARKETPLACE - METADATA & STATISTICS
        # ===================================================================

        # GET /api/v1/ai/marketplace/featured
        def featured
          templates = discovery_service.featured_templates(limit: params[:limit]&.to_i || 10)

          render_success({
            templates: templates.map { |t| serialize_template(t) }
          })
        end

        # GET /api/v1/ai/marketplace/popular
        def popular
          templates = discovery_service.popular_templates(limit: params[:limit]&.to_i || 10)

          render_success({
            templates: templates.map { |t| serialize_template(t) }
          })
        end

        # GET /api/v1/ai/marketplace/categories
        def categories
          result = discovery_service.explore_categories

          render_success({ categories: result })
        end

        # GET /api/v1/ai/marketplace/tags
        def tags
          result = discovery_service.explore_tags

          render_success({ tags: result })
        end

        # GET /api/v1/ai/marketplace/statistics
        def statistics
          authenticate_optional

          result = discovery_service.marketplace_statistics

          if current_user
            account_templates = ::Ai::WorkflowTemplate.where(account_id: current_user.account.id)
            result[:account] = {
              my_templates: account_templates.count,
              published_templates: account_templates.where(is_public: true).count,
              private_templates: account_templates.where(is_public: false).count,
              total_installs: account_templates.sum(:usage_count),
              templates_by_category: account_templates.group(:category).count
            }
          end

          render_success({ statistics: result })
        end

        # GET /api/v1/ai/marketplace/templates/:id/analytics
        def template_analytics
          analytics = discovery_service.template_analytics(@template.id)

          render_success({ analytics: analytics })
        end

        # ===================================================================
        # INSTALLATIONS - NESTED RESOURCE
        # ===================================================================

        # GET /api/v1/ai/marketplace/installations
        def installations_index
          result = installation_service.list_installations(
            page: params[:page]&.to_i || 1,
            per_page: params[:per_page]&.to_i || 25,
            category: params[:category]
          )

          render_success({
            installations: result[:installations],
            pagination: result[:pagination],
            total_count: result[:pagination][:total_count]
          })
        end

        # GET /api/v1/ai/marketplace/installations/:id
        def installation_show
          result = installation_service.get_installation(params[:id])

          if result[:success]
            render_success({ installation: result[:installation] })
          else
            render_error(result[:error], status: :not_found)
          end
        end

        # DELETE /api/v1/ai/marketplace/installations/:id
        def installation_destroy
          result = installation_service.uninstall(
            subscription_id: params[:id],
            delete_workflow: params[:delete_workflow] == "true"
          )

          if result[:success]
            log_audit_event("ai.marketplace.installation_deleted", nil)
            render_success({ message: result[:message] })
          else
            render_error(result[:error], status: :not_found)
          end
        end

        # GET /api/v1/ai/marketplace/updates
        def check_updates
          result = installation_service.check_for_updates

          render_success({ updates_available: result[:updates_available] })
        end

        # POST /api/v1/ai/marketplace/updates/apply
        def apply_updates
          result = installation_service.apply_all_updates(
            preserve_customizations: params[:preserve_customizations] != "false"
          )

          render_success({
            updated: result,
            message: "Updated #{result[:successful]} of #{result[:total_attempted]} templates"
          })
        end

        # ===================================================================
        # RATINGS - NESTED RESOURCE
        # ===================================================================

        # POST /api/v1/ai/marketplace/templates/:id/rate
        def rate
          unless params[:rating].present?
            return render_error("Rating is required", status: :bad_request)
          end

          rating_value = params[:rating].to_i
          unless rating_value.between?(1, 5)
            return render_error("Rating must be between 1 and 5", status: :bad_request)
          end

          result = installation_service.rate_template(
            template_id: @template.id,
            rating: rating_value,
            feedback: params[:feedback] || {}
          )

          if result[:success]
            log_audit_event("ai.marketplace.template_rated", @template, rating: rating_value)

            render_success({
              rating: result,
              message: result[:message]
            })
          else
            render_error(result[:error], status: :unprocessable_content)
          end
        end

        private

        # ===================================================================
        # SERVICE ACCESSORS
        # ===================================================================

        def discovery_service
          @discovery_service ||= ::Ai::Marketplace::TemplateDiscoveryService.new(
            account: current_user&.account,
            user: current_user
          )
        end

        def installation_service
          @installation_service ||= ::Ai::Marketplace::InstallationService.new(
            account: current_user.account,
            user: current_user
          )
        end

        # ===================================================================
        # RESOURCE LOADING
        # ===================================================================

        def set_template
          if current_user
            @template = ::Ai::WorkflowTemplate.accessible_to_account(current_user.account.id).find(params[:id])
          else
            @template = ::Ai::WorkflowTemplate.public_templates.find(params[:id])
          end
        rescue ActiveRecord::RecordNotFound
          render_error("Template not found", status: :not_found)
        end

        # ===================================================================
        # AUTHORIZATION
        # ===================================================================

        def validate_permissions
          return if current_worker

          case action_name
          when "index", "show", "discover", "search", "featured", "popular", "categories", "tags", "statistics"
            true
          when "recommendations", "installations_index", "installation_show", "check_updates", "template_analytics"
            require_permission("ai.workflows.read")
          when "create", "create_from_workflow", "install"
            require_permission("ai.workflows.create")
          when "update", "publish", "rate"
            require_permission("ai.workflows.update")
          when "destroy", "installation_destroy"
            require_permission("ai.workflows.delete")
          when "compare", "apply_updates"
            require_permission("ai.workflows.manage")
          end
        end

        # ===================================================================
        # PARAMETER HANDLING
        # ===================================================================

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

        # ===================================================================
        # TEMPLATE CREATION HELPERS
        # ===================================================================

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

        # ===================================================================
        # SERIALIZATION
        # ===================================================================

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

        def serialize_installation(subscription)
          {
            id: subscription.id,
            installed_version: subscription.metadata&.dig("template_version"),
            created_at: subscription.subscribed_at&.iso8601 || subscription.created_at.iso8601,
            customizations: subscription.configuration
          }
        end

        def serialize_workflow(workflow)
          return nil unless workflow

          {
            id: workflow.id,
            name: workflow.name,
            description: workflow.description,
            status: workflow.status,
            version: workflow.version,
            created_at: workflow.created_at.iso8601
          }
        end

        def serialize_recommendations(recommendations)
          return [] unless recommendations

          recommendations.map do |rec|
            {
              template: serialize_template(rec[:template]),
              score: rec[:recommendation_score],
              reasons: rec[:recommendation_reasons]
            }
          end
        end
      end
    end
  end
end

# frozen_string_literal: true

module Api
  module V1
    module Ai
      # ==================================================================
      # MARKETPLACE CONTROLLER - Consolidated AI Template Marketplace
      # ==================================================================
      #
      # Consolidates 2 controllers:
      # - WorkflowMarketplaceController (252 lines) - discovery, search, recommendations
      # - AiWorkflowTemplatesController (406 lines) - template CRUD, installations
      #
      # Total reduction: 2 controllers → 1 controller (50% reduction)
      # Code consolidation: ~658 lines → ~950 lines (comprehensive architecture)
      #
      # RESTful Resource Structure:
      # - Templates (primary resource): CRUD, publishing, discovery
      # - Installations (nested resource): template installations and tracking
      # - Ratings (nested resource): template ratings and reviews
      #
      class MarketplaceController < ApplicationController
        skip_before_action :authenticate_request, only: [ :index, :show, :discover, :search, :featured, :popular, :categories, :tags, :statistics, :validate_template ]
        before_action :authenticate_request, except: [ :index, :show, :discover, :search, :featured, :popular, :categories, :tags, :statistics, :validate_template ]
        before_action :set_template, only: [ :show, :update, :destroy, :install, :publish, :rate, :validate_template, :template_analytics ]
        before_action :validate_permissions, except: [ :index, :show, :discover, :search, :featured, :popular, :categories, :tags, :statistics, :validate_template ]
        before_action :set_marketplace_service, only: [ :discover, :search, :recommendations, :compare, :template_analytics, :statistics, :tags, :publish_workflow ]

        # ===================================================================
        # TEMPLATES - PRIMARY RESOURCE CRUD
        # ===================================================================

        # GET /api/v1/ai/marketplace/templates
        def index
          templates = AiWorkflowTemplate.accessible_to_account(current_user&.account&.id || "public")
                                        .includes(:created_by_user, :source_workflow)

          # Apply filters
          templates = apply_template_filters(templates)

          # Apply sorting
          templates = apply_sorting(templates, params[:sort_by] || "recent")

          # Apply pagination
          templates = apply_pagination(templates)

          render_success({
            items: templates.map { |template| serialize_template(template) },
            pagination: pagination_data(templates)
          })
        end

        # GET /api/v1/ai/marketplace/templates/:id
        def show
          analytics = @marketplace_service ? @marketplace_service.template_analytics(@template.id) : nil

          render_success({
            template: serialize_template_detail(@template),
            analytics: analytics
          })
        end

        # POST /api/v1/ai/marketplace/templates
        def create
          template_params_data = template_params

          # Map template_data to workflow_definition if present
          if template_params_data[:template_data]
            template_params_data[:workflow_definition] = template_params_data.delete(:template_data)
          end

          # Remove configuration_schema - it's generated, not stored
          template_params_data.delete(:configuration_schema)

          # Set account ownership from current user
          template_params_data[:account_id] = current_user.account_id
          template_params_data[:created_by_user_id] = current_user.id
          # Also set author fields for display
          template_params_data[:author_name] = current_user.full_name if current_user.full_name.present?
          template_params_data[:author_email] = current_user.email

          @template = AiWorkflowTemplate.new(template_params_data)

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
          # Support both user and worker authentication
          actor = current_user || current_worker
          account = actor.account
          workflow = account.ai_workflows.find(params[:workflow_id])

          template_data = {
            name: params[:name] || "#{workflow.name} Template",
            description: params[:description] || workflow.description || "Template created from #{workflow.name}",
            category: params[:category] || "custom",
            difficulty_level: params[:difficulty_level] || "intermediate",
            tags: params[:tags] || workflow.metadata&.dig("tags") || [],
            is_public: params[:is_public] || false,
            version: params[:version] || "1.0.0",
            license: params[:license] || "private",
            account_id: account.id,
            created_by_user_id: current_user&.id,
            workflow_definition: extract_workflow_template_data(workflow),
            metadata: {
              node_count: workflow.nodes.count,
              edge_count: workflow.edges.count,
              complexity_score: calculate_complexity_score(workflow),
              has_ai_agents: workflow.nodes.where(node_type: "ai_agent").exists?,
              has_webhooks: workflow.nodes.where(node_type: "webhook").exists?,
              has_schedules: workflow.triggers.where(trigger_type: "schedule").exists?,
              source_workflow_id: workflow.id,
              configuration_schema: generate_configuration_schema(workflow)
            }
          }

          template = AiWorkflowTemplate.create(template_data)

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
          # Create the workflow first from template
          workflow = create_workflow_from_template(@template, nil)

          unless workflow.persisted?
            return render_validation_error(workflow.errors)
          end

          # Now create installation with the workflow reference
          installation_params = {
            account_id: current_user.account.id,
            installed_by_user_id: current_user.id,
            ai_workflow_id: workflow.id,
            custom_configuration: params[:custom_configuration] || params[:customizations] || {},
            installation_notes: params[:installation_notes]
          }

          installation = @template.install_to_account(**installation_params)

          if installation.persisted?
            log_audit_event("ai.marketplace.template_installed", @template, {
              installation_id: installation.id,
              workflow_id: workflow.id
            })

            render_success({
              installation: serialize_installation(installation),
              workflow: serialize_created_workflow(workflow),
              message: "Template installed successfully"
            }, status: :created)
          else
            # Rollback workflow if installation fails
            workflow.destroy
            render_validation_error(installation.errors)
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

        # POST /api/v1/ai/marketplace/templates/publish_workflow
        def publish_workflow
          result = @marketplace_service.publish_template(
            params[:workflow_id],
            {
              name: params[:name],
              description: params[:description],
              long_description: params[:long_description],
              category: params[:category],
              difficulty_level: params[:difficulty_level],
              tags: params[:tags] || [],
              author_url: params[:author_url],
              license: params[:license] || "MIT",
              version: params[:version] || "1.0.0",
              is_public: params[:is_public] == "true",
              publish_immediately: params[:publish_immediately] == "true"
            }
          )

          if result[:success]
            log_audit_event("ai.marketplace.workflow_published", result[:template])

            render_success({
              template: result[:template],
              message: result[:message]
            })
          else
            render_error(
              message: "Publishing failed",
              errors: result[:errors],
              status: :unprocessable_content
            )
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

          # Additional validation checks
          if @template.workflow_definition.blank?
            validation_result[:warnings] << "Template data is empty"
          end

          tags = @template.metadata&.dig("tags") || []
          if tags.empty?
            validation_result[:suggestions] << "Add tags to improve discoverability"
          end

          if @template.description.to_s.length < 50
            validation_result[:suggestions] << "Add a more detailed description (minimum 50 characters recommended)"
          end

          render_success({ validation: validation_result })
        end

        # ===================================================================
        # MARKETPLACE - DISCOVERY & SEARCH
        # ===================================================================

        # GET /api/v1/ai/marketplace/discover
        def discover
          if @marketplace_service
            result = @marketplace_service.discover_templates(
              category: params[:category],
              difficulty: params[:difficulty],
              tags: params[:tags]&.split(","),
              featured: params[:featured] == "true",
              highly_rated: params[:highly_rated] == "true",
              sort_by: params[:sort_by],
              limit: params[:limit]&.to_i || 20,
              offset: params[:offset]&.to_i || 0
            )

            render_success({
              templates: serialize_templates(result[:templates]),
              total_count: result[:total_count],
              recommendations: serialize_recommendations(result[:recommendations])
            })
          else
            # Fallback to basic discover
            templates = AiWorkflowTemplate.accessible_to_account(current_user&.account&.id || "public")

            # Apply filters
            templates = templates.where(category: params[:category]) if params[:category].present?
            templates = templates.where("tags ?| array[:tags]", tags: params[:tags].split(",")) if params[:tags].present?
            templates = templates.where(is_featured: true) if params[:featured] == "true"
            templates = templates.where("rating >= ?", 4.0) if params[:highly_rated] == "true"

            # Apply sorting
            templates = case params[:sort_by]
            when "popularity" then templates.order(usage_count: :desc)
            when "rating" then templates.order(rating: :desc)
            when "recent" then templates.order(created_at: :desc)
            else templates.order(usage_count: :desc, created_at: :desc)
            end

            limit = params[:limit]&.to_i || 20
            offset = params[:offset]&.to_i || 0
            total_count = templates.count
            templates = templates.limit(limit).offset(offset)

            render_success({
              templates: templates.map { |t| serialize_template(t) },
              total_count: total_count,
              recommendations: []
            })
          end
        end

        # POST /api/v1/ai/marketplace/search
        def search
          # Handle both POST and GET for flexibility
          query_params = request.post? ? params : request.query_parameters

          if @marketplace_service
            # Use marketplace service for advanced search
            result = @marketplace_service.advanced_search(
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
              templates: serialize_templates(result[:templates]),
              total_count: result[:total_count],
              suggestions: result[:suggestions]
            })
          else
            # Fallback to basic search
            templates = perform_basic_search(query_params)

            render_success({
              templates: templates.map { |t| serialize_template(t) },
              pagination: pagination_data(templates),
              search_query: query_params[:query] || query_params[:q],
              filters: {
                category: query_params[:category],
                tags: query_params[:tags]&.split(",")
              }
            })
          end
        end

        # GET /api/v1/ai/marketplace/recommendations
        def recommendations
          result = @marketplace_service.get_recommendations_for_account(
            limit: params[:limit]&.to_i || 5
          )

          render_success({ recommendations: result })
        end

        # POST /api/v1/ai/marketplace/compare
        def compare
          template_ids = params[:template_ids] || []

          unless template_ids.size.between?(2, 5)
            return render_error("Please provide 2-5 template IDs to compare", status: :bad_request)
          end

          result = @marketplace_service.compare_templates(template_ids)

          render_success({ comparison: result })
        end

        # ===================================================================
        # MARKETPLACE - METADATA & STATISTICS
        # ===================================================================

        # GET /api/v1/ai/marketplace/featured
        def featured
          featured_templates = AiWorkflowTemplate.featured
                                                 .public_templates
                                                 .includes(:created_by_user)
                                                 .limit(params[:limit]&.to_i || 10)

          render_success({
            templates: featured_templates.map { |template| serialize_template(template) }
          })
        end

        # GET /api/v1/ai/marketplace/popular
        def popular
          popular_templates = AiWorkflowTemplate.popular
                                                .public_templates
                                                .includes(:created_by_user)
                                                .limit(params[:limit]&.to_i || 10)

          render_success({
            templates: popular_templates.map { |template| serialize_template(template) }
          })
        end

        # GET /api/v1/ai/marketplace/categories
        def categories
          if @marketplace_service
            result = @marketplace_service.explore_categories
            render_success({ categories: result })
          else
            categories = AiWorkflowTemplate.distinct.pluck(:category).compact.sort
            category_counts = AiWorkflowTemplate.group(:category).count

            render_success({
              categories: categories.map do |category|
                {
                  name: category,
                  slug: category.parameterize,
                  count: category_counts[category] || 0,
                  display_name: category.humanize,
                  description: category_description(category)
                }
              end
            })
          end
        end

        # GET /api/v1/ai/marketplace/tags
        def tags
          if @marketplace_service
            result = @marketplace_service.explore_tags
            render_success({ tags: result })
          else
            # Aggregate all tags from templates
            all_tags = AiWorkflowTemplate.pluck(:tags).flatten.compact.uniq.sort

            render_success({
              tags: all_tags.map do |tag|
                {
                  name: tag,
                  count: AiWorkflowTemplate.where("tags @> ?", [ tag ].to_json).count
                }
              end
            })
          end
        end

        # GET /api/v1/ai/marketplace/statistics
        def statistics
          # Attempt optional authentication to support account-specific statistics
          authenticate_optional

          if @marketplace_service
            result = @marketplace_service.marketplace_statistics

            # Add account statistics if user is authenticated
            if current_user
              account_templates = AiWorkflowTemplate.where(account_id: current_user.account.id)
              # Use string key to match service response format
              result["account"] = {
                my_templates: account_templates.count,
                published_templates: account_templates.where(is_public: true).count,
                private_templates: account_templates.where(is_public: false).count,
                total_installs: account_templates.sum(:usage_count),
                templates_by_category: account_templates.group(:category).count,
                recent_templates: account_templates.where(created_at: 30.days.ago..).count,
                most_installed: account_templates.order(usage_count: :desc)
                                                .limit(5)
                                                .pluck(:name, :usage_count)
              }
            end

            render_success({ statistics: result })
          else
            has_user = current_user.present?
            account_templates = has_user ? AiWorkflowTemplate.where(account_id: current_user.account.id) : AiWorkflowTemplate.none

            stats = {
              marketplace: {
                total_templates: AiWorkflowTemplate.public_templates.count,
                total_installs: AiWorkflowTemplate.sum(:usage_count),
                total_ratings: AiWorkflowTemplate.sum(:rating_count),
                average_rating: AiWorkflowTemplate.average(:rating)&.round(2)
              },
              account: has_user ? {
                my_templates: account_templates.count,
                published_templates: account_templates.where(is_public: true).count,
                private_templates: account_templates.where(is_public: false).count,
                total_installs: account_templates.sum(:usage_count),
                templates_by_category: account_templates.group(:category).count,
                recent_templates: account_templates.where(created_at: 30.days.ago..).count,
                most_installed: account_templates.order(usage_count: :desc)
                                                .limit(5)
                                                .pluck(:name, :usage_count)
              } : nil,
              trending: {
                categories: AiWorkflowTemplate.public_templates
                                              .group(:category)
                                              .order(Arel.sql("COUNT(*) DESC"))
                                              .limit(5)
                                              .count,
                tags: AiWorkflowTemplate.public_templates
                                        .pluck(:tags)
                                        .flatten
                                        .compact
                                        .group_by(&:itself)
                                        .transform_values(&:count)
                                        .sort_by { |_k, v| -v }
                                        .first(10)
                                        .to_h
              }
            }

            render_success({ statistics: stats })
          end
        end

        # GET /api/v1/ai/marketplace/templates/:id/analytics
        def template_analytics
          analytics = @marketplace_service.template_analytics(@template.id)

          render_success({ analytics: analytics })
        end

        # ===================================================================
        # INSTALLATIONS - NESTED RESOURCE
        # ===================================================================

        # GET /api/v1/ai/marketplace/installations
        def installations_index
          installations = current_user.account.ai_workflow_template_installations
                                      .includes(:ai_workflow_template, :ai_workflow, :installed_by_user)
                                      .order(created_at: :desc)

          installations = apply_pagination(installations)

          render_success({
            installations: installations.map { |installation| serialize_installation_detail(installation) },
            pagination: pagination_data(installations),
            total_count: installations.total_count
          })
        end

        # GET /api/v1/ai/marketplace/installations/:id
        def installation_show
          installation = current_user.account.ai_workflow_template_installations.find(params[:id])

          render_success({
            installation: serialize_installation_detail(installation)
          })
        rescue ActiveRecord::RecordNotFound
          render_error("Installation not found", status: :not_found)
        end

        # DELETE /api/v1/ai/marketplace/installations/:id
        def installation_destroy
          installation = current_user.account.ai_workflow_template_installations.find(params[:id])

          # Optionally delete the created workflow
          if params[:delete_workflow] == "true" && installation.ai_workflow
            installation.ai_workflow.destroy
          end

          installation.destroy
          log_audit_event("ai.marketplace.installation_deleted", installation)

          render_success({ message: "Installation deleted successfully" })
        rescue ActiveRecord::RecordNotFound
          render_error("Installation not found", status: :not_found)
        end

        # GET /api/v1/ai/marketplace/updates
        def check_updates
          if @marketplace_service
            result = @marketplace_service.check_for_updates
            render_success({ updates_available: result })
          else
            # Fallback implementation
            installations = current_user.account.ai_workflow_template_installations.includes(:ai_workflow_template)
            updates = installations.select do |installation|
              installation.ai_workflow_template.version != installation.template_version
            end

            render_success({
              updates_available: updates.map do |installation|
                {
                  installation_id: installation.id,
                  template_id: installation.ai_workflow_template.id,
                  template_name: installation.ai_workflow_template.name,
                  current_version: installation.template_version,
                  latest_version: installation.ai_workflow_template.version
                }
              end
            })
          end
        end

        # POST /api/v1/ai/marketplace/updates/apply
        def apply_updates
          if @marketplace_service
            result = @marketplace_service.update_all_templates(
              preserve_customizations: params[:preserve_customizations] != "false"
            )

            render_success({
              updated: result,
              message: "Updated #{result[:successful]} of #{result[:total_attempted]} templates"
            })
          else
            render_error("Update service not available", status: :service_unavailable)
          end
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

          if @marketplace_service
            result = @marketplace_service.rate_template(
              @template.id,
              rating_value,
              feedback: params[:feedback] || {}
            )

            if result[:success]
              log_audit_event("ai.marketplace.template_rated", @template, { rating: rating_value })

              render_success({
                rating: result,
                message: result[:message]
              })
            else
              render_error(message: result[:error], status: :unprocessable_content)
            end
          else
            # Fallback implementation - update template rating
            update_template_rating(@template, rating_value, params[:feedback])

            render_success({
              rating: {
                template_id: @template.id,
                rating: rating_value,
                average_rating: @template.rating,
                total_ratings: @template.rating_count
              },
              message: "Template rated successfully"
            })
          end
        end

        # ===================================================================
        # RESOURCE LOADING
        # ===================================================================

        private

        def set_template
          if current_user
            @template = AiWorkflowTemplate.accessible_to_account(current_user.account.id).find(params[:id])
          else
            @template = AiWorkflowTemplate.public_templates.find(params[:id])
          end
        rescue ActiveRecord::RecordNotFound
          render_error("Template not found", status: :not_found)
        end

        def set_marketplace_service
          return unless current_user

          @marketplace_service = Mcp::WorkflowMarketplaceService.new(
            account: current_user.account,
            user: current_user
          )
        rescue NameError
          # Service not available, fallback to basic functionality
          @marketplace_service = nil
        end

        # ===================================================================
        # AUTHORIZATION
        # ===================================================================

        def validate_permissions
          # Worker bypass - workers can access all endpoints
          return if current_worker

          case action_name
          when "index", "template_index", "show", "template_show", "discover", "search", "featured", "popular", "categories", "tags", "statistics"
            # Public read access - no authentication required
            true
          when "recommendations", "installations_index", "installation_show", "check_updates", "template_analytics"
            require_permission("ai.workflows.read")
          when "create", "template_create", "create_from_workflow", "install"
            require_permission("ai.workflows.create")
          when "update", "template_update", "publish", "publish_workflow", "rate"
            require_permission("ai.workflows.update")
          when "destroy", "template_destroy", "installation_destroy"
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

          # Allow nested hashes for workflow definitions - these contain arbitrary JSON structures
          # Using to_unsafe_h as template_data/configuration_schema have dynamic schemas
          permitted[:template_data] = template_params[:template_data].to_unsafe_h if template_params[:template_data].present?
          permitted[:configuration_schema] = template_params[:configuration_schema].to_unsafe_h if template_params[:configuration_schema].present?

          permitted
        rescue ActionController::ParameterMissing
          # Allow params without wrapping in template key for backward compatibility
          permitted = params.permit(
            :name, :description, :category, :visibility, :version,
            :source_workflow_id, :is_featured, :is_public, :difficulty_level, :license,
            tags: [],
            metadata: {}
          ).to_h.with_indifferent_access

          # Allow nested hashes for workflow definitions (dynamic JSON schemas)
          permitted[:template_data] = params[:template_data].to_unsafe_h if params[:template_data].present?
          permitted[:configuration_schema] = params[:configuration_schema].to_unsafe_h if params[:configuration_schema].present?

          permitted
        end

        # ===================================================================
        # FILTERING & SORTING
        # ===================================================================

        def apply_template_filters(templates)
          templates = templates.where(category: params[:category]) if params[:category].present?
          if params[:visibility].present?
            templates = templates.where(is_public: params[:visibility] == "public")
          end
          templates = templates.where(difficulty_level: params[:difficulty_level]) if params[:difficulty_level].present?

          if params[:tags].present?
            tag_array = params[:tags].is_a?(Array) ? params[:tags] : params[:tags].split(",")
            # Use PostgreSQL array overlap operator with proper sanitization
            # Convert to PG array using Arel to avoid SQL injection
            templates = templates.where(
              "tags ?| ARRAY[:tags]::text[]",
              tags: tag_array.map(&:to_s)
            )
          end

          if params[:is_featured] == "true"
            templates = templates.where(is_featured: true)
          end

          if params[:q].present? || params[:query].present?
            query = params[:q] || params[:query]
            templates = templates.where("name ILIKE ? OR description ILIKE ?", "%#{query}%", "%#{query}%")
          end

          templates
        end

        def apply_sorting(collection, sort_by)
          case sort_by
          when "name", "title"
            collection.order(:name)
          when "category"
            collection.order(:category, :name)
          when "popular", "installs"
            collection.order(install_count: :desc, created_at: :desc)
          when "rating"
            collection.order(rating: :desc, rating_count: :desc)
          when "recent", "created_at"
            collection.order(created_at: :desc)
          when "updated_at"
            collection.order(updated_at: :desc)
          else
            collection.order(created_at: :desc)
          end
        end

        def apply_pagination(collection)
          page = params[:page]&.to_i || 1
          per_page = params[:per_page]&.to_i || 25
          per_page = 100 if per_page > 100 # Cap at 100

          collection.page(page).per(per_page)
        end

        def pagination_data(collection)
          {
            current_page: collection.current_page,
            per_page: collection.limit_value,
            total_pages: collection.total_pages,
            total_count: collection.total_count
          }
        end

        # ===================================================================
        # SEARCH HELPERS
        # ===================================================================

        def perform_basic_search(query_params)
          query = query_params[:query] || query_params[:q]
          category = query_params[:category]
          tags = query_params[:tags]&.split(",")

          templates = AiWorkflowTemplate.accessible_to_account(current_user&.account&.id || "public")

          if query.present?
            templates = templates.where("name ILIKE ? OR description ILIKE ?", "%#{query}%", "%#{query}%")
          end

          templates = templates.where(category: category) if category.present?
          templates = templates.where("tags && ARRAY[?]::varchar[]", tags) if tags.present?

          templates.includes(:created_by_user)
                   .order(install_count: :desc, created_at: :desc)
                   .page(params[:page])
                   .per(params[:per_page] || 25)
        end

        # ===================================================================
        # TEMPLATE CREATION HELPERS
        # ===================================================================

        def extract_workflow_template_data(workflow)
          {
            workflow: {
              name: workflow.name,
              description: workflow.description,
              version: workflow.version,
              status: workflow.status
            },
            nodes: workflow.nodes.map { |node| extract_node_data(node) },
            edges: workflow.edges.map { |edge| extract_edge_data(edge) },
            triggers: workflow.triggers.map { |trigger| extract_trigger_data(trigger) },
            variables: workflow.variables.map { |var| extract_variable_data(var) }
          }
        end

        def extract_node_data(node)
          {
            node_id: node.node_id,
            node_type: node.node_type,
            name: node.name,
            description: node.description,
            configuration: node.configuration || {},
            position: node.position
          }
        end

        def extract_edge_data(edge)
          {
            source_node_id: edge.source_node_id,
            target_node_id: edge.target_node_id,
            edge_type: edge.edge_type,
            condition: edge.condition,
            configuration: edge.configuration || {}
          }
        end

        def extract_trigger_data(trigger)
          {
            trigger_type: trigger.trigger_type,
            name: trigger.name,
            configuration: trigger.configuration,
            is_active: trigger.is_active
          }
        end

        def extract_variable_data(variable)
          {
            key: variable.key,
            value: variable.value,
            variable_type: variable.variable_type,
            description: variable.description,
            is_required: variable.is_required
          }
        end

        def generate_configuration_schema(workflow)
          {
            type: "object",
            properties: {},
            required: [],
            description: "Configuration schema for #{workflow.name}"
          }
        end

        def calculate_complexity_score(workflow)
          node_count = workflow.nodes.count
          edge_count = workflow.edges.count
          trigger_count = workflow.triggers.count

          # Simple complexity score calculation
          (node_count * 1.0) + (edge_count * 0.5) + (trigger_count * 1.5)
        end

        def create_workflow_from_template(template, installation)
          workflow_data = template.workflow_definition.deep_symbolize_keys

          # Create workflow
          workflow = current_user.account.ai_workflows.create!(
            name: template.name,
            description: template.description,
            status: "draft",
            version: template.version,
            configuration: { enabled: true, from_template: true },
            creator: current_user
          )

          # Get custom configuration if installation provided
          custom_config = installation&.custom_configuration || {}

          # Create nodes
          node_mapping = {}
          workflow_data[:nodes]&.each do |node_data|
            config = merge_custom_configuration(node_data[:configuration], custom_config)
            # Ensure configuration is not blank - add placeholder if empty
            config = { enabled: true } if config.blank? || config.empty?

            node = workflow.nodes.create!(
              node_id: node_data[:node_id],
              node_type: node_data[:node_type],
              name: node_data[:name],
              description: node_data[:description],
              configuration: config,
              position: node_data[:position]
            )
            node_mapping[node_data[:node_id]] = node
          end

          # Create edges
          workflow_data[:edges]&.each do |edge_data|
            source_node = node_mapping[edge_data[:source_node_id]]
            target_node = node_mapping[edge_data[:target_node_id]]

            next unless source_node && target_node

            # Generate edge_id from source and target
            edge_id = "#{edge_data[:source_node_id]}_to_#{edge_data[:target_node_id]}"

            workflow.edges.create!(
              edge_id: edge_id,
              source_node: source_node,
              target_node: target_node,
              edge_type: edge_data[:edge_type],
              condition: edge_data[:condition] || {},
              configuration: edge_data[:configuration] || {}
            )
          end

          # Create triggers
          workflow_data[:triggers]&.each do |trigger_data|
            workflow.triggers.create!(
              trigger_type: trigger_data[:trigger_type],
              name: trigger_data[:name],
              configuration: trigger_data[:configuration],
              is_active: trigger_data[:is_active]
            )
          end

          # Create variables
          workflow_data[:variables]&.each do |var_data|
            workflow.variables.create!(
              key: var_data[:key],
              value: var_data[:value],
              variable_type: var_data[:variable_type],
              description: var_data[:description],
              is_required: var_data[:is_required]
            )
          end

          workflow
        end

        def merge_custom_configuration(default_config, custom_config)
          default_config = default_config || {}
          return default_config if custom_config.blank?

          default_config.deep_merge(custom_config)
        end

        # ===================================================================
        # RATING HELPERS
        # ===================================================================

        def update_template_rating(template, rating_value, feedback)
          # Update running average
          current_total = template.rating * template.rating_count
          new_total = current_total + rating_value
          new_count = template.rating_count + 1
          new_average = new_total / new_count.to_f

          template.update!(
            rating: new_average.round(2),
            rating_count: new_count
          )
        end

        # ===================================================================
        # SERIALIZATION
        # ===================================================================

        def serialize_templates(templates)
          templates.map { |t| serialize_template(t) }
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
            created_by: template.created_by_user ? {
              id: template.created_by_user.id,
              name: template.created_by_user.full_name,
              email: template.created_by_user.email
            } : nil,
            metadata: template.metadata,
            can_install: template.can_install?(current_user&.account),
            can_edit: template.can_edit?(current_user, current_user&.account)
          }
        end

        def serialize_template_detail(template)
          source_workflow_id = template.metadata&.dig("source_workflow_id")
          source_workflow_data = if source_workflow_id
            workflow = AiWorkflow.find_by(id: source_workflow_id)
            workflow ? { id: workflow.id, name: workflow.name } : nil
          end

          serialize_template(template).merge(
            template_data: template.workflow_definition,
            configuration_schema: template.metadata&.dig("configuration_schema") || {},
            license: template.license,
            updated_at: template.updated_at.iso8601,
            source_workflow: source_workflow_data,
            recent_installations: template.installations
                                          .includes(:installed_by_user)
                                          .order(created_at: :desc)
                                          .limit(10)
                                          .map { |inst| serialize_installation(inst) },
            can_delete: template.can_delete?(current_user, current_user&.account),
            can_publish: template.can_publish?(current_user, current_user&.account)
          )
        end

        def serialize_installation(installation)
          {
            id: installation.id,
            installed_version: installation.template_version || installation.ai_workflow_template.version,
            created_at: installation.created_at.iso8601,
            installed_by: installation.installed_by_user ? {
              id: installation.installed_by_user.id,
              name: installation.installed_by_user.full_name,
              email: installation.installed_by_user.email
            } : nil
          }
        end

        def serialize_installation_detail(installation)
          serialize_installation(installation).merge(
            template: {
              id: installation.ai_workflow_template.id,
              name: installation.ai_workflow_template.name,
              description: installation.ai_workflow_template.description,
              category: installation.ai_workflow_template.category,
              version: installation.ai_workflow_template.version
            },
            created_workflow: installation.ai_workflow ? {
              id: installation.ai_workflow.id,
              name: installation.ai_workflow.name,
              description: installation.ai_workflow.description,
              status: installation.ai_workflow.status,
              created_at: installation.ai_workflow.created_at.iso8601
            } : nil
          )
        end

        def serialize_created_workflow(workflow)
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

        # ===================================================================
        # HELPERS
        # ===================================================================

        def category_description(category)
          descriptions = {
            "automation" => "Automate repetitive tasks and workflows",
            "data_processing" => "Process and transform data efficiently",
            "integration" => "Connect and integrate different services",
            "analytics" => "Analyze data and generate insights",
            "notification" => "Send notifications and alerts",
            "custom" => "Custom workflow templates"
          }

          descriptions[category] || category.humanize
        end

        def log_audit_event(event_type, resource, additional_data = {})
          return unless respond_to?(:audit_log)

          audit_log(
            event_type: event_type,
            resource_type: resource.class.name,
            resource_id: resource.id,
            metadata: additional_data
          )
        end
      end
    end
  end
end

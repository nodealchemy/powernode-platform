# frozen_string_literal: true

module Api
  module V1
    module Marketplace
      class ItemsController < ApplicationController
        skip_before_action :authenticate_request, only: [ :index, :show, :categories, :featured ]
        before_action :authenticate_optional, only: [ :index, :show, :categories, :featured ]

        # GET /api/v1/marketplace
        # Lists all marketplace items - supports feature-aligned types
        def index
          items = []

          # Filter types (default to all feature-aligned types)
          default_types = %w[workflow_template pipeline_template integration_template prompt_template]
          requested_types = params[:types]&.split(",") || default_types

          # Feature-aligned types
          items += normalize_workflow_templates(filtered_workflow_templates) if requested_types.include?("workflow_template")
          items += normalize_pipeline_templates(filtered_pipeline_templates) if requested_types.include?("pipeline_template")
          items += normalize_integration_templates(filtered_integration_templates) if requested_types.include?("integration_template")
          items += normalize_prompt_templates(filtered_prompt_templates) if requested_types.include?("prompt_template")

          # Legacy types (template and integration only)
          items += normalize_templates(filtered_templates) if requested_types.include?("template")
          items += normalize_integrations(filtered_integrations) if requested_types.include?("integration")

          # Apply search filter if provided
          if params[:search].present?
            search_term = params[:search].downcase
            items.select! do |item|
              item[:name].to_s.downcase.include?(search_term) ||
                item[:description].to_s.downcase.include?(search_term)
            end
          end

          # Apply category filter
          if params[:category].present?
            items.select! { |item| item[:category].to_s.downcase == params[:category].downcase }
          end

          # Apply pagination
          pagination = pagination_params
          total_count = items.count
          total_pages = (total_count.to_f / pagination[:per_page]).ceil

          paginated_items = items.slice(
            (pagination[:page] - 1) * pagination[:per_page],
            pagination[:per_page]
          ) || []

          render_success(
            paginated_items,
            meta: {
              current_page: pagination[:page],
              per_page: pagination[:per_page],
              total_count: total_count,
              total_pages: total_pages,
              filters: {
                types: requested_types,
                search: params[:search],
                category: params[:category],
                verified: params[:verified]
              }
            }
          )
        end

        # GET /api/v1/marketplace/unified/featured
        # Returns featured items across all types
        def featured
          items = []

          # Get featured/verified items from each type
          items += normalize_templates(featured_templates)
          items += normalize_integrations(featured_integrations)

          # Sort by rating and install count
          items.sort_by! { |i| [ -i[:rating], -i[:install_count] ] }

          render_success(items.take(12))
        end

        # GET /api/v1/marketplace/unified/categories
        # Returns available categories across all types
        def categories
          categories = {}

          # Add integration templates to categories
          ::Devops::IntegrationTemplate.marketplace_published.pluck(:category).compact.each do |cat|
            categories[cat] ||= { name: cat, count: 0, types: [] }
            categories[cat][:count] += 1
            categories[cat][:types] |= [ "integration" ]
          end

          ::Ai::WorkflowTemplate.public_templates.published.pluck(:category).compact.each do |cat|
            categories[cat] ||= { name: cat, count: 0, types: [] }
            categories[cat][:count] += 1
            categories[cat][:types] |= [ "template" ]
          end

          render_success(categories.values.sort_by { |c| -c[:count] })
        end

        # GET /api/v1/marketplace/unified/:type/:id
        # Gets a single marketplace item by type and ID
        def show
          item_type = params[:type]
          item_id = params[:id]

          item = case item_type
          # Feature-aligned types
          when "workflow_template"
                   find_workflow_template(item_id)
          when "pipeline_template"
                   find_pipeline_template(item_id)
          when "integration_template"
                   find_integration_template(item_id)
          when "prompt_template"
                   find_prompt_template(item_id)
          # Legacy types
          when "template"
                   find_template(item_id)
          when "integration"
                   find_integration(item_id)
          else
                   return render_error("Invalid item type: #{item_type}", :bad_request)
          end

          return render_error("#{item_type.tr('_', ' ').titleize} not found", :not_found) unless item

          normalized_item = normalize_item(item, item_type)

          # Add subscription info if authenticated
          if current_user && current_account
            normalized_item[:subscription] = get_subscription_info(item, item_type)
          end

          render_success(normalized_item)
        end

        # POST /api/v1/marketplace/unified/:type/:id/subscribe
        # Creates a subscription to a marketplace item
        def subscribe
          return render_error("Authentication required", :unauthorized) unless current_user

          item_type = params[:type]
          item_id = params[:id]

          orchestrator = ::Marketplace::SubscriptionOrchestrator.new(
            account: current_account,
            user: current_user
          )

          result = orchestrator.subscribe(
            item_type: item_type,
            item_id: item_id,
            options: subscription_options
          )

          if result[:success]
            subscription = result[:data]
            render_success({
              id: subscription.id,
              item_id: subscription.subscribable_id,
              item_type: subscription.subscription_type,
              item_name: subscription.item_name,
              status: subscription.status,
              tier: subscription.tier,
              subscribed_at: subscription.subscribed_at.iso8601
            }, status: :created)
          else
            render_error(result[:errors].join(", "), :unprocessable_content)
          end
        end

        # DELETE /api/v1/marketplace/unified/:type/:id/unsubscribe
        # Cancels a subscription to a marketplace item
        def unsubscribe
          return render_error("Authentication required", :unauthorized) unless current_user

          item_type = params[:type]
          item_id = params[:id]

          # Find the subscription
          item = find_item_by_type(item_type, item_id)
          return render_error("Item not found", :not_found) unless item

          orchestrator = ::Marketplace::SubscriptionOrchestrator.new(
            account: current_account,
            user: current_user
          )

          subscription = orchestrator.subscription_for(item)
          return render_error("No active subscription found", :not_found) unless subscription

          result = orchestrator.unsubscribe(
            subscription_id: subscription.id,
            reason: params[:reason]
          )

          if result[:success]
            render_success({ message: "Subscription cancelled successfully" })
          else
            render_error(result[:errors].join(", "), :unprocessable_content)
          end
        end

        # GET /api/v1/marketplace/unified/subscriptions
        # Lists all subscriptions for current account
        def subscriptions
          return render_error("Authentication required", :unauthorized) unless current_user

          orchestrator = ::Marketplace::SubscriptionOrchestrator.new(
            account: current_account,
            user: current_user
          )

          subs = orchestrator.list_subscriptions(
            type: params[:type],
            status: params[:status]
          )

          subscriptions_data = subs.map do |sub|
            {
              id: sub.id,
              item_id: sub.subscribable_id,
              item_type: sub.subscription_type,
              item_name: sub.item_name,
              item_slug: sub.item_slug,
              status: sub.status,
              tier: sub.tier,
              subscribed_at: sub.subscribed_at.iso8601,
              configuration: sub.configuration,
              usage_metrics: sub.usage_metrics
            }
          end

          render_success(subscriptions_data)
        end

        private

        # Query builders - Feature-aligned types
        def filtered_workflow_templates
          templates = ::Ai::WorkflowTemplate.marketplace_published
          templates = templates.by_category(params[:category]) if params[:category].present?
          templates = templates.search_by_text(params[:search]) if params[:search].present?
          templates = templates.featured if params[:verified] == "true"
          templates
        end

        def filtered_pipeline_templates
          templates = ::Devops::PipelineTemplate.marketplace_published
          templates = templates.by_category(params[:category]) if params[:category].present?
          templates = templates.search_by_text(params[:search]) if params[:search].present?
          templates = templates.featured if params[:verified] == "true"
          templates
        end

        def filtered_integration_templates
          templates = ::Devops::IntegrationTemplate.marketplace_published
          templates = templates.by_type(params[:integration_type]) if params[:integration_type].present?
          templates = templates.by_category(params[:category]) if params[:category].present?
          templates = templates.featured if params[:verified] == "true"
          templates
        end

        def filtered_prompt_templates
          templates = ::Shared::PromptTemplate.marketplace_published
          templates = templates.by_category(params[:category]) if params[:category].present?
          templates = templates.search(params[:search]) if params[:search].present?
          templates
        end

        # Query builders - Legacy types
        def filtered_templates
          templates = ::Ai::WorkflowTemplate.public_templates.published
          templates = templates.by_category(params[:category]) if params[:category].present?
          templates = templates.search_by_text(params[:search]) if params[:search].present?
          templates = templates.featured if params[:verified] == "true"
          templates
        end

        def filtered_integrations
          integrations = ::Devops::IntegrationTemplate.marketplace_published
          integrations = integrations.by_category(params[:category]) if params[:category].present?
          integrations = integrations.search_by_text(params[:search]) if params[:search].present?
          integrations = integrations.featured if params[:verified] == "true"
          integrations
        end

        def featured_templates
          ::Ai::WorkflowTemplate.public_templates.published.featured.limit(3)
        end

        def featured_integrations
          ::Devops::IntegrationTemplate.marketplace_published.featured.limit(3)
        end

        # Normalizers - Feature-aligned types
        def normalize_workflow_templates(templates)
          templates.map do |template|
            {
              id: template.id,
              type: "workflow_template",
              name: template.name,
              slug: template.slug,
              description: template.description,
              category: template.category,
              tags: template.tags || [],
              icon: template.metadata&.dig("icon"),
              version: template.version,
              rating: template.rating || template.marketplace_rating || 0.0,
              rating_count: template.rating_count || template.marketplace_review_count || 0,
              install_count: template.usage_count || 0,
              is_verified: template.is_featured || false,
              is_featured: template.is_featured || false,
              difficulty_level: template.difficulty_level,
              node_count: template.node_count,
              status: template.published? ? "published" : "draft",
              publisher: serialize_publisher(template.account),
              created_at: template.created_at.iso8601
            }
          end
        end

        def normalize_pipeline_templates(templates)
          templates.map do |template|
            {
              id: template.id,
              type: "pipeline_template",
              name: template.name,
              slug: template.slug,
              description: template.description,
              category: template.category,
              tags: template.tags || [],
              icon: template.icon_url,
              version: template.version,
              rating: template.rating || 0.0,
              rating_count: template.rating_count || 0,
              install_count: template.usage_count || 0,
              is_verified: template.is_featured || false,
              is_featured: template.is_featured || false,
              difficulty_level: template.difficulty_level,
              step_count: template.step_count,
              status: template.published? ? "published" : "draft",
              publisher: serialize_publisher(template.account),
              created_at: template.created_at.iso8601
            }
          end
        end

        def normalize_integration_templates(templates)
          templates.map do |template|
            {
              id: template.id,
              type: "integration_template",
              name: template.name,
              slug: template.slug,
              description: template.description,
              category: template.category,
              tags: [],
              icon: template.icon_url,
              version: template.version,
              rating: 0.0,
              rating_count: 0,
              install_count: template.usage_count || 0,
              is_verified: template.is_featured || false,
              is_featured: template.is_featured || false,
              integration_type: template.integration_type,
              capabilities: template.capabilities || [],
              status: template.is_active? ? "published" : "draft",
              publisher: serialize_publisher(template.account),
              created_at: template.created_at.iso8601
            }
          end
        end

        def normalize_prompt_templates(templates)
          templates.map do |template|
            {
              id: template.id,
              type: "prompt_template",
              name: template.name,
              slug: template.slug,
              description: template.description,
              category: template.category,
              tags: [],
              icon: nil,
              version: template.version.to_s,
              rating: template.rating || 0.0,
              rating_count: template.rating_count || 0,
              install_count: template.usage_count || 0,
              is_verified: false,
              is_featured: false,
              domain: template.domain,
              status: template.is_active? ? "published" : "draft",
              publisher: serialize_publisher(template.account),
              created_at: template.created_at.iso8601
            }
          end
        end

        def serialize_publisher(account)
          return nil unless account

          {
            id: account.id,
            display_name: account.publisher_display_name || account.name,
            bio: account.publisher_bio,
            website: account.publisher_website,
            logo_url: account.publisher_logo_url,
            verified: false
          }
        end

        # Normalizers - Legacy types
        def normalize_templates(templates)
          templates.map do |template|
            {
              id: template.id,
              type: "template",
              name: template.name,
              slug: template.slug,
              description: template.description,
              category: template.category,
              tags: template.tags || [],
              icon: template.metadata&.dig("icon"),
              version: template.version,
              rating: template.rating || template.marketplace_rating || 0.0,
              rating_count: template.marketplace_review_count || 0,
              install_count: template.usage_count || 0,
              is_verified: template.is_featured || false,
              is_featured: template.is_featured || false,
              difficulty_level: template.difficulty_level,
              node_count: template.node_count,
              status: template.published? ? "published" : "draft",
              created_at: template.created_at.iso8601
            }
          end
        end

        def normalize_integrations(integrations)
          integrations.map do |integration|
            {
              id: integration.id,
              type: "integration",
              name: integration.name,
              slug: integration.slug,
              description: integration.description,
              category: integration.metadata&.dig("category") || "integration",
              tags: integration.integration_types || [],
              icon: integration.metadata&.dig("icon"),
              version: integration.version,
              rating: integration.average_rating || integration.marketplace_rating || 0.0,
              rating_count: integration.marketplace_review_count || 0,
              install_count: integration.install_count || 0,
              is_verified: integration.is_verified || false,
              is_featured: integration.is_official || false,
              status: integration.marketplace_published? ? "published" : "draft",
              integration_type: integration.manifest&.dig("integration", "type") || "api",
              capabilities: integration.capabilities || [],
              created_at: integration.created_at.iso8601
            }
          end
        end

        # Item finders
        def find_template(template_id)
          ::Ai::WorkflowTemplate.public_templates.find_by(id: template_id)
        end

        def find_integration(integration_id)
          ::Devops::IntegrationTemplate.marketplace_published.find_by(id: integration_id)
        end

        # Item finders - Feature-aligned types
        def find_workflow_template(template_id)
          ::Ai::WorkflowTemplate.marketplace_published.find_by(id: template_id)
        end

        def find_pipeline_template(template_id)
          ::Devops::PipelineTemplate.marketplace_published.find_by(id: template_id)
        end

        def find_integration_template(template_id)
          ::Devops::IntegrationTemplate.marketplace_published.find_by(id: template_id)
        end

        def find_prompt_template(template_id)
          ::Shared::PromptTemplate.marketplace_published.find_by(id: template_id)
        end

        def find_item_by_type(item_type, item_id)
          case item_type
          # Feature-aligned types
          when "workflow_template"
            ::Ai::WorkflowTemplate.find_by(id: item_id)
          when "pipeline_template"
            ::Devops::PipelineTemplate.find_by(id: item_id)
          when "integration_template"
            ::Devops::IntegrationTemplate.find_by(id: item_id)
          when "prompt_template"
            ::Shared::PromptTemplate.find_by(id: item_id)
          # Legacy types
          when "template"
            ::Ai::WorkflowTemplate.find_by(id: item_id)
          when "integration"
            ::Devops::IntegrationTemplate.find_by(id: item_id)
          end
        end

        def normalize_item(item, type)
          case type
          # Feature-aligned types
          when "workflow_template"
            normalize_workflow_templates([ item ]).first
          when "pipeline_template"
            normalize_pipeline_templates([ item ]).first
          when "integration_template"
            normalize_integration_templates([ item ]).first
          when "prompt_template"
            normalize_prompt_templates([ item ]).first
          # Legacy types
          when "template"
            normalize_templates([ item ]).first
          when "integration"
            normalize_integrations([ item ]).first
          end
        end

        def get_subscription_info(item, item_type)
          return nil unless current_account

          subscription = ::Marketplace::Subscription.where(
            account: current_account,
            subscribable_type: item.class.name,
            subscribable_id: item.id
          ).first

          return nil unless subscription

          {
            id: subscription.id,
            status: subscription.status,
            tier: subscription.tier,
            subscribed_at: subscription.subscribed_at.iso8601
          }
        end

        def subscription_options
          {
            tier: params[:tier] || "standard",
            configuration: params[:configuration] || {},
            create_workflow: params[:create_workflow] == "true",
            workflow_name: params[:workflow_name],
            source: "marketplace_api"
          }
        end

        def authenticate_optional
          header = request.headers["Authorization"]
          return unless header

          header = header.split(" ").last

          begin
            payload = Security::JwtService.decode(header)

            case payload[:type]
            when "access"
              @current_user = User.find(payload[:sub])
              @current_account = @current_user.account
              @current_jwt_payload = payload
            end
          rescue StandardError => e
            Rails.logger.debug "Optional authentication failed: #{e.message}"
            @current_user = nil
            @current_account = nil
          end
        end
      end
    end
  end
end

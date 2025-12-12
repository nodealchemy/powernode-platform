# frozen_string_literal: true

module Api
  module V1
    module Marketplace
      class UnifiedController < ApplicationController
        skip_before_action :authenticate_request, only: [ :index, :show ]
        before_action :authenticate_optional, only: [ :index, :show ]

        # GET /api/v1/marketplace/unified
        # Lists all marketplace items (apps, plugins, templates) with unified format
        def index
          items = []

          # Filter types (default to all three types)
          requested_types = params[:types]&.split(",") || %w[app plugin template]

          # Build items array from each type
          items += normalize_apps(filtered_apps) if requested_types.include?("app")
          items += normalize_plugins(filtered_plugins) if requested_types.include?("plugin")
          items += normalize_templates(filtered_templates) if requested_types.include?("template")

          # Apply search filter if provided
          if params[:search].present?
            search_term = params[:search].downcase
            items.select! do |item|
              item[:name].downcase.include?(search_term) ||
                item[:description].downcase.include?(search_term)
            end
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

        # GET /api/v1/marketplace/unified/:type/:id
        # Gets a single marketplace item by type and ID
        def show
          item_type = params[:type]
          item_id = params[:id]

          item = case item_type
          when "app"
                   find_app(item_id)
          when "plugin"
                   find_plugin(item_id)
          when "template"
                   find_template(item_id)
          else
                   return render_error("Invalid item type: #{item_type}", :bad_request)
          end

          return render_error("#{item_type.capitalize} not found", :not_found) unless item

          normalized_item = normalize_item(item, item_type)
          render_success(normalized_item)
        end

        # POST /api/v1/marketplace/unified/:type/:id/install
        # Installs a marketplace item
        def install
          return render_error("Authentication required", :unauthorized) unless current_user

          item_type = params[:type]
          item_id = params[:id]

          installation = case item_type
          when "app"
                           install_app(item_id)
          when "plugin"
                           install_plugin(item_id)
          when "template"
                           install_template(item_id)
          else
                           return render_error("Invalid item type: #{item_type}", :bad_request)
          end

          if installation[:success]
            render_success(installation[:data], status: :created)
          else
            render_error(installation[:error], :unprocessable_content)
          end
        end

        private

        # Query builders
        def filtered_apps
          apps = MarketplaceListing.includes(:app).approved.published

          apps = apps.by_category(params[:category]) if params[:category].present?
          apps = apps.search(params[:search]) if params[:search].present?

          apps
        end

        def filtered_plugins
          plugins = Plugin.active.where(account: current_account)

          plugins = plugins.search_by_text(params[:search]) if params[:search].present?
          plugins = plugins.verified if params[:verified] == "true"
          plugins = plugins.official if params[:official] == "true"

          plugins
        end

        def filtered_templates
          templates = AiWorkflowTemplate.public_templates.published

          templates = templates.by_category(params[:category]) if params[:category].present?
          templates = templates.search_by_text(params[:search]) if params[:search].present?
          templates = templates.featured if params[:verified] == "true" # Map verified filter to featured

          templates
        end

        # Normalizers - convert each model to unified MarketplaceItem format
        def normalize_apps(apps)
          apps.map do |listing|
            {
              id: listing.app.id,
              type: "app",
              name: listing.title,
              slug: listing.app.slug,
              description: listing.short_description,
              category: listing.category,
              tags: listing.tags || [],
              icon: listing.primary_screenshot&.dig("url"),
              version: listing.app.version || "1.0.0",
              rating: listing.average_rating || 0.0,
              install_count: listing.subscription_count || 0,
              is_verified: listing.app.verified,
              status: listing.published? ? "published" : "draft",
              created_at: listing.created_at.iso8601
            }
          end
        end

        def normalize_plugins(plugins)
          plugins.map do |plugin|
            {
              id: plugin.id,
              type: "plugin",
              name: plugin.name,
              slug: plugin.slug,
              description: plugin.description,
              category: plugin.metadata&.dig("category") || "general",
              tags: plugin.plugin_types || [],
              icon: plugin.metadata&.dig("icon"),
              version: plugin.version,
              rating: plugin.average_rating || 0.0,
              install_count: plugin.install_count || 0,
              is_verified: plugin.is_verified || false,
              status: plugin.status == "available" ? "published" : "draft",
              created_at: plugin.created_at.iso8601
            }
          end
        end

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
              rating: template.rating || 0.0,
              install_count: template.usage_count || 0,
              is_verified: template.is_featured || false,
              status: template.published? ? "published" : "draft",
              created_at: template.created_at.iso8601
            }
          end
        end

        # Item finders
        def find_app(app_id)
          App.find_by(id: app_id)&.marketplace_listing
        end

        def find_plugin(plugin_id)
          Plugin.find_by(id: plugin_id, account: current_account)
        end

        def find_template(template_id)
          AiWorkflowTemplate.public_templates.find_by(id: template_id)
        end

        def normalize_item(item, type)
          case type
          when "app"
            normalize_apps([ item ]).first
          when "plugin"
            normalize_plugins([ item ]).first
          when "template"
            normalize_templates([ item ]).first
          end
        end

        # Install handlers
        def install_app(app_id)
          app = App.find_by(id: app_id)
          return { success: false, error: "App not found" } unless app

          # Create subscription to app's primary plan
          primary_plan = app.app_plans.where(is_primary: true).first || app.app_plans.first
          return { success: false, error: "No plans available for this app" } unless primary_plan

          subscription = AppSubscription.create(
            account: current_account,
            app_plan: primary_plan,
            status: "trial" # Start with trial status
          )

          if subscription.persisted?
            listing = app.marketplace_listing
            {
              success: true,
              data: {
                id: subscription.id,
                item_id: app.id,
                item_type: "app",
                item_name: listing&.title || app.name,
                status: subscription.active? ? "active" : "inactive",
                installed_at: subscription.created_at.iso8601
              }
            }
          else
            { success: false, error: subscription.errors.full_messages.join(", ") }
          end
        rescue StandardError => e
          Rails.logger.error "Failed to install app #{app_id}: #{e.message}"
          { success: false, error: "Installation failed" }
        end

        def install_plugin(plugin_id)
          plugin = Plugin.find_by(id: plugin_id, account: current_account)
          return { success: false, error: "Plugin not found" } unless plugin

          installation = plugin.install_for_account(current_account, current_user, {})

          if installation
            {
              success: true,
              data: {
                id: installation.id,
                item_id: plugin.id,
                item_type: "plugin",
                item_name: plugin.name,
                status: installation.status,
                installed_at: installation.installed_at.iso8601
              }
            }
          else
            { success: false, error: "Installation failed" }
          end
        rescue StandardError => e
          Rails.logger.error "Failed to install plugin #{plugin_id}: #{e.message}"
          { success: false, error: "Installation failed" }
        end

        def install_template(template_id)
          template = AiWorkflowTemplate.public_templates.find_by(id: template_id)
          return { success: false, error: "Template not found" } unless template

          installation = template.install_to_account(
            account_id: current_account.id,
            installed_by_user_id: current_user.id
          )

          if installation.persisted?
            {
              success: true,
              data: {
                id: installation.id,
                item_id: template.id,
                item_type: "template",
                item_name: template.name,
                status: "active",
                installed_at: installation.created_at.iso8601
              }
            }
          else
            { success: false, error: installation.errors.full_messages.join(", ") }
          end
        rescue StandardError => e
          Rails.logger.error "Failed to install template #{template_id}: #{e.message}"
          { success: false, error: "Installation failed" }
        end

        def authenticate_optional
          # Try to authenticate but don't fail if not authenticated
          header = request.headers["Authorization"]
          return unless header

          header = header.split(" ").last

          begin
            payload = JwtService.decode(header)

            case payload[:type]
            when "access"
              @current_user = User.find(payload[:sub])
              @current_account = @current_user.account
              @current_jwt_payload = payload
            end
          rescue StandardError => e
            # Log error but allow anonymous access
            Rails.logger.debug "Optional authentication failed: #{e.message}"
            @current_user = nil
            @current_account = nil
          end
        end
      end
    end
  end
end

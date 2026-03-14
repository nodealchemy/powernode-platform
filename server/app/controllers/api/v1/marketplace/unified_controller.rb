# frozen_string_literal: true

module Api
  module V1
    module Marketplace
      class UnifiedController < ApplicationController
        skip_before_action :authenticate_request, only: [ :index, :show ]
        before_action :authenticate_optional, only: [ :index, :show ]

        # GET /api/v1/marketplace/unified
        # Lists all marketplace items (templates, integrations) with unified format
        def index
          items = []

          # Filter types (default to templates and integrations)
          requested_types = params[:types]&.split(",") || %w[template integration]

          # Build items array from each type
          items += normalize_templates(filtered_templates) if requested_types.include?("template")
          items += normalize_integrations(filtered_integrations) if requested_types.include?("integration")

          # Apply search filter if provided
          if params[:search].present?
            search_term = params[:search].downcase
            items.select! do |item|
              item[:name].downcase.include?(search_term) ||
                item[:description].to_s.downcase.include?(search_term)
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
          when "template"
                   find_template(item_id)
          when "integration"
                   find_integration(item_id)
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
          when "template"
                           install_template(item_id)
          when "integration"
                           install_integration(item_id)
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
        def filtered_templates
          templates = Ai::WorkflowTemplate.public_templates.published

          templates = templates.by_category(params[:category]) if params[:category].present?
          templates = templates.search_by_text(params[:search]) if params[:search].present?
          templates = templates.featured if params[:verified] == "true"

          templates
        end

        def filtered_integrations
          integrations = Devops::IntegrationTemplate.marketplace_published

          integrations = integrations.by_category(params[:category]) if params[:category].present?
          integrations = integrations.search_by_text(params[:search]) if params[:search].present?
          integrations = integrations.featured if params[:verified] == "true"

          integrations
        end

        # Normalizers - convert each model to unified MarketplaceItem format
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
              rating: integration.marketplace_rating || 0.0,
              install_count: integration.install_count || 0,
              is_verified: integration.is_verified || false,
              status: integration.marketplace_published? ? "published" : "draft",
              created_at: integration.created_at.iso8601
            }
          end
        end

        # Item finders
        def find_template(template_id)
          Ai::WorkflowTemplate.public_templates.find_by(id: template_id)
        end

        def find_integration(integration_id)
          Devops::IntegrationTemplate.marketplace_published.find_by(id: integration_id)
        end

        def normalize_item(item, type)
          case type
          when "template"
            normalize_templates([ item ]).first
          when "integration"
            normalize_integrations([ item ]).first
          end
        end

        # Install handlers
        def install_template(template_id)
          template = Ai::WorkflowTemplate.public_templates.find_by(id: template_id)
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

        def install_integration(integration_id)
          integration = Devops::IntegrationTemplate.marketplace_published.find_by(id: integration_id)
          return { success: false, error: "Integration not found" } unless integration

          installation = integration.install_to_account(
            account_id: current_account.id,
            installed_by_user_id: current_user.id
          )

          if installation.persisted?
            {
              success: true,
              data: {
                id: installation.id,
                item_id: integration.id,
                item_type: "integration",
                item_name: integration.name,
                status: "active",
                installed_at: installation.created_at.iso8601
              }
            }
          else
            { success: false, error: installation.errors.full_messages.join(", ") }
          end
        rescue StandardError => e
          Rails.logger.error "Failed to install integration #{integration_id}: #{e.message}"
          { success: false, error: "Installation failed" }
        end

        def authenticate_optional
          # Try to authenticate but don't fail if not authenticated
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

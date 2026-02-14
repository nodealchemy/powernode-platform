# frozen_string_literal: true

module Api
  module V1
    module Ai
      # Phase 4: Agent Marketplace Controller
      # Pre-Built Vertical AI Agent Templates
      class AgentMarketplaceController < ApplicationController
        include ::Ai::MarketplaceSerialization

        before_action :set_service
        before_action :validate_permissions

        # GET /api/v1/ai/agent_marketplace/templates
        def templates
          templates = @service.search_templates(
            query: params[:query],
            category: params[:category],
            vertical: params[:vertical],
            pricing_type: params[:pricing_type],
            page: params[:page] || 1,
            per_page: params[:per_page] || 20
          )

          render_success(
            templates: templates.map { |t| template_json(t) },
            pagination: pagination_meta(templates)
          )
        end

        # GET /api/v1/ai/agent_marketplace/templates/featured
        def featured
          templates = @service.featured_templates(limit: params[:limit] || 10)
          render_success(templates: templates.map { |t| template_json(t) })
        end

        # GET /api/v1/ai/agent_marketplace/templates/:id
        def show_template
          template = ::Ai::AgentTemplate.find(params[:id])
          render_success(template: template_json(template, detailed: true))
        end

        # GET /api/v1/ai/agent_marketplace/categories
        def categories
          categories = @service.list_categories
          render_success(categories: categories.map { |c| category_json(c) })
        end

        # POST /api/v1/ai/agent_marketplace/templates/:template_id/install
        def install
          template = ::Ai::AgentTemplate.find(params[:template_id])
          result = @service.install_template(
            template: template,
            user: current_user,
            custom_config: params[:custom_config] || {}
          )

          if result[:success]
            render_success(installation: installation_json(result[:installation]))
          else
            render_error(result[:error], :unprocessable_content)
          end
        end

        # DELETE /api/v1/ai/agent_marketplace/installations/:id
        def uninstall
          installation = current_account.ai_agent_installations.find(params[:id])
          result = @service.uninstall_template(installation)

          if result[:success]
            render_success(message: "Template uninstalled successfully")
          else
            render_error(result[:error], :unprocessable_content)
          end
        end

        # GET /api/v1/ai/agent_marketplace/installations
        def installations
          installations = current_account.ai_agent_installations
                                         .includes(agent_template: [:publisher])
                                         .order(created_at: :desc)
                                         .page(params[:page])
                                         .per(params[:per_page] || 20)

          render_success(
            installations: installations.map { |i| installation_json(i) },
            pagination: pagination_meta(installations)
          )
        end

        # POST /api/v1/ai/agent_marketplace/templates/:template_id/reviews
        def create_review
          template = ::Ai::AgentTemplate.find(params[:template_id])
          result = @service.create_review(
            template: template,
            user: current_user,
            rating: params[:rating],
            title: params[:title],
            content: params[:content],
            pros: params[:pros] || [],
            cons: params[:cons] || []
          )

          if result[:success]
            render_success(review: review_json(result[:review]))
          else
            render_error(result[:error], :unprocessable_content)
          end
        end

        # GET /api/v1/ai/agent_marketplace/templates/:template_id/reviews
        def reviews
          template = ::Ai::AgentTemplate.find(params[:template_id])
          reviews = template.reviews.published.recent
                           .page(params[:page])
                           .per(params[:per_page] || 20)

          render_success(
            reviews: reviews.map { |r| review_json(r) },
            pagination: pagination_meta(reviews)
          )
        end

        # Publisher endpoints
        # GET /api/v1/ai/agent_marketplace/publisher
        def publisher
          publisher = @service.get_publisher
          if publisher
            render_success(publisher: publisher_json(publisher))
          else
            render_error("No publisher account found", :not_found)
          end
        end

        # POST /api/v1/ai/agent_marketplace/publisher
        def create_publisher
          publisher = @service.create_publisher(
            name: params[:name],
            user: current_user,
            description: params[:description],
            website_url: params[:website_url],
            support_email: params[:support_email]
          )

          render_success(publisher: publisher_json(publisher), status: :created)
        end

        # GET /api/v1/ai/agent_marketplace/publisher/analytics
        def publisher_analytics
          publisher = @service.get_publisher
          return render_error("No publisher account found", :not_found) unless publisher

          analytics = @service.publisher_analytics(
            publisher,
            start_date: params[:start_date]&.to_datetime || 30.days.ago,
            end_date: params[:end_date]&.to_datetime || Time.current
          )

          render_success(analytics: analytics)
        end

        # POST /api/v1/ai/agent_marketplace/compose_team
        # Create a team from multiple marketplace templates
        def compose_team
          template_ids = Array(params[:template_ids])
          return render_error("At least 2 template_ids required", :unprocessable_content) if template_ids.size < 2

          result = @service.compose_team(
            template_ids: template_ids,
            team_name: params[:team_name] || "Marketplace Team",
            team_type: params[:team_type] || "hierarchical",
            coordination_strategy: params[:coordination_strategy] || "manager_led",
            user: current_user
          )

          if result[:success]
            render_success(
              team: {
                id: result[:team].id,
                name: result[:team].name,
                team_type: result[:team].team_type,
                coordination_strategy: result[:team].coordination_strategy,
                agent_count: result[:agents].size
              },
              agents: result[:agents].map { |a| { id: a.id, name: a.name } }
            )
          else
            render_error(result[:error], :unprocessable_content)
          end
        end

        # GET /api/v1/ai/agent_marketplace/analytics
        # Core usage analytics (non-enterprise)
        def analytics
          data = @service.installation_analytics
          render_success(analytics: data)
        end

        private

        def validate_permissions
          return if current_worker

          case action_name
          when "templates", "featured", "show_template", "categories", "installations", "reviews", "analytics"
            require_permission("ai.marketplace.read")
          when "install", "uninstall"
            require_permission("ai.marketplace.manage")
          when "create_review"
            require_permission("ai.marketplace.review")
          when "publisher", "create_publisher", "publisher_analytics"
            require_permission("ai.marketplace.publish")
          when "compose_team"
            require_permission("ai.marketplace.compose")
          end
        end

        def set_service
          @service = ::Ai::MarketplaceService.new(current_account)
        end
      end
    end
  end
end

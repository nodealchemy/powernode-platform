# frozen_string_literal: true

module Api
  module V1
    module Ai
      # Phase 4: Agent Marketplace Controller
      # Pre-Built Vertical AI Agent Templates
      class AgentMarketplaceController < ApplicationController
        before_action :set_service

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

        private

        def set_service
          @service = ::Ai::MarketplaceService.new(current_account)
        end

        def template_json(template, detailed: false)
          json = {
            id: template.id,
            name: template.name,
            slug: template.slug,
            description: template.description,
            category: template.category,
            vertical: template.vertical,
            pricing_type: template.pricing_type,
            price_usd: template.price_usd,
            monthly_price_usd: template.monthly_price_usd,
            version: template.version,
            installation_count: template.installation_count,
            average_rating: template.average_rating,
            review_count: template.review_count,
            is_featured: template.is_featured,
            is_verified: template.is_verified,
            publisher: {
              id: template.publisher.id,
              name: template.publisher.publisher_name,
              slug: template.publisher.publisher_slug,
              verified: template.publisher.verified?
            },
            published_at: template.published_at
          }

          if detailed
            json.merge!(
              long_description: template.long_description,
              agent_config: template.agent_config,
              required_credentials: template.required_credentials,
              required_tools: template.required_tools,
              sample_prompts: template.sample_prompts,
              screenshots: template.screenshots,
              tags: template.tags,
              features: template.features,
              limitations: template.limitations,
              setup_instructions: template.setup_instructions,
              changelog: template.changelog
            )
          end

          json
        end

        def installation_json(installation)
          {
            id: installation.id,
            status: installation.status,
            installed_version: installation.installed_version,
            license_type: installation.license_type,
            executions_count: installation.executions_count,
            total_cost_usd: installation.total_cost_usd,
            last_used_at: installation.last_used_at,
            created_at: installation.created_at,
            template: {
              id: installation.agent_template.id,
              name: installation.agent_template.name,
              slug: installation.agent_template.slug
            }
          }
        end

        def review_json(review)
          {
            id: review.id,
            rating: review.rating,
            title: review.title,
            content: review.content,
            pros: review.pros,
            cons: review.cons,
            is_verified_purchase: review.is_verified_purchase,
            helpful_count: review.helpful_count,
            created_at: review.created_at
          }
        end

        def category_json(category)
          {
            id: category.id,
            name: category.name,
            slug: category.slug,
            description: category.description,
            icon: category.icon,
            template_count: category.template_count,
            children: category.children.active.ordered.map { |c| category_json(c) }
          }
        end

        def publisher_json(publisher)
          {
            id: publisher.id,
            name: publisher.publisher_name,
            slug: publisher.publisher_slug,
            description: publisher.description,
            website_url: publisher.website_url,
            status: publisher.status,
            verification_status: publisher.verification_status,
            total_templates: publisher.total_templates,
            total_installations: publisher.total_installations,
            average_rating: publisher.average_rating,
            lifetime_earnings_usd: publisher.lifetime_earnings_usd,
            pending_payout_usd: publisher.pending_payout_usd
          }
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

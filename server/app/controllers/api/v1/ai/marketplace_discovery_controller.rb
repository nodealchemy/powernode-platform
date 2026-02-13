# frozen_string_literal: true

module Api
  module V1
    module Ai
      class MarketplaceDiscoveryController < ApplicationController
        include AuditLogging

        skip_before_action :authenticate_request, only: [ :discover, :search, :featured, :popular, :categories, :tags, :statistics ]
        before_action :authenticate_request, except: [ :discover, :search, :featured, :popular, :categories, :tags, :statistics ]
        before_action :set_template, only: [ :template_analytics ]
        before_action :validate_permissions, except: [ :discover, :search, :featured, :popular, :categories, :tags, :statistics ]

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
          when "recommendations", "template_analytics"
            require_permission("ai.workflows.read")
          when "compare"
            require_permission("ai.workflows.manage")
          end
        end

        def parse_tags(tags_param)
          return nil if tags_param.blank?
          tags_param.is_a?(Array) ? tags_param : tags_param.split(",")
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

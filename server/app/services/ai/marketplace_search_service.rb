# frozen_string_literal: true

module Ai
  class MarketplaceSearchService
    SORTABLE_FIELDS = %w[created_at installation_count average_rating price_usd name].freeze
    DEFAULT_SORT = "installation_count"
    DEFAULT_ORDER = "desc"

    def initialize(params = {})
      @params = params
    end

    def search
      query = base_query

      # Apply filters
      query = apply_text_search(query)
      query = apply_category_filter(query)
      query = apply_pricing_filter(query)
      query = apply_rating_filter(query)
      query = apply_features_filter(query)
      query = apply_publisher_filter(query)

      # Apply sorting
      query = apply_sorting(query)

      # Return with pagination info
      {
        templates: query,
        total_count: query.unscope(:limit, :offset, :order).count,
        filters_applied: active_filters
      }
    end

    def featured
      base_query
        .where(is_featured: true)
        .order(installation_count: :desc)
        .limit(10)
    end

    def trending(days: 7)
      # Templates with most installations in recent days
      Ai::AgentTemplate
        .published
        .joins(:usage_metrics)
        .where("ai_template_usage_metrics.metric_date >= ?", days.days.ago.to_date)
        .group("ai_agent_templates.id")
        .select("ai_agent_templates.*, SUM(ai_template_usage_metrics.new_installations) as recent_installs")
        .order("recent_installs DESC")
        .limit(10)
    end

    def new_releases(days: 30)
      base_query
        .where("ai_agent_templates.created_at >= ?", days.days.ago)
        .order(created_at: :desc)
        .limit(10)
    end

    def top_rated(min_reviews: 5)
      base_query
        .where("review_count >= ?", min_reviews)
        .order(average_rating: :desc)
        .limit(10)
    end

    def by_category(category_id)
      base_query
        .joins(:categories)
        .where(ai_marketplace_categories: { id: category_id })
        .order(installation_count: :desc)
    end

    def similar_to(template, limit: 6)
      # Find similar templates based on categories and features
      category_ids = template.categories.pluck(:id)

      base_query
        .where.not(id: template.id)
        .where(id: Ai::AgentTemplate
          .joins(:categories)
          .where(ai_marketplace_categories: { id: category_ids })
          .select(:id)
        )
        .order(average_rating: :desc, installation_count: :desc)
        .limit(limit)
    end

    def autocomplete(query, limit: 10)
      return [] if query.blank? || query.length < 2

      Ai::AgentTemplate
        .published
        .where("name ILIKE ?", "#{query}%")
        .or(Ai::AgentTemplate.where("name ILIKE ?", "%#{query}%"))
        .select(:id, :name, :slug, :publisher_id)
        .includes(:publisher)
        .order("CASE WHEN name ILIKE '#{query}%' THEN 0 ELSE 1 END", :name)
        .limit(limit)
        .map do |t|
          {
            id: t.id,
            name: t.name,
            slug: t.slug,
            publisher_name: t.publisher&.publisher_name
          }
        end
    end

    private

    def base_query
      Ai::AgentTemplate
        .published
        .includes(:publisher, :categories)
    end

    def apply_text_search(query)
      search_term = @params[:q] || @params[:query]
      return query if search_term.blank?

      # Full-text search on name, description, and features
      query.where(
        "name ILIKE :term OR description ILIKE :term OR features::text ILIKE :term",
        term: "%#{search_term}%"
      )
    end

    def apply_category_filter(query)
      category_id = @params[:category_id] || @params[:category]
      return query if category_id.blank?

      query.joins(:categories).where(ai_marketplace_categories: { id: category_id })
    end

    def apply_pricing_filter(query)
      pricing_type = @params[:pricing_type]
      min_price = @params[:min_price]
      max_price = @params[:max_price]

      if pricing_type.present?
        query = query.where(pricing_type: pricing_type)
      end

      if min_price.present?
        query = query.where("price_usd >= ? OR pricing_type = 'free'", min_price.to_f)
      end

      if max_price.present?
        query = query.where("price_usd <= ? OR pricing_type = 'free'", max_price.to_f)
      end

      if @params[:free_only] == "true"
        query = query.where(pricing_type: "free")
      end

      query
    end

    def apply_rating_filter(query)
      min_rating = @params[:min_rating]
      return query if min_rating.blank?

      query.where("average_rating >= ?", min_rating.to_f)
    end

    def apply_features_filter(query)
      features = @params[:features]
      return query if features.blank?

      feature_list = features.is_a?(Array) ? features : features.split(",")

      feature_list.each do |feature|
        query = query.where("features @> ?", [ feature ].to_json)
      end

      query
    end

    def apply_publisher_filter(query)
      publisher_id = @params[:publisher_id]
      verified_only = @params[:verified_only]

      if publisher_id.present?
        query = query.where(publisher_id: publisher_id)
      end

      if verified_only == "true"
        query = query.where(is_verified: true)
      end

      query
    end

    def apply_sorting(query)
      sort_field = @params[:sort_by] || DEFAULT_SORT
      sort_order = @params[:sort_order] || DEFAULT_ORDER

      # Validate sort field
      sort_field = DEFAULT_SORT unless SORTABLE_FIELDS.include?(sort_field)
      sort_order = sort_order == "asc" ? :asc : :desc

      query.order(sort_field => sort_order)
    end

    def active_filters
      filters = {}

      filters[:query] = @params[:q] || @params[:query] if (@params[:q] || @params[:query]).present?
      filters[:category] = @params[:category_id] if @params[:category_id].present?
      filters[:pricing_type] = @params[:pricing_type] if @params[:pricing_type].present?
      filters[:min_price] = @params[:min_price] if @params[:min_price].present?
      filters[:max_price] = @params[:max_price] if @params[:max_price].present?
      filters[:min_rating] = @params[:min_rating] if @params[:min_rating].present?
      filters[:free_only] = true if @params[:free_only] == "true"
      filters[:verified_only] = true if @params[:verified_only] == "true"

      filters
    end
  end
end

# frozen_string_literal: true

module Ai
  module Marketplace
    class TemplateDiscoveryService
      module Search
        extend ActiveSupport::Concern

        # Discover templates with filtering
        # @param options [Hash] Discovery options
        # @return [Hash] Discovery results with templates and metadata
        def discover(options = {})
          templates = base_query

          # Apply filters
          templates = apply_discovery_filters(templates, options)

          # Apply sorting
          templates = apply_discovery_sorting(templates, options[:sort_by])

          # Apply pagination
          limit = [ options[:limit]&.to_i || DEFAULT_LIMIT, MAX_LIMIT ].min
          offset = options[:offset]&.to_i || 0
          total_count = templates.count
          templates = templates.limit(limit).offset(offset)

          {
            templates: templates,
            total_count: total_count,
            recommendations: options[:include_recommendations] ? get_recommendations(limit: 5) : []
          }
        end

        # Advanced search with multiple criteria
        # @param options [Hash] Search criteria
        # @return [Hash] Search results
        def advanced_search(options = {})
          templates = base_query

          # Text search
          if options[:query].present?
            search_term = "%#{options[:query]}%"
            templates = templates.where(
              "name ILIKE ? OR description ILIKE ? OR tags::text ILIKE ?",
              search_term, search_term, search_term
            )
          end

          # Category filter
          if options[:categories].present?
            categories = Array(options[:categories])
            templates = templates.where(category: categories)
          end

          # Difficulty filter
          if options[:difficulty_levels].present?
            levels = Array(options[:difficulty_levels])
            templates = templates.where(difficulty_level: levels)
          end

          # Tags filter
          if options[:tags].present?
            tags = Array(options[:tags])
            templates = templates.where("tags ?| ARRAY[:tags]::text[]", tags: tags)
          end

          # Complexity filters
          if options[:min_complexity].present?
            templates = templates.where("(metadata->>'complexity_score')::float >= ?", options[:min_complexity])
          end
          if options[:max_complexity].present?
            templates = templates.where("(metadata->>'complexity_score')::float <= ?", options[:max_complexity])
          end

          # Feature filters
          if options[:has_ai_agents]
            templates = templates.where("(metadata->>'has_ai_agents')::boolean = ?", true)
          end
          if options[:has_webhooks]
            templates = templates.where("(metadata->>'has_webhooks')::boolean = ?", true)
          end
          if options[:has_schedules]
            templates = templates.where("(metadata->>'has_schedules')::boolean = ?", true)
          end

          # Quality filters
          if options[:min_rating].present?
            templates = templates.where("rating >= ?", options[:min_rating])
          end
          if options[:min_usage].present?
            templates = templates.where("usage_count >= ?", options[:min_usage])
          end

          total_count = templates.count
          templates = templates.order(usage_count: :desc, rating: :desc).limit(MAX_LIMIT)

          {
            templates: templates,
            total_count: total_count,
            suggestions: generate_search_suggestions(options[:query])
          }
        end

        private

        def apply_discovery_filters(templates, options)
          templates = templates.where(category: options[:category]) if options[:category].present?
          templates = templates.where(difficulty_level: options[:difficulty]) if options[:difficulty].present?

          if options[:tags].present?
            tags = Array(options[:tags])
            templates = templates.where("tags ?| ARRAY[:tags]::text[]", tags: tags)
          end

          templates = templates.where(is_featured: true) if options[:featured]
          templates = templates.where("rating >= ?", 4.0) if options[:highly_rated]

          templates
        end

        def apply_discovery_sorting(templates, sort_by)
          case sort_by
          when "popularity"
            templates.order(usage_count: :desc)
          when "rating"
            templates.order(rating: :desc, rating_count: :desc)
          when "recent"
            templates.order(created_at: :desc)
          when "name"
            templates.order(:name)
          else
            templates.order(usage_count: :desc, created_at: :desc)
          end
        end

        def generate_search_suggestions(query)
          return [] if query.blank?

          suggestions = []

          # Suggest related categories
          CATEGORIES.each do |category|
            suggestions << "Category: #{category}" if category.include?(query.downcase)
          end

          # Suggest popular tags that match
          matching_tags = ::Ai::WorkflowTemplate.public_templates
                                                .pluck(:tags)
                                                .flatten
                                                .compact
                                                .uniq
                                                .select { |tag| tag.downcase.include?(query.downcase) }
                                                .first(5)

          matching_tags.each do |tag|
            suggestions << "Tag: #{tag}"
          end

          suggestions.first(10)
        end
      end
    end
  end
end

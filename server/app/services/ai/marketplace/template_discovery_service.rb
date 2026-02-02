# frozen_string_literal: true

module Ai
  module Marketplace
    # Service for AI template marketplace discovery, search, and recommendations
    #
    # Provides discovery features including:
    # - Template discovery with filters
    # - Advanced search capabilities
    # - Personalized recommendations
    # - Category and tag exploration
    # - Template comparison
    # - Marketplace statistics
    #
    # Usage:
    #   service = Ai::Marketplace::TemplateDiscoveryService.new(account: current_account, user: current_user)
    #   templates = service.discover(category: 'automation', difficulty: 'beginner')
    #
    class TemplateDiscoveryService
      attr_reader :account, :user

      DEFAULT_LIMIT = 20
      MAX_LIMIT = 100

      CATEGORIES = %w[
        automation
        data_processing
        integration
        analytics
        notification
        ai_assistant
        custom
      ].freeze

      DIFFICULTY_LEVELS = %w[
        beginner
        intermediate
        advanced
        expert
      ].freeze

      def initialize(account:, user: nil)
        @account = account
        @user = user
      end

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

      # Get personalized recommendations for the account
      # @param limit [Integer] Maximum number of recommendations
      # @return [Array<Hash>] Recommended templates with scores
      def get_recommendations(limit: 5)
        return [] unless account

        recommendations = []

        # Get account's installed templates
        installed_template_ids = account.workflow_template_subscriptions
                                        .where(subscribable_type: "Ai::WorkflowTemplate")
                                        .pluck(:subscribable_id)

        # Get account's workflow categories
        account_categories = account.ai_workflows.pluck(:metadata)
                                    .map { |m| m&.dig("category") }
                                    .compact
                                    .uniq

        # Find templates in similar categories not yet installed
        similar_category_templates = base_query
          .where.not(id: installed_template_ids)
          .where(category: account_categories)
          .order(rating: :desc, usage_count: :desc)
          .limit(limit * 2)

        similar_category_templates.each do |template|
          recommendations << {
            template: template,
            recommendation_score: calculate_recommendation_score(template, account_categories),
            recommendation_reasons: generate_recommendation_reasons(template, account_categories)
          }
        end

        # Add popular templates if needed
        if recommendations.size < limit
          popular_templates = base_query
            .where.not(id: installed_template_ids + recommendations.map { |r| r[:template].id })
            .order(usage_count: :desc, rating: :desc)
            .limit(limit - recommendations.size)

          popular_templates.each do |template|
            recommendations << {
              template: template,
              recommendation_score: template.rating * 0.5 + (template.usage_count / 100.0) * 0.5,
              recommendation_reasons: [ "Popular in the community", "Highly rated" ]
            }
          end
        end

        recommendations.sort_by { |r| -r[:recommendation_score] }.first(limit)
      end

      # Compare multiple templates
      # @param template_ids [Array<String>] Template IDs to compare
      # @return [Hash] Comparison data
      def compare_templates(template_ids)
        templates = ::Ai::WorkflowTemplate.where(id: template_ids)

        {
          templates: templates.map do |template|
            {
              id: template.id,
              name: template.name,
              description: template.description,
              category: template.category,
              difficulty_level: template.difficulty_level,
              version: template.version,
              rating: template.rating,
              rating_count: template.rating_count,
              usage_count: template.usage_count,
              node_count: template.metadata&.dig("node_count") || 0,
              complexity_score: template.metadata&.dig("complexity_score") || 0,
              has_ai_agents: template.metadata&.dig("has_ai_agents") || false,
              has_webhooks: template.metadata&.dig("has_webhooks") || false,
              has_schedules: template.metadata&.dig("has_schedules") || false,
              license: template.license,
              created_at: template.created_at.iso8601,
              updated_at: template.updated_at.iso8601
            }
          end,
          comparison_matrix: generate_comparison_matrix(templates),
          recommendation: recommend_from_comparison(templates)
        }
      end

      # Explore available categories
      # @return [Array<Hash>] Category data with counts
      def explore_categories
        category_counts = ::Ai::WorkflowTemplate.public_templates
                                                .group(:category)
                                                .count

        CATEGORIES.map do |category|
          {
            name: category,
            slug: category.parameterize,
            display_name: category.humanize,
            description: category_description(category),
            count: category_counts[category] || 0,
            featured_templates: ::Ai::WorkflowTemplate.public_templates
                                                      .where(category: category)
                                                      .order(rating: :desc)
                                                      .limit(3)
                                                      .pluck(:id, :name)
                                                      .map { |id, name| { id: id, name: name } }
          }
        end.sort_by { |c| -c[:count] }
      end

      # Explore available tags
      # @return [Array<Hash>] Tag data with counts
      def explore_tags
        all_tags = ::Ai::WorkflowTemplate.public_templates
                                         .pluck(:tags)
                                         .flatten
                                         .compact

        tag_counts = all_tags.group_by(&:itself)
                             .transform_values(&:count)
                             .sort_by { |_tag, count| -count }

        tag_counts.first(50).map do |tag, count|
          {
            name: tag,
            count: count,
            related_tags: find_related_tags(tag).first(5)
          }
        end
      end

      # Get marketplace statistics
      # @return [Hash] Marketplace statistics
      def marketplace_statistics
        public_templates = ::Ai::WorkflowTemplate.public_templates

        {
          total_templates: public_templates.count,
          total_installs: public_templates.sum(:usage_count),
          total_ratings: public_templates.sum(:rating_count),
          average_rating: public_templates.average(:rating)&.round(2),
          templates_by_category: public_templates.group(:category).count,
          templates_by_difficulty: public_templates.group(:difficulty_level).count,
          new_this_week: public_templates.where("created_at >= ?", 1.week.ago).count,
          new_this_month: public_templates.where("created_at >= ?", 1.month.ago).count,
          top_categories: public_templates.group(:category)
                                          .order(Arel.sql("COUNT(*) DESC"))
                                          .limit(5)
                                          .count,
          trending_tags: trending_tags(10)
        }
      end

      # Get template analytics
      # @param template_id [String] Template ID
      # @return [Hash] Template analytics
      def template_analytics(template_id)
        template = ::Ai::WorkflowTemplate.find(template_id)

        # Get installation history
        subscriptions = template.subscriptions.order(subscribed_at: :desc)

        {
          total_installs: template.usage_count,
          total_ratings: template.rating_count,
          average_rating: template.rating,
          installs_this_week: subscriptions.where("subscribed_at >= ?", 1.week.ago).count,
          installs_this_month: subscriptions.where("subscribed_at >= ?", 1.month.ago).count,
          installs_by_day: subscriptions.where("subscribed_at >= ?", 30.days.ago)
                                        .group("DATE(subscribed_at)")
                                        .count
                                        .transform_keys(&:to_s),
          category_rank: calculate_category_rank(template),
          similar_templates: find_similar_templates(template, limit: 5)
        }
      end

      # Get featured templates
      # @param limit [Integer] Maximum number of templates
      # @return [Array<Ai::WorkflowTemplate>] Featured templates
      def featured_templates(limit: 10)
        ::Ai::WorkflowTemplate.featured
                              .public_templates
                              .includes(:created_by_user)
                              .order(rating: :desc, usage_count: :desc)
                              .limit(limit)
      end

      # Get popular templates
      # @param limit [Integer] Maximum number of templates
      # @return [Array<Ai::WorkflowTemplate>] Popular templates
      def popular_templates(limit: 10)
        ::Ai::WorkflowTemplate.popular
                              .public_templates
                              .includes(:created_by_user)
                              .order(usage_count: :desc)
                              .limit(limit)
      end

      private

      def base_query
        ::Ai::WorkflowTemplate.accessible_to_account(account&.id || "public")
                              .includes(:created_by_user)
      end

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

      def calculate_recommendation_score(template, account_categories)
        score = 0.0

        # Category match bonus
        score += 2.0 if account_categories.include?(template.category)

        # Rating bonus
        score += template.rating * 0.5 if template.rating.present?

        # Popularity bonus (logarithmic scale)
        score += Math.log10(template.usage_count + 1) * 0.3

        # Freshness bonus for recent templates
        if template.created_at > 30.days.ago
          score += 0.5
        end

        score.round(2)
      end

      def generate_recommendation_reasons(template, account_categories)
        reasons = []

        reasons << "Matches your workflow categories" if account_categories.include?(template.category)
        reasons << "Highly rated (#{template.rating}/5)" if template.rating >= 4.0
        reasons << "Popular choice (#{template.usage_count} installs)" if template.usage_count >= 100
        reasons << "Recently added" if template.created_at > 30.days.ago
        reasons << "Easy to get started" if template.difficulty_level == "beginner"

        reasons.presence || [ "Recommended for you" ]
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

      def generate_comparison_matrix(templates)
        {
          ratings: templates.map { |t| [ t.name, t.rating ] }.to_h,
          usage: templates.map { |t| [ t.name, t.usage_count ] }.to_h,
          complexity: templates.map { |t| [ t.name, t.metadata&.dig("complexity_score") || 0 ] }.to_h,
          node_count: templates.map { |t| [ t.name, t.metadata&.dig("node_count") || 0 ] }.to_h
        }
      end

      def recommend_from_comparison(templates)
        return nil if templates.empty?

        # Simple scoring based on rating and usage
        best = templates.max_by { |t| (t.rating || 0) * 0.6 + Math.log10(t.usage_count + 1) * 0.4 }

        {
          recommended_id: best.id,
          recommended_name: best.name,
          reason: "Best balance of rating (#{best.rating}) and popularity (#{best.usage_count} installs)"
        }
      end

      def category_description(category)
        {
          "automation" => "Automate repetitive tasks and workflows",
          "data_processing" => "Process and transform data efficiently",
          "integration" => "Connect and integrate different services",
          "analytics" => "Analyze data and generate insights",
          "notification" => "Send notifications and alerts",
          "ai_assistant" => "AI-powered assistant workflows",
          "custom" => "Custom workflow templates"
        }[category] || category.humanize
      end

      def find_related_tags(tag)
        # Find tags that commonly appear together
        templates_with_tag = ::Ai::WorkflowTemplate.public_templates
                                                   .where("tags @> ?", [ tag ].to_json)
                                                   .pluck(:tags)

        co_occurring_tags = templates_with_tag.flatten.compact
        co_occurring_tags.delete(tag)

        co_occurring_tags.group_by(&:itself)
                         .transform_values(&:count)
                         .sort_by { |_t, c| -c }
                         .map(&:first)
      end

      def trending_tags(limit)
        recent_templates = ::Ai::WorkflowTemplate.public_templates
                                                 .where("created_at >= ?", 30.days.ago)
                                                 .pluck(:tags)
                                                 .flatten
                                                 .compact

        recent_templates.group_by(&:itself)
                        .transform_values(&:count)
                        .sort_by { |_tag, count| -count }
                        .first(limit)
                        .to_h
      end

      def calculate_category_rank(template)
        category_templates = ::Ai::WorkflowTemplate.public_templates
                                                   .where(category: template.category)
                                                   .order(usage_count: :desc)
                                                   .pluck(:id)

        rank = category_templates.index(template.id)
        rank ? rank + 1 : nil
      end

      def find_similar_templates(template, limit: 5)
        ::Ai::WorkflowTemplate.public_templates
                              .where(category: template.category)
                              .where.not(id: template.id)
                              .order(rating: :desc)
                              .limit(limit)
                              .pluck(:id, :name, :rating)
                              .map { |id, name, rating| { id: id, name: name, rating: rating } }
      end
    end
  end
end

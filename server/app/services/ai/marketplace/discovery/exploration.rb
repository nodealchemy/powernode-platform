# frozen_string_literal: true

module Ai
  module Marketplace
    class TemplateDiscoveryService
      module Exploration
        extend ActiveSupport::Concern

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
end

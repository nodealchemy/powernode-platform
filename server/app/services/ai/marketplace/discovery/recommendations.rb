# frozen_string_literal: true

module Ai
  module Marketplace
    class TemplateDiscoveryService
      module Recommendations
        extend ActiveSupport::Concern

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

        private

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
      end
    end
  end
end

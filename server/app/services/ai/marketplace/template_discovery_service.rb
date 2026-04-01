# frozen_string_literal: true

module Ai
  module Marketplace
    # Service for AI template marketplace discovery, search, and recommendations
    #
    # NOTE: AI Workflow Templates have been removed from the platform.
    # This service is retained as a stub to prevent controller errors.
    #
    class TemplateDiscoveryService
      attr_reader :account, :user

      def initialize(account:, user: nil)
        @account = account
        @user = user
      end

      def discover(options = {})
        {
          templates: [],
          total_count: 0,
          recommendations: []
        }
      end

      def advanced_search(options = {})
        {
          templates: [],
          total_count: 0,
          suggestions: []
        }
      end

      def get_recommendations(limit: 5)
        []
      end

      def compare_templates(template_ids)
        {
          templates: [],
          comparison_matrix: {},
          recommendation: nil
        }
      end

      def explore_categories
        []
      end

      def explore_tags
        []
      end

      def marketplace_statistics
        {
          total_templates: 0,
          total_installs: 0,
          total_ratings: 0,
          average_rating: 0,
          templates_by_category: {},
          templates_by_difficulty: {},
          new_this_week: 0,
          new_this_month: 0,
          top_categories: {},
          trending_tags: {}
        }
      end

      def template_analytics(template_id)
        { error: "AI Workflow Templates have been removed" }
      end

      def featured_templates(limit: 10)
        []
      end

      def popular_templates(limit: 10)
        []
      end
    end
  end
end

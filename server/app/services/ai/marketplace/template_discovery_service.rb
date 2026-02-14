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
      include Search
      include Recommendations
      include Exploration

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

      private

      def base_query
        ::Ai::WorkflowTemplate.accessible_to_account(account&.id || "public")
                              .includes(:created_by_user)
      end
    end
  end
end

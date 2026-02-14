# frozen_string_literal: true

module Ai
  module Memory
    # StorageService - Unified storage for experiential, factual, shared learning, and pool memories
    # Consolidates ExperientialMemoryService, FactualMemoryService, SharedLearningService, MemoryPoolService
    class StorageService
      include Experiential
      include Factual
      include SharedLearning
      include MemoryPool

      # === Experiential constants ===
      DEFAULT_DECAY_RATE = 0.01
      DEFAULT_IMPORTANCE = 0.5

      # === SharedLearning constants ===
      LEARNING_CATEGORIES = %w[fact pattern anti_pattern best_practice discovery].freeze

      LEARNING_MARKERS = {
        "Discovery:" => "discovery",
        "Pattern:" => "pattern",
        "Anti-pattern:" => "anti_pattern",
        "Best practice:" => "best_practice",
        "Fact:" => "fact"
      }.freeze

      attr_reader :account

      def initialize(account:, agent: nil)
        @account = account
        @agent = agent
      end

      private

      def require_agent!
        raise ArgumentError, "agent is required for this operation" unless @agent
      end
    end
  end
end

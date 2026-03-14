# frozen_string_literal: true

module Ai
  class TrajectoryAnalysisJob < ApplicationJob
    queue_as :default

    def perform(account_id = nil)
      return unless Shared::FeatureFlagService.enabled?(:trajectory_analysis)

      if account_id
        account = Account.find(account_id)
        run_for_account(account)
      else
        Account.find_each { |account| run_for_account(account) }
      end
    end

    private

    def run_for_account(account)
      recommender = Ai::Learning::ImprovementRecommender.new(account: account)
      recommendations = recommender.generate_recommendations

      if recommendations.any?
        Rails.logger.info "[TrajectoryAnalysis] Generated #{recommendations.count} recommendations for account #{account.id}"
      end
    rescue => e
      Rails.logger.error "[TrajectoryAnalysis] Failed for account #{account.id}: #{e.message}"
    end
  end
end

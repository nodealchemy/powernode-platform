# frozen_string_literal: true

module Api
  module V1
    module Internal
      module Ai
        class TrajectoryController < InternalBaseController
          # POST /api/v1/internal/ai/trajectory/analyze_all
          def analyze_all
            accounts_processed = 0

            Account.find_each do |account|
              next unless account.feature_enabled?(:trajectory_analysis)

              begin
                recommender = ::Ai::Learning::ImprovementRecommender.new(account: account)
                recommender.generate_recommendations
                accounts_processed += 1
              rescue StandardError => e
                Rails.logger.error "[TrajectoryAnalysis] Failed for account #{account.id}: #{e.message}"
              end
            end

            render_success(accounts_processed: accounts_processed)
          end
        end
      end
    end
  end
end

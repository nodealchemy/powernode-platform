# frozen_string_literal: true

module Ai
  module TeamStrategies
    class StrategyFactory
      STRATEGY_MAP = {
        "sequential" => "Ai::TeamStrategies::SequentialStrategy",
        "parallel" => "Ai::TeamStrategies::ParallelStrategy",
        "hierarchical" => "Ai::TeamStrategies::HierarchicalStrategy",
        "mesh" => "Ai::TeamStrategies::MeshStrategy",
        "workspace" => "Ai::TeamStrategies::SequentialStrategy"
      }.freeze

      def self.build(team:, execution:, account:)
        strategy_class_name = STRATEGY_MAP.fetch(team.team_type) do
          Rails.logger.warn "[StrategyFactory] Unknown team_type '#{team.team_type}', falling back to SequentialStrategy"
          "Ai::TeamStrategies::SequentialStrategy"
        end

        strategy_class = strategy_class_name.constantize
        strategy_class.new(team: team, execution: execution, account: account)
      end
    end
  end
end

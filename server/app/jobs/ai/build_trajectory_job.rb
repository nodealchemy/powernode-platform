# frozen_string_literal: true

module Ai
  class BuildTrajectoryJob < ApplicationJob
    queue_as :default

    def perform(account_id:, team_execution_id:)
      account = Account.find(account_id)
      execution = account.ai_team_executions.find(team_execution_id)

      Ai::TrajectoryService.new(account: account).build_from_team_execution(execution)
    rescue StandardError => e
      Rails.logger.error "[BuildTrajectoryJob] Failed: #{e.message}"
    end
  end
end

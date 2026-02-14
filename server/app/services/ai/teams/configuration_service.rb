# frozen_string_literal: true

module Ai
  module Teams
    class ConfigurationService
      include RoleManagement
      include MemberManagement
      include TeamAnalysis

      IDEAL_ROLE_DISTRIBUTION = {
        "lead" => 1,
        "worker" => 3,
        "reviewer" => 1,
        "specialist" => 2
      }.freeze

      attr_reader :account

      def initialize(account:)
        @account = account
      end

      private

      def find_team(team_id)
        account.ai_agent_teams.find(team_id)
      end
    end
  end
end

# frozen_string_literal: true

module Ai
  module Missions
    class PrManagementService
      class PrError < StandardError; end

      attr_reader :mission, :account

      def initialize(mission:)
        @mission = mission
        @account = mission.account
      end

      def create_branch!(base:, name:)
        client = git_client
        owner, repo_name = repo_parts

        result = client.create_branch(owner, repo_name, new_branch: name, old_branch: base)
        raise PrError, "Failed to create branch: #{result[:error]}" unless result[:success]

        mission.update!(branch_name: name, base_branch: base)
        result
      end

      def create_pr!(head:, base:, title:, body:)
        client = git_client
        owner, repo_name = repo_parts

        result = client.create_pull_request(owner, repo_name, title: title, body: body, head: head, base: base)
        raise PrError, "Failed to create PR: #{result[:error]}" unless result[:success]

        mission.update!(
          pr_number: result[:number],
          pr_url: result[:url]
        )

        MissionChannel.broadcast_mission_event(mission.id, "pr_created", {
          mission_id: mission.id,
          pr_number: result[:number],
          pr_url: result[:url]
        })

        result
      end

      def merge_pr!(pr_number:)
        client = git_client
        owner, repo_name = repo_parts

        result = client.merge_pull_request(owner, repo_name, pr_number)
        raise PrError, "Failed to merge PR: #{result[:error]}" unless result[:success]

        result
      end

      private

      def git_client
        repository = mission.repository
        raise PrError, "No repository linked to mission" unless repository

        credential = find_credential(repository)
        raise PrError, "No git credentials found" unless credential

        Devops::Git::ApiClient.for(credential)
      end

      def repo_parts
        repository = mission.repository
        [repository.owner, repository.name]
      end

      def find_credential(repository)
        account.git_provider_credentials
          .joins(:provider)
          .where(git_providers: { provider_type: repository.provider_type })
          .first
      end
    end
  end
end

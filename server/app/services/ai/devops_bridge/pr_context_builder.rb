# frozen_string_literal: true

module Ai
  module DevopsBridge
    class PrContextBuilder
      def initialize(account:, repository:, pr_number:)
        @account = account
        @repository = repository
        @pr_number = pr_number
      end

      def build
        credential = find_credential
        return nil unless credential

        api_client = build_api_client(credential)
        return nil unless api_client

        pr_data = fetch_pr_data(api_client)
        return nil unless pr_data

        diff = fetch_diff(api_client)

        {
          repository_name: @repository.name,
          provider_type: @repository.provider&.provider_type,
          pr_number: @pr_number,
          title: pr_data[:title],
          description: pr_data[:description] || pr_data[:body],
          author: pr_data[:author] || pr_data[:user],
          base_branch: pr_data[:base_branch] || pr_data.dig(:base, :ref),
          head_branch: pr_data[:head_branch] || pr_data.dig(:head, :ref),
          diff: diff,
          files_changed: pr_data[:changed_files] || pr_data[:files_count],
          additions: pr_data[:additions],
          deletions: pr_data[:deletions]
        }
      rescue => e
        Rails.logger.error "[PrContextBuilder] Failed to build context: #{e.message}"
        nil
      end

      private

      def find_credential
        @repository.credential || @repository.provider&.credentials&.active&.first
      end

      def build_api_client(credential)
        provider_type = @repository.provider&.provider_type
        case provider_type
        when "github"
          Devops::Git::GithubApiClient.new(credential: credential)
        when "gitlab"
          Devops::Git::GitlabApiClient.new(credential: credential)
        when "bitbucket"
          Devops::Git::BitbucketApiClient.new(credential: credential)
        else
          Rails.logger.warn "[PrContextBuilder] Unknown provider type: #{provider_type}"
          nil
        end
      rescue NameError => e
        Rails.logger.warn "[PrContextBuilder] API client not available: #{e.message}"
        nil
      end

      def fetch_pr_data(api_client)
        if api_client.respond_to?(:get_pull_request)
          api_client.get_pull_request(@repository.full_name || @repository.name, @pr_number)
        elsif api_client.respond_to?(:get_merge_request)
          api_client.get_merge_request(@repository.project_id || @repository.name, @pr_number)
        end
      rescue => e
        Rails.logger.error "[PrContextBuilder] Failed to fetch PR data: #{e.message}"
        nil
      end

      def fetch_diff(api_client)
        if api_client.respond_to?(:get_pull_request_diff)
          api_client.get_pull_request_diff(@repository.full_name || @repository.name, @pr_number)
        elsif api_client.respond_to?(:get_merge_request_diff)
          api_client.get_merge_request_diff(@repository.project_id || @repository.name, @pr_number)
        else
          ""
        end
      rescue => e
        Rails.logger.error "[PrContextBuilder] Failed to fetch diff: #{e.message}"
        ""
      end
    end
  end
end

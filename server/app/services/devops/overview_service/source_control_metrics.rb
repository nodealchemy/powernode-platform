# frozen_string_literal: true

module Devops
  class OverviewService
    module SourceControlMetrics
      extend ActiveSupport::Concern

      private

      def generate_source_control_metrics
        {
          providers: provider_metrics,
          repositories: repository_metrics,
          credentials: credential_metrics
        }
      end

      def provider_metrics
        credentials = account.git_provider_credentials
        provider_ids = credentials.select(:git_provider_id).distinct
        providers = Devops::GitProvider.where(id: provider_ids)

        {
          total: providers.count,
          active: providers.active.count,
          by_type: providers.group(:provider_type).count
        }
      end

      def repository_metrics
        repos = account.git_repositories

        {
          total: repos.count,
          active: repos.active.count,
          with_webhook: repos.with_webhook.count
        }
      end

      def credential_metrics
        creds = account.git_provider_credentials

        {
          total: creds.count,
          healthy: creds.healthy.count,
          unhealthy: creds.unhealthy.count,
          expires_soon: creds.expires_soon.count
        }
      end
    end
  end
end

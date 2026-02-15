# frozen_string_literal: true

module Marketing
  module SocialMedia
    class BaseAdapter
      class AdapterError < StandardError; end
      class AuthenticationError < AdapterError; end
      class RateLimitError < AdapterError; end
      class PostError < AdapterError; end

      attr_reader :social_account

      def initialize(social_account)
        @social_account = social_account
      end

      # Override in subclasses
      def platform_name
        raise NotImplementedError, "Subclass must implement #platform_name"
      end

      # Publish a post to the platform
      def post(content, **options)
        raise NotImplementedError, "Subclass must implement #post"
      end

      # Schedule a post for future publishing
      def schedule_post(content, scheduled_at:, **options)
        raise NotImplementedError, "Subclass must implement #schedule_post"
      end

      # Delete a post from the platform
      def delete_post(platform_post_id)
        raise NotImplementedError, "Subclass must implement #delete_post"
      end

      # Get metrics/analytics for the account or a specific post
      def get_metrics(platform_post_id: nil)
        raise NotImplementedError, "Subclass must implement #get_metrics"
      end

      # Test the connection/credentials
      def test_connection
        raise NotImplementedError, "Subclass must implement #test_connection"
      end

      # Refresh an expired OAuth token
      def refresh_token
        raise NotImplementedError, "Subclass must implement #refresh_token"
      end

      protected

      def credentials
        @credentials ||= fetch_credentials
      end

      def fetch_credentials
        return {} unless @social_account.vault_path.present?

        # Credentials are stored in vault, accessed via vault_path
        { vault_path: @social_account.vault_path }
      end

      def log_api_call(method, endpoint, status)
        Rails.logger.info "[Marketing::SocialMedia::#{platform_name}] #{method} #{endpoint} -> #{status}"
      end

      def with_retry(max_attempts: 3)
        attempts = 0
        begin
          attempts += 1
          yield
        rescue RateLimitError => e
          if attempts < max_attempts
            sleep(2**attempts)
            retry
          end
          raise
        end
      end
    end
  end
end

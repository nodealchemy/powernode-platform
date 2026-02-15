# frozen_string_literal: true

module Marketing
  module SocialMedia
    module Adapters
      class TwitterAdapter < BaseAdapter
        MAX_TWEET_LENGTH = 280

        def platform_name
          "Twitter"
        end

        def post(content, **options)
          validate_content_length!(content)
          raise NotImplementedError, "Twitter API v2 integration not yet implemented"
        end

        def schedule_post(content, scheduled_at:, **options)
          validate_content_length!(content)
          raise NotImplementedError, "Twitter scheduled posting not yet implemented"
        end

        def delete_post(platform_post_id)
          raise NotImplementedError, "Twitter post deletion not yet implemented"
        end

        def get_metrics(platform_post_id: nil)
          raise NotImplementedError, "Twitter metrics retrieval not yet implemented"
        end

        def test_connection
          raise NotImplementedError, "Twitter connection test not yet implemented"
        end

        def refresh_token
          raise NotImplementedError, "Twitter OAuth 2.0 token refresh not yet implemented"
        end

        private

        def validate_content_length!(content)
          return if content.length <= MAX_TWEET_LENGTH

          raise PostError, "Tweet exceeds maximum length of #{MAX_TWEET_LENGTH} characters (got #{content.length})"
        end
      end
    end
  end
end

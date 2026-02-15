# frozen_string_literal: true

module Marketing
  module SocialMedia
    module Adapters
      class FacebookAdapter < BaseAdapter
        MAX_POST_LENGTH = 63206

        def platform_name
          "Facebook"
        end

        def post(content, **options)
          validate_content_length!(content)
          raise NotImplementedError, "Facebook Graph API integration not yet implemented"
        end

        def schedule_post(content, scheduled_at:, **options)
          validate_content_length!(content)
          raise NotImplementedError, "Facebook scheduled posting not yet implemented"
        end

        def delete_post(platform_post_id)
          raise NotImplementedError, "Facebook post deletion not yet implemented"
        end

        def get_metrics(platform_post_id: nil)
          raise NotImplementedError, "Facebook metrics retrieval not yet implemented"
        end

        def test_connection
          raise NotImplementedError, "Facebook connection test not yet implemented"
        end

        def refresh_token
          raise NotImplementedError, "Facebook OAuth token refresh not yet implemented"
        end

        private

        def validate_content_length!(content)
          return if content.length <= MAX_POST_LENGTH

          raise PostError, "Facebook post exceeds maximum length of #{MAX_POST_LENGTH} characters (got #{content.length})"
        end
      end
    end
  end
end

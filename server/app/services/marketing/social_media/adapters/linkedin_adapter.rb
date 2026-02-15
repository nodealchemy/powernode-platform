# frozen_string_literal: true

module Marketing
  module SocialMedia
    module Adapters
      class LinkedinAdapter < BaseAdapter
        MAX_POST_LENGTH = 3000

        def platform_name
          "LinkedIn"
        end

        def post(content, **options)
          validate_content_length!(content)
          raise NotImplementedError, "LinkedIn Marketing API integration not yet implemented"
        end

        def schedule_post(content, scheduled_at:, **options)
          validate_content_length!(content)
          raise NotImplementedError, "LinkedIn scheduled posting not yet implemented"
        end

        def delete_post(platform_post_id)
          raise NotImplementedError, "LinkedIn post deletion not yet implemented"
        end

        def get_metrics(platform_post_id: nil)
          raise NotImplementedError, "LinkedIn metrics retrieval not yet implemented"
        end

        def test_connection
          raise NotImplementedError, "LinkedIn connection test not yet implemented"
        end

        def refresh_token
          raise NotImplementedError, "LinkedIn OAuth token refresh not yet implemented"
        end

        private

        def validate_content_length!(content)
          return if content.length <= MAX_POST_LENGTH

          raise PostError, "LinkedIn post exceeds maximum length of #{MAX_POST_LENGTH} characters (got #{content.length})"
        end
      end
    end
  end
end

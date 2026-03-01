# frozen_string_literal: true

module Marketing
  module SocialMedia
    module Adapters
      class InstagramAdapter < BaseAdapter
        MAX_CAPTION_LENGTH = 2200
        MAX_HASHTAGS = 30

        def platform_name
          "Instagram"
        end

        def post(content, **options)
          validate_content_length!(content)
          validate_hashtag_count!(content)
          raise NotImplementedError, "Instagram Graph API integration not yet implemented"
        end

        def schedule_post(content, scheduled_at:, **options)
          validate_content_length!(content)
          raise NotImplementedError, "Instagram scheduled posting not yet implemented"
        end

        def delete_post(platform_post_id)
          raise NotImplementedError, "Instagram post deletion not yet implemented"
        end

        def get_metrics(platform_post_id: nil)
          raise NotImplementedError, "Instagram metrics retrieval not yet implemented"
        end

        def test_connection
          raise NotImplementedError, "Instagram connection test not yet implemented"
        end

        def refresh_token
          raise NotImplementedError, "Instagram OAuth token refresh not yet implemented"
        end

        private

        def validate_content_length!(content)
          return if content.length <= MAX_CAPTION_LENGTH

          raise PostError, "Instagram caption exceeds maximum length of #{MAX_CAPTION_LENGTH} characters (got #{content.length})"
        end

        def validate_hashtag_count!(content)
          hashtag_count = content.scan(/#\w+/).count
          return if hashtag_count <= MAX_HASHTAGS

          raise PostError, "Instagram post exceeds maximum of #{MAX_HASHTAGS} hashtags (got #{hashtag_count})"
        end
      end
    end
  end
end

# frozen_string_literal: true

module Marketing
  module SocialMedia
    class AdapterFactory
      ADAPTERS = {
        "twitter" => "Marketing::SocialMedia::Adapters::TwitterAdapter",
        "linkedin" => "Marketing::SocialMedia::Adapters::LinkedinAdapter",
        "facebook" => "Marketing::SocialMedia::Adapters::FacebookAdapter",
        "instagram" => "Marketing::SocialMedia::Adapters::InstagramAdapter"
      }.freeze

      class << self
        def for_account(social_account)
          adapter_class = ADAPTERS[social_account.platform]

          raise BaseAdapter::AdapterError, "Unsupported platform: #{social_account.platform}" unless adapter_class

          adapter_class.constantize.new(social_account)
        end

        def supported_platforms
          ADAPTERS.keys
        end

        def supported?(platform)
          ADAPTERS.key?(platform)
        end
      end
    end
  end
end

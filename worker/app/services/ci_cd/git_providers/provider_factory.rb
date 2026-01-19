# frozen_string_literal: true

require_relative "gitea_provider"
require_relative "gitlab_provider"
require_relative "github_provider"

module CiCd
  module GitProviders
    # Factory for creating git provider instances
    class ProviderFactory
      PROVIDER_CLASSES = {
        gitea: GiteaProvider,
        gitlab: GitlabProvider,
        github: GithubProvider
      }.freeze

      class << self
        # Create a provider instance from configuration
        # @param type [Symbol, String] Provider type (:gitea, :gitlab, :github)
        # @param api_url [String] Provider API URL
        # @param access_token [String] Authentication token
        # @param logger [Logger, nil] Optional logger
        # @return [BaseProvider] Provider instance
        def create(type:, api_url:, access_token:, logger: nil)
          provider_class = PROVIDER_CLASSES[type.to_sym]

          unless provider_class
            raise ArgumentError, "Unknown provider type: #{type}. " \
                                 "Supported: #{PROVIDER_CLASSES.keys.join(', ')}"
          end

          provider_class.new(
            api_url: api_url,
            access_token: access_token,
            logger: logger
          )
        end

        # Create a provider from a provider record (ActiveRecord-like object)
        # @param provider_record [Object] Provider record with type, api_url, access_token attributes
        # @param logger [Logger, nil] Optional logger
        # @return [BaseProvider] Provider instance
        def from_record(provider_record, logger: nil)
          create(
            type: detect_provider_type(provider_record),
            api_url: provider_record.api_url,
            access_token: decrypt_token(provider_record),
            logger: logger
          )
        end

        # Create a provider from API response data
        # @param data [Hash] Provider data from API
        # @param logger [Logger, nil] Optional logger
        # @return [BaseProvider] Provider instance
        def from_api_data(data, logger: nil)
          type = data["provider_type"] || data["type"] || detect_type_from_url(data["api_url"])

          create(
            type: type,
            api_url: data["api_url"],
            access_token: data["access_token"] || data["api_token"],
            logger: logger
          )
        end

        # Detect provider type from URL patterns
        # @param url [String] API or instance URL
        # @return [Symbol] Detected provider type
        def detect_type_from_url(url)
          return :github if url.nil?

          case url.downcase
          when /github\.com/
            :github
          when /gitlab\.com/, /gitlab/
            :gitlab
          when /gitea/, /forgejo/, /codeberg/
            :gitea
          else
            # Default to Gitea for self-hosted instances
            :gitea
          end
        end

        # Get supported provider types
        # @return [Array<Symbol>] List of supported types
        def supported_types
          PROVIDER_CLASSES.keys
        end

        # Check if a provider type is supported
        # @param type [Symbol, String] Provider type
        # @return [Boolean]
        def supported?(type)
          PROVIDER_CLASSES.key?(type.to_sym)
        end

        private

        def detect_provider_type(provider_record)
          # Try provider_type attribute first
          if provider_record.respond_to?(:provider_type) && provider_record.provider_type.present?
            return provider_record.provider_type.to_sym
          end

          # Try type attribute
          if provider_record.respond_to?(:type) && provider_record.type.present?
            return provider_record.type.to_sym
          end

          # Fall back to URL detection
          detect_type_from_url(provider_record.api_url)
        end

        def decrypt_token(provider_record)
          # Handle encrypted tokens
          if provider_record.respond_to?(:decrypted_access_token)
            provider_record.decrypted_access_token
          elsif provider_record.respond_to?(:access_token)
            provider_record.access_token
          elsif provider_record.respond_to?(:api_token)
            provider_record.api_token
          else
            raise ArgumentError, "Provider record must have access_token or api_token"
          end
        end
      end
    end
  end
end

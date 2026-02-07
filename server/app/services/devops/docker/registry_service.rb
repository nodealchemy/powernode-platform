# frozen_string_literal: true

module Devops
  module Docker
    class RegistryService
      PROVIDER_REGISTRIES = {
        "github" => "ghcr.io",
        "gitlab" => "registry.gitlab.com",
        "bitbucket" => nil
      }.freeze

      def registry_url_for(credential)
        provider = credential.provider

        case provider.provider_type
        when "gitea"
          provider.effective_web_base_url
        when "github"
          PROVIDER_REGISTRIES["github"]
        when "gitlab"
          if provider.self_hosted?
            uri = URI.parse(provider.effective_web_base_url)
            "#{uri.host}:5050"
          else
            PROVIDER_REGISTRIES["gitlab"]
          end
        else
          nil
        end
      end

      def docker_auth_config(credential)
        registry_url = registry_url_for(credential)
        return nil unless registry_url

        username = derive_username(credential)
        token = credential.access_token

        auth_json = {
          "auths" => {
            registry_url => {
              "auth" => Base64.strict_encode64("#{username}:#{token}")
            }
          }
        }

        Base64.strict_encode64(auth_json.to_json)
      end

      def test_registry(credential)
        registry_url = registry_url_for(credential)
        return { success: false, error: "No registry URL for provider type" } unless registry_url

        conn = Faraday.new(url: "https://#{registry_url}") do |f|
          f.options.timeout = 10
          f.options.open_timeout = 5
          f.adapter Faraday.default_adapter
        end

        response = conn.get("/v2/")

        { success: response.status == 200 || response.status == 401, registry_url: registry_url, status: response.status }
      rescue Faraday::Error => e
        { success: false, error: e.message, registry_url: registry_url }
      end

      def available_registries(account)
        account.git_provider_credentials.active.includes(:provider).map do |credential|
          url = registry_url_for(credential)
          next unless url

          {
            credential_id: credential.id,
            credential_name: credential.name,
            provider_type: credential.provider_type,
            registry_url: url
          }
        end.compact
      end

      private

      def derive_username(credential)
        case credential.provider_type
        when "gitea"
          credential.credentials["username"] || credential.user&.email || "token"
        when "github"
          credential.credentials["username"] || "USERNAME"
        when "gitlab"
          "oauth2"
        else
          "token"
        end
      end
    end
  end
end

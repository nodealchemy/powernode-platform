# frozen_string_literal: true

module Ai
  class Provider
    module DevopsIntegration
      extend ActiveSupport::Concern

      included do
        # DevOps-specific scopes
        scope :for_devops, -> { supporting_capability("devops_execution").or(by_type("anthropic")) }
        scope :with_claude_code, -> { where("supported_models @> ?", [ "claude-3-opus" ].to_json) }
        scope :devops_default_for_account, ->(account) {
          for_account(account).active.where("metadata @> ?", { devops_default: true }.to_json)
        }
      end

      # Check if provider supports DevOps operations
      #
      # @return [Boolean]
      def supports_devops?
        supports_capability?("devops_execution") ||
          supports_capability?("code_generation") ||
          provider_type == "anthropic"
      end

      # Check if this is the default DevOps provider for the account
      #
      # @return [Boolean]
      def devops_default?
        metadata&.dig("devops_default") == true
      end

      # Set as the default DevOps provider for the account
      #
      # @return [Boolean]
      def set_as_devops_default!
        # Clear other defaults for this account
        account.ai_providers.where.not(id: id).find_each do |provider|
          provider.update!(metadata: provider.metadata.except("devops_default"))
        end

        # Set this provider as default
        update!(metadata: (metadata || {}).merge("devops_default" => true))
      end

      # Generate environment variables for DevOps execution
      # Used by worker jobs to configure Claude Code CLI
      #
      # @return [Hash] Environment variables for the provider
      def devops_environment_variables
        credential = active_credential
        return {} unless credential

        base_vars = {
          "AI_PROVIDER_ID" => id,
          "AI_PROVIDER_TYPE" => provider_type
        }

        case provider_type
        when "anthropic"
          base_vars.merge(
            "ANTHROPIC_API_KEY" => credential.decrypted_api_key,
            "CLAUDE_MODEL" => default_model_for_devops
          )
        when "google", "vertex"
          base_vars.merge(
            "CLAUDE_CODE_USE_VERTEX" => "1",
            "GOOGLE_CLOUD_PROJECT" => configuration["project_id"],
            "GOOGLE_CLOUD_REGION" => configuration["region"] || "us-central1",
            "GOOGLE_APPLICATION_CREDENTIALS" => credential.configuration&.dig("credentials_path")
          ).compact
        when "azure"
          base_vars.merge(
            "AZURE_OPENAI_API_KEY" => credential.decrypted_api_key,
            "AZURE_OPENAI_ENDPOINT" => api_endpoint,
            "AZURE_OPENAI_DEPLOYMENT" => configuration["deployment_name"]
          ).compact
        else
          # AWS Bedrock or other
          if bedrock_provider?
            base_vars.merge(
              "CLAUDE_CODE_USE_BEDROCK" => "1",
              "AWS_REGION" => configuration["region"] || "us-east-1",
              "AWS_ACCESS_KEY_ID" => credential.configuration&.dig("access_key_id"),
              "AWS_SECRET_ACCESS_KEY" => credential.configuration&.dig("secret_access_key"),
              "AWS_SESSION_TOKEN" => credential.configuration&.dig("session_token")
            ).compact
          else
            base_vars
          end
        end
      end

      # Get model parameters configured for DevOps operations
      #
      # @return [Hash] Model parameters
      def devops_model_params
        {
          model: default_model_for_devops,
          max_tokens: devops_max_tokens,
          max_thinking_tokens: devops_max_thinking_tokens,
          temperature: devops_temperature,
          timeout_seconds: devops_timeout
        }
      end

      # Get the active credential for API access
      #
      # @return [Ai::ProviderCredential, nil]
      def active_credential
        provider_credentials.find_by(is_active: true)
      end

      private

      def bedrock_provider?
        provider_type == "aws" ||
          configuration&.dig("use_bedrock") == true ||
          api_endpoint&.include?("bedrock")
      end

      def default_model_for_devops
        metadata&.dig("devops_model") ||
          supported_models&.find { |m| m.include?("claude-3") } ||
          supported_models&.first ||
          "claude-3-sonnet-20240229"
      end

      def devops_max_tokens
        (metadata&.dig("devops_max_tokens") || configuration&.dig("max_tokens") || 16_000).to_i
      end

      def devops_max_thinking_tokens
        (metadata&.dig("devops_max_thinking_tokens") || configuration&.dig("max_thinking_tokens") || 8000).to_i
      end

      def devops_temperature
        (metadata&.dig("devops_temperature") || configuration&.dig("temperature") || 0.7).to_f
      end

      def devops_timeout
        (metadata&.dig("devops_timeout_seconds") || configuration&.dig("timeout_seconds") || 300).to_i
      end
    end
  end
end

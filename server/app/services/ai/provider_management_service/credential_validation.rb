# frozen_string_literal: true

class Ai::ProviderManagementService
  module CredentialValidation
    extend ActiveSupport::Concern

    class_methods do
      # Create a new provider credential with validation and encryption
      def create_provider_credential(provider, account, credentials_data, name: nil, is_active: nil, is_default: nil, expires_at: nil)
        raise ValidationError, "Provider is required" unless provider
        raise ValidationError, "Account is required" unless account
        raise ValidationError, "Credentials data is required" if credentials_data.blank? || (credentials_data.is_a?(Hash) && credentials_data.empty?)

        # Validate credentials against provider schema
        validate_ai_provider_credentials(provider, credentials_data)

        # Generate a name if not provided
        credential_name = name || "#{provider.name} Credentials"

        # Check for duplicate names within the account
        existing = account.ai_provider_credentials.where(name: credential_name).exists?
        if existing
          credential_name = "#{credential_name} (#{Time.current.strftime('%Y%m%d%H%M%S')})"
        end

        # Build credential attributes
        credential_attrs = {
          provider: provider,
          name: credential_name,
          credentials: credentials_data,
          is_active: is_active.nil? ? true : is_active
        }

        # Add optional attributes if provided
        credential_attrs[:is_default] = is_default unless is_default.nil?
        credential_attrs[:expires_at] = expires_at if expires_at.present?

        # Create the credential
        credential = account.ai_provider_credentials.build(credential_attrs)

        if credential.save
          # Test the credential to ensure it works
          begin
            test_service = new(credential)
            # Use simple format for flat response with :success and :error at top level
            test_result = test_service.test_with_details_simple

            if test_result[:success]
              credential.record_success!
            else
              credential.record_failure!(test_result[:error])
              Rails.logger.warn "Created credential #{credential.id} but initial test failed: #{test_result[:error]}"
            end
          rescue StandardError => e
            Rails.logger.error "Failed to test newly created credential #{credential.id}: #{e.message}"
            credential.record_failure!(e.message)
          end

          credential
        else
          raise CredentialError, "Failed to create credential: #{credential.errors.full_messages.join(', ')}"
        end
      end

      # Validate provider credentials against the provider's schema
      def validate_ai_provider_credentials(provider, credentials_data)
        raise ValidationError, "Provider is required" unless provider
        raise ValidationError, "Credentials data is required" unless credentials_data.present?

        schema = provider.configuration_schema

        # Check schema-defined required fields if present
        if schema.present? && schema["required"].present?
          required_fields = schema["required"] || []
          missing_fields = required_fields - credentials_data.keys.map(&:to_s)

          if missing_fields.any?
            raise ValidationError, "Missing required credentials: #{missing_fields.join(', ')}"
          end
        end

        # Basic validation for known provider types (always runs regardless of schema)
        case provider.provider_type&.downcase
        when "openai"
          validate_openai_credentials(credentials_data)
        when "anthropic"
          validate_anthropic_credentials(credentials_data)
        when "huggingface"
          validate_huggingface_credentials(credentials_data)
        end

        true
      end

      # Test all credentials for an account
      def test_all_credentials(account)
        credentials = account.ai_provider_credentials.active.includes(:provider)
        results = []

        credentials.find_each do |credential|
          begin
            test_service = new(credential)
            # Use simple format for flat response with :success and :error at top level
            test_result = test_service.test_with_details_simple

            # Update credential status based on test result
            if test_result[:success]
              credential.record_success!
            else
              credential.record_failure!(test_result[:error])
            end

            results << {
              credential_id: credential.id,
              credential_name: credential.name,
              provider_name: credential.provider.name,
              success: test_result[:success],
              error: test_result[:error],
              response_time_ms: test_result[:response_time_ms]
            }
          rescue StandardError => e
            credential.record_failure!(e.message)
            results << {
              credential_id: credential.id,
              credential_name: credential.name,
              provider_name: credential.provider.name,
              success: false,
              error: e.message,
              response_time_ms: nil
            }
          end
        end

        results
      end

      # Class methods from former ProviderTestService
      def summarize_test_results(results)
        successful = results.count { |r| r[:success] }
        response_times = results.filter_map { |r| r[:response_time_ms] }

        sorted_by_time = results.select { |r| r[:response_time_ms] }.sort_by { |r| r[:response_time_ms] }

        {
          total_credentials: results.size,
          successful_tests: successful,
          failed_tests: results.size - successful,
          average_response_time: response_times.any? ? response_times.sum / response_times.size.to_f : 0,
          fastest_provider: sorted_by_time.first&.dig(:provider_name),
          slowest_provider: sorted_by_time.last&.dig(:provider_name)
        }
      end

      def health_check_all_providers
        Ai::Provider.active.map do |provider|
          {
            provider_id: provider.id,
            provider_name: provider.name,
            status: "active"
          }
        end
      end

      private

      # Provider-specific credential validation methods
      def validate_openai_credentials(credentials_data)
        api_key = credentials_data["api_key"] || credentials_data[:api_key]
        raise ValidationError, "OpenAI API key is required" unless api_key.present?
        raise ValidationError, "OpenAI API key must start with 'sk-'" unless api_key.start_with?("sk-")
        raise ValidationError, "OpenAI API key appears to be invalid format" unless api_key.length > 20
      end

      def validate_anthropic_credentials(credentials_data)
        api_key = credentials_data["api_key"] || credentials_data[:api_key]
        raise ValidationError, "Anthropic API key is required" unless api_key.present?
        raise ValidationError, "Anthropic API key must start with 'sk-ant-'" unless api_key.start_with?("sk-ant-")
      end

      def validate_huggingface_credentials(credentials_data)
        api_key = credentials_data["api_key"] || credentials_data[:api_key]
        raise ValidationError, "Hugging Face API token is required" unless api_key.present?
        raise ValidationError, "Hugging Face API token appears to be too short" unless api_key.length > 10
      end
    end
  end
end

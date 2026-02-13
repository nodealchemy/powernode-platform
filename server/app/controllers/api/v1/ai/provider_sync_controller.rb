# frozen_string_literal: true

module Api
  module V1
    module Ai
      class ProviderSyncController < ApplicationController
        include AuditLogging

        before_action :set_provider, only: [ :test_connection, :sync_models ]
        before_action :validate_permissions

        # POST /api/v1/ai/providers/:id/test_connection
        def test_connection
          credential_id = params[:credential_id]

          credential = if credential_id.present?
                          find_credential_for_test(credential_id)
          else
                          find_default_credential
          end

          return if credential.nil? # Error already rendered

          test_service = ::Ai::ProviderManagementService.new(credential)
          test_result = test_service.test_with_details_simple

          if test_result[:success]
            credential.record_success!
            @provider.update_health_metrics(true, test_result[:response_time_ms])
          else
            credential.record_failure!(test_result[:error])
            @provider.update_health_metrics(false, test_result[:response_time_ms], test_result[:error])
          end

          render_success(test_result)

          log_audit_event("ai.providers.test_connection", @provider,
            credential_id: credential.id,
            success: test_result[:success],
            response_time: test_result[:response_time_ms]
          )
        end

        # POST /api/v1/ai/providers/:id/sync_models
        def sync_models
          unless @provider.is_active?
            return render_error(
              "Cannot sync models: Provider is not active. Please activate the provider first.",
              status: :unprocessable_content
            )
          end

          success = ::Ai::ProviderManagementService.sync_provider_models(@provider, force_refresh: true)

          if success
            render_success({
              provider: serialize_provider_detail(@provider.reload),
              message: "Provider models synced successfully"
            })

            log_audit_event("ai.providers.sync_models", @provider,
              models_count: @provider.supported_models&.length || 0
            )
          else
            error_message = case @provider.slug
            when "ollama", "remote-ollama-server"
                             "Failed to sync models: Could not connect to Ollama server at #{@provider.api_base_url}. Ensure the server is running."
            else
                             "Failed to sync provider models. Please check the provider configuration."
            end
            render_error(error_message, status: :unprocessable_content)
          end
        end

        # POST /api/v1/ai/providers/sync_all
        def sync_all
          results = ::Ai::ProviderManagementService.sync_all_providers(force_refresh: true)

          render_success({
            results: results,
            message: "Synced #{results[:synced]} providers, #{results[:failed]} failed"
          })

          log_audit_event("ai.providers.sync_all", current_user.account,
            synced: results[:synced],
            failed: results[:failed]
          )
        end

        # POST /api/v1/ai/providers/test_all
        def test_all
          providers = current_user.account.ai_providers.where(is_active: true)
          results = []

          providers.find_each do |provider|
            result = { id: provider.id, name: provider.name, provider_type: provider.provider_type }

            begin
              test_service = ::Ai::ProviderManagementService.new(provider)
              test_result = test_service.test_provider_connection

              result[:success] = test_result[:success]
              result[:message] = test_result[:message]
              result[:response_time_ms] = test_result[:response_time_ms]

              if test_result[:success]
                provider.update(health_status: "healthy", last_health_check_at: Time.current)
              else
                provider.update(health_status: "unhealthy", last_health_check_at: Time.current)
              end
            rescue StandardError => e
              result[:success] = false
              result[:message] = e.message
              provider.update(health_status: "unhealthy", last_health_check_at: Time.current)
            end

            results << result
          end

          successful = results.count { |r| r[:success] }
          failed = results.count { |r| !r[:success] }

          render_success({
            results: results,
            summary: {
              total: results.length,
              successful: successful,
              failed: failed
            }
          })

          log_audit_event("ai.providers.test_all", current_user.account,
            total: results.length,
            successful: successful,
            failed: failed
          )
        end

        # POST /api/v1/ai/providers/setup_defaults
        def setup_defaults
          requested_types = params[:provider_types] || default_provider_types
          created_providers = []

          requested_types.each do |provider_type|
            next if current_user.account.ai_providers.exists?(provider_type: provider_type)

            provider_config = default_provider_config(provider_type)
            next unless provider_config

            provider = current_user.account.ai_providers.build(
              name: provider_config[:name],
              provider_type: provider_type,
              is_active: false,
              configuration: provider_config[:configuration] || {}
            )

            if provider.save
              created_providers << { id: provider.id, name: provider.name, provider_type: provider_type }
            end
          end

          render_success({
            created_providers: created_providers,
            message: created_providers.any? ? "Created #{created_providers.length} default providers" : "All default providers already exist"
          })

          log_audit_event("ai.providers.setup_defaults", current_user.account,
            created_count: created_providers.length
          )
        end

        private

        def set_provider
          @provider = current_user.account.ai_providers.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_error("Provider not found", status: :not_found)
        end

        def validate_permissions
          return if current_worker

          case action_name
          when "test_connection", "test_all"
            require_permission("ai.providers.read")
          when "sync_models", "sync_all"
            require_permission("ai.providers.update")
          when "setup_defaults"
            require_permission("ai.providers.create")
          end
        end

        def find_credential_for_test(credential_id)
          credential = current_user.account.ai_provider_credentials
                                  .includes(:provider)
                                  .find_by(id: credential_id)

          unless credential
            render_error("Credential not found", status: :not_found)
            return nil
          end

          unless credential.provider == @provider
            render_error("Credential does not belong to this provider", status: :bad_request)
            return nil
          end

          credential
        end

        def find_default_credential
          credential = current_user.account.ai_provider_credentials
                                  .includes(:provider)
                                  .find_by(provider: @provider, is_default: true, is_active: true)

          credential ||= current_user.account.ai_provider_credentials
                                     .includes(:provider)
                                     .where(provider: @provider, is_active: true)
                                     .order(created_at: :asc)
                                     .first

          unless credential
            render_error("No active credentials found for this provider", status: :not_found)
            return nil
          end

          credential
        end

        def calculate_provider_health_status(provider)
          return "degraded" unless provider.is_active

          active_credentials = provider.provider_credentials.where(is_active: true)
          return "degraded" if active_credentials.empty?

          tested_credentials = active_credentials.where.not(last_test_at: nil)
          return "healthy" if tested_credentials.empty?

          successful = tested_credentials.where(last_test_status: "success").count
          total = tested_credentials.count
          success_rate = (successful.to_f / total * 100).round

          if success_rate >= 80
            "healthy"
          elsif success_rate >= 50
            "degraded"
          else
            "critical"
          end
        end

        def serialize_provider_detail(provider)
          serialize_provider(provider).merge(
            description: provider.description,
            documentation_url: provider.documentation_url,
            status_url: provider.status_url,
            supported_models: provider.supported_models || [],
            default_parameters: provider.default_parameters,
            rate_limits: provider.rate_limits || {},
            pricing_info: provider.pricing_info || {},
            metadata: provider.metadata,
            credentials: provider.provider_credentials.map { |c| serialize_credential(c) }
          )
        end

        def serialize_provider(provider)
          {
            id: provider.id,
            account_id: provider.account_id,
            name: provider.name,
            slug: provider.slug,
            provider_type: provider.provider_type,
            is_active: provider.is_active,
            api_base_url: provider.api_base_url,
            priority_order: provider.priority_order,
            capabilities: provider.capabilities,
            created_at: provider.created_at.iso8601,
            updated_at: provider.updated_at.iso8601,
            health_status: calculate_provider_health_status(provider),
            stats: {
              credentials_count: provider.provider_credentials.count,
              supported_models_count: provider.supported_models&.length || 0
            },
            credential_count: provider.provider_credentials.count,
            model_count: provider.supported_models&.length || 0
          }
        end

        def serialize_credential(credential)
          {
            id: credential.id,
            name: credential.name,
            is_active: credential.is_active,
            is_default: credential.is_default,
            last_used_at: credential.last_used_at&.iso8601,
            last_test_at: credential.last_test_at&.iso8601,
            last_test_status: credential.last_test_status,
            created_at: credential.created_at.iso8601,
            updated_at: credential.updated_at.iso8601,
            provider: {
              id: credential.provider.id,
              name: credential.provider.name,
              provider_type: credential.provider.provider_type
            },
            stats: {
              success_count: credential.success_count,
              failure_count: credential.failure_count,
              success_rate: calculate_credential_success_rate(credential)
            }
          }
        end

        def calculate_credential_success_rate(credential)
          total = credential.success_count + credential.failure_count
          return 0 if total.zero?

          ((credential.success_count.to_f / total) * 100).round(2)
        end

        def default_provider_types
          %w[openai anthropic google azure_openai groq mistral cohere]
        end

        def default_provider_config(provider_type)
          configs = {
            "openai" => {
              name: "OpenAI",
              configuration: {
                api_base_url: "https://api.openai.com/v1",
                default_model: "gpt-4o",
                supported_models: %w[gpt-4o gpt-4o-mini gpt-4-turbo gpt-3.5-turbo],
                capabilities: %w[chat completions embeddings images]
              }
            },
            "anthropic" => {
              name: "Anthropic",
              configuration: {
                api_base_url: "https://api.anthropic.com/v1",
                default_model: "claude-sonnet-4-20250514",
                supported_models: %w[claude-sonnet-4-20250514 claude-3-5-sonnet-20241022 claude-3-5-haiku-20241022],
                capabilities: %w[chat completions]
              }
            },
            "google" => {
              name: "Google AI (Gemini)",
              configuration: {
                api_base_url: "https://generativelanguage.googleapis.com/v1beta",
                default_model: "gemini-2.0-flash",
                supported_models: %w[gemini-2.0-flash gemini-1.5-pro gemini-1.5-flash],
                capabilities: %w[chat completions embeddings]
              }
            },
            "azure_openai" => {
              name: "Azure OpenAI",
              configuration: {
                api_base_url: nil,
                default_model: "gpt-4o",
                supported_models: %w[gpt-4o gpt-4o-mini gpt-4-turbo],
                capabilities: %w[chat completions embeddings]
              }
            },
            "groq" => {
              name: "Groq",
              configuration: {
                api_base_url: "https://api.groq.com/openai/v1",
                default_model: "llama-3.3-70b-versatile",
                supported_models: %w[llama-3.3-70b-versatile llama-3.1-8b-instant mixtral-8x7b-32768],
                capabilities: %w[chat completions]
              }
            },
            "mistral" => {
              name: "Mistral AI",
              configuration: {
                api_base_url: "https://api.mistral.ai/v1",
                default_model: "mistral-large-latest",
                supported_models: %w[mistral-large-latest mistral-medium-latest mistral-small-latest],
                capabilities: %w[chat completions embeddings]
              }
            },
            "cohere" => {
              name: "Cohere",
              configuration: {
                api_base_url: "https://api.cohere.ai/v1",
                default_model: "command-r-plus",
                supported_models: %w[command-r-plus command-r command-light],
                capabilities: %w[chat completions embeddings]
              }
            }
          }

          configs[provider_type]
        end
      end
    end
  end
end

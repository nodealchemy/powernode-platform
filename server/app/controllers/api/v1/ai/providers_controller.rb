# frozen_string_literal: true

# Consolidated Providers Controller - Phase 3 Controller Consolidation
#
# This controller consolidates provider-related controllers into a single
# RESTful resource controller following the AI Orchestration Redesign pattern.
#
# Consolidates:
# - AiProvidersController (provider CRUD and operations)
# - AiProviderCredentialsController (credential management)
#
# Architecture:
# - Primary resource: Providers
# - Nested resource: Credentials
# - Uses RESTful conventions strictly
# - Thin controller, delegates to services
#
module Api
  module V1
    module Ai
      class ProvidersController < ApplicationController
        include AuditLogging

        # Authentication and resource loading
        before_action :set_provider, only: [
          :show, :update, :destroy,
          :test_connection, :sync_models, :usage_summary, :models, :check_availability
        ], unless: -> { params[:provider_id].present? }

        before_action :set_credential, only: [
          :show, :update, :destroy,
          :credential_test, :credential_make_default, :credential_rotate
        ], if: -> { params[:provider_id].present? }

        before_action :validate_permissions

        # =============================================================================
        # PROVIDERS - PRIMARY RESOURCE CRUD
        # =============================================================================

        # GET /api/v1/ai/providers/:id
        # GET /api/v1/ai/providers/:id
        # GET /api/v1/ai/providers/:provider_id/credentials/:id
        def show
          if params[:provider_id].present?
            # CREDENTIAL SHOW
            render_success({
              credential: serialize_credential_detail(@credential)
            })
          else
            # PROVIDER SHOW
            render_success({
              provider: serialize_provider_detail(@provider)
            })

            log_audit_event("ai.providers.read", @provider)
          end
        end

        # POST /api/v1/ai/providers
        # POST /api/v1/ai/providers/:provider_id/credentials
        def create
          if params[:provider_id].present?
            # CREDENTIAL CREATE
            begin
              provider = current_user.account.ai_providers.find(params[:provider_id])

              # Extract credentials from params and convert to Hash with string keys
              credentials_data = credential_params[:credentials]&.to_h&.deep_stringify_keys || {}

              # Build options hash from permitted params
              options = {
                name: credential_params[:name],
                is_active: credential_params[:is_active],
                is_default: credential_params[:is_default],
                expires_at: credential_params[:expires_at]
              }.compact # Remove nil values

              @credential = AiProviderManagementService.create_provider_credential(
                provider,
                current_user.account,
                credentials_data,
                **options
              )

              render_success({
                credential: serialize_credential_detail(@credential)
              }, status: :created)

              log_audit_event("ai.providers.credential.create", @credential,
                provider_name: provider.name
              )

            rescue ActiveRecord::RecordNotFound
              render_error("Provider not found", status: :not_found)
            rescue AiProviderManagementService::ValidationError => e
              render_error("Validation failed: #{e.message}", status: :unprocessable_content)
            rescue AiProviderManagementService::CredentialError => e
              render_error("Credential error: #{e.message}", status: :unprocessable_content)
            end
          else
            # PROVIDER CREATE
            @provider = AiProvider.new(provider_params)
            @provider.account = current_user.account

            if @provider.save
              render_success({
                provider: serialize_provider_detail(@provider)
              }, status: :created)

              log_audit_event("ai.providers.create", @provider,
                provider_type: @provider.provider_type
              )
            else
              render_validation_error(@provider.errors)
            end
          end
        end

        # PATCH /api/v1/ai/providers/:id
        # PATCH /api/v1/ai/providers/:provider_id/credentials/:id
        def update
          if params[:provider_id].present?
            # CREDENTIAL UPDATE
            # Handle credential updates carefully
            update_params = credential_params.except(:credentials)

            # If credentials are being updated, validate and encrypt them
            if credential_params[:credentials].present?
              begin
                credentials_hash = credential_params[:credentials].to_h.deep_stringify_keys
                AiProviderManagementService.validate_provider_credentials(
                  @credential.ai_provider,
                  credentials_hash
                )

                # Update credentials (will trigger re-encryption)
                @credential.credentials = credentials_hash
              rescue AiProviderManagementService::ValidationError => e
                return render_error("Credential validation failed: #{e.message}", status: :unprocessable_content)
              end
            end

            if @credential.update(update_params)
              render_success({
                credential: serialize_credential_detail(@credential),
                message: "Credential updated successfully"
              })

              log_audit_event("ai.providers.credential.update", @credential,
                changes: @credential.previous_changes.keys
              )
            else
              render_validation_error(@credential.errors)
            end
          else
            # PROVIDER UPDATE
            if @provider.update(provider_params)
              render_success({
                provider: serialize_provider_detail(@provider)
              })

              log_audit_event("ai.providers.update", @provider,
                changes: @provider.previous_changes.keys
              )
            else
              render_validation_error(@provider.errors)
            end
          end
        end

        # DELETE /api/v1/ai/providers/:id
        # DELETE /api/v1/ai/providers/:provider_id/credentials/:id
        def destroy
          if params[:provider_id].present?
            # CREDENTIAL DESTROY
            credential_name = @credential.name
            provider_name = @credential.ai_provider.name

            if @credential.destroy
              render_success({ message: "Credential deleted successfully" })

              log_audit_event("ai.providers.credential.delete", current_user.account,
                credential_name: credential_name,
                provider_name: provider_name
              )
            else
              # Return specific validation errors if present
              if @credential.errors.any?
                render_validation_error(@credential.errors)
              else
                render_error("Failed to delete credential", status: :unprocessable_content)
              end
            end
          else
            # PROVIDER DESTROY
            provider_name = @provider.name

            if @provider.destroy
              render_success({ message: "AI provider deleted successfully" })

              log_audit_event("ai.providers.delete", current_user.account,
                provider_name: provider_name
              )
            else
              render_error("Failed to delete provider", status: :unprocessable_content)
            end
          end
        end

        # =============================================================================
        # PROVIDERS - CUSTOM ACTIONS
        # =============================================================================

        # POST /api/v1/ai/providers/:id/test_connection
        def test_connection
          credential_id = params[:credential_id]

          credential = if credential_id.present?
                        find_credential_for_test(credential_id)
          else
                        find_default_credential
          end

          return if credential.nil? # Error already rendered

          test_service = AiProviderTestService.new(credential)
          # Use test_with_details_simple for flat response format expected by controller
          test_result = test_service.test_with_details_simple

          # Update credential status based on test result
          if test_result[:success]
            credential.record_success!
            # Also update provider's health metrics so it's marked as healthy
            @provider.update_health_metrics(true, test_result[:response_time_ms])
          else
            credential.record_failure!(test_result[:error])
            # Update provider's health metrics with failure
            @provider.update_health_metrics(false, test_result[:response_time_ms], test_result[:error])
          end

          render_success(test_result)

          log_audit_event("ai.providers.test_connection", @provider,
            credential_id: credential.id,
            success: test_result[:success],
            response_time: test_result[:response_time_ms]
          )
        end

        # GET /api/v1/ai/providers/:id/check_availability
        def check_availability
          availability_result = ProviderAvailabilityService.check_provider(@provider)

          render_success({
            provider: {
              id: @provider.id,
              name: @provider.name,
              provider_type: @provider.provider_type
            },
            availability: {
              available: availability_result[:available],
              reason: availability_result[:reason],
              is_active: @provider.is_active?,
              is_healthy: @provider.healthy?,
              has_credentials: @provider.ai_provider_credentials.where(is_active: true).exists?,
              has_models: @provider.available_models.any?,
              health_status: @provider.health_status
            }
          })
        end

        # POST /api/v1/ai/providers/:id/sync_models
        def sync_models
          # Check provider is active first for better error messages
          unless @provider.is_active?
            return render_error(
              "Cannot sync models: Provider is not active. Please activate the provider first.",
              status: :unprocessable_content
            )
          end

          success = AiProviderManagementService.sync_provider_models(@provider)

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

        # GET /api/v1/ai/providers/:id/models
        def models
          render_success({
            provider: {
              id: @provider.id,
              name: @provider.name,
              provider_type: @provider.provider_type
            },
            models: @provider.supported_models || [],
            count: @provider.supported_models&.length || 0
          })
        end

        # GET /api/v1/ai/providers/:id/usage_summary
        def usage_summary
          period_days = params[:period]&.to_i || 30
          period = period_days.days

          summary = AiProviderManagementService.provider_usage_summary(
            @provider,
            current_user.account,
            period
          )

          render_success({
            provider: serialize_provider(@provider),
            usage_summary: summary,
            period: {
              days: period_days,
              start_date: period_days.days.ago.to_date,
              end_date: Date.current
            }
          })
        end

        # GET /api/v1/ai/providers/available
        def available
          providers = AiProviderManagementService.get_available_providers_for_account(current_user.account)

          render_success({
            providers: providers.map { |p| serialize_provider(p) },
            count: providers.count
          })
        end

        # GET /api/v1/ai/providers/statistics
        def statistics
          providers = current_user.account.ai_providers

          stats = {
            total_providers: providers.count,
            active_providers: providers.where(is_active: true).count,
            providers_by_type: providers.group(:provider_type).count,
            total_credentials: AiProviderCredential.joins(:ai_provider)
                                                  .where(ai_providers: { account_id: current_user.account_id })
                                                  .count,
            total_api_calls: calculate_total_api_calls,
            total_cost: calculate_total_cost
          }

          render_success({ statistics: stats })
        end

        # POST /api/v1/ai/providers/setup_defaults
        def setup_defaults
          requested_types = params[:provider_types] || default_provider_types
          created_providers = []

          requested_types.each do |provider_type|
            # Skip if provider of this type already exists
            next if current_user.account.ai_providers.exists?(provider_type: provider_type)

            provider_config = default_provider_config(provider_type)
            next unless provider_config

            provider = current_user.account.ai_providers.build(
              name: provider_config[:name],
              provider_type: provider_type,
              is_active: false, # Inactive until credentials are added
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

        # POST /api/v1/ai/providers/test_all
        def test_all
          providers = current_user.account.ai_providers.where(is_active: true)
          results = []

          providers.find_each do |provider|
            result = { id: provider.id, name: provider.name, provider_type: provider.provider_type }

            begin
              test_service = AiProviderTestService.new(provider)
              test_result = test_service.test_provider_connection

              result[:success] = test_result[:success]
              result[:message] = test_result[:message]
              result[:response_time_ms] = test_result[:response_time_ms]

              # Update provider health status
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

        # =============================================================================
        # CREDENTIALS - NESTED RESOURCE
        # =============================================================================

        # GET /api/v1/ai/providers
        # GET /api/v1/ai/providers/:provider_id/credentials
        def index
          # Determine if this is a credentials request or providers request
          if params[:provider_id].present? || current_worker
            # CREDENTIALS INDEX
            credentials = if current_worker
                           # Worker can access any credentials for background processing
                           AiProviderCredential.includes(:ai_provider)
            else
                           # Nested under specific provider
                           provider = current_user.account.ai_providers.find(params[:provider_id])
                           provider.ai_provider_credentials
            end

            credentials = apply_credential_filters(credentials)
            credentials = apply_credential_sorting(credentials)
            credentials = apply_pagination(credentials)

            render_success({
              credentials: credentials.map { |c| serialize_credential(c) },
              pagination: pagination_data(credentials),
              total_count: credentials.total_count
            })
          else
            # PROVIDERS INDEX
            providers = current_user.account.ai_providers
                                   .includes(:ai_provider_credentials)

            # Admin users can see inactive providers
            providers = providers.active unless current_user.has_permission?("admin.ai.providers.read")

            providers = apply_provider_filters(providers)
            providers = apply_sorting(providers)
            providers = apply_pagination(providers)

            render_success({
              items: providers.map { |p| serialize_provider(p) },
              pagination: pagination_data(providers)
            })

            log_audit_event("ai.providers.read", current_user.account)
          end
        end


        # POST /api/v1/ai/providers/:provider_id/credentials/:credential_id/test
        def credential_test
          test_service = AiProviderTestService.new(@credential)
          # Use test_with_details_simple for flat response format expected by controller
          test_result = test_service.test_with_details_simple

          provider = @credential.ai_provider

          # Update credential and provider status
          if test_result[:success]
            @credential.record_success!
            # Also update provider's health metrics so it's marked as healthy
            provider.update_health_metrics(true, test_result[:response_time_ms])
          else
            @credential.record_failure!(test_result[:error])
            # Update provider's health metrics with failure
            provider.update_health_metrics(false, test_result[:response_time_ms], test_result[:error])
          end

          render_success(test_result)

          log_audit_event("ai.providers.credential.test", @credential,
            success: test_result[:success]
          )
        end

        # POST /api/v1/ai/providers/:provider_id/credentials/:credential_id/make_default
        def credential_make_default
          # Unset other default credentials for this provider
          current_user.account.ai_provider_credentials
                     .where(ai_provider: @credential.ai_provider, is_default: true)
                     .where.not(id: @credential.id)
                     .update_all(is_default: false)

          # Set this credential as default
          @credential.update!(is_default: true)

          render_success({
            credential: serialize_credential(@credential),
            message: "Credential set as default"
          })

          log_audit_event("ai.providers.credential.make_default", @credential)
        end

        # POST /api/v1/ai/providers/:provider_id/credentials/:credential_id/rotate
        def credential_rotate
          # Credential rotation would typically involve:
          # 1. Generating new credentials with the provider's API
          # 2. Updating the stored credentials
          # 3. Marking the old credentials as rotated
          # This is a placeholder for the actual rotation logic

          render_success({
            credential: serialize_credential(@credential),
            message: "Credential rotation initiated"
          })

          log_audit_event("ai.providers.credential.rotate", @credential)
        end

        private

        # =============================================================================
        # RESOURCE LOADING
        # =============================================================================

        def set_provider
          @provider = current_user.account.ai_providers.find(params[:id] || params[:provider_id])
        rescue ActiveRecord::RecordNotFound
          render_error("Provider not found", status: :not_found)
        end

        def set_credential
          # Use :id for nested resource (standard Rails convention)
          credential_id = params[:id]

          if current_worker
            # Worker can access any credential
            @credential = AiProviderCredential.find_by!(id: credential_id)
          else
            # User context - scope to account
            @credential = current_user.account.ai_provider_credentials
                                     .includes(:ai_provider)
                                     .find_by!(id: credential_id)
          end
        rescue ActiveRecord::RecordNotFound
          render_error("Credential not found", status: :not_found)
        end

        # =============================================================================
        # AUTHORIZATION
        # =============================================================================

        def validate_permissions
          # Skip for workers
          return if current_worker

          # Determine if this is a credential action based on params
          is_credential_action = params[:provider_id].present?

          case action_name
          when "index"
            if is_credential_action
              require_permission("ai.providers.read")
            else
              require_permission("ai.providers.read")
            end
          when "show"
            if is_credential_action
              require_permission("ai.providers.read")
            else
              require_permission("ai.providers.read")
            end
          when "available", "statistics", "test_all"
            require_permission("ai.providers.read")
          when "setup_defaults"
            require_permission("ai.providers.create")
          when "create"
            if is_credential_action
              require_permission("ai.credentials.create")
            else
              require_permission("ai.providers.create")
            end
          when "update"
            if is_credential_action
              require_permission("ai.credentials.update")
            else
              require_permission("ai.providers.update")
            end
          when "sync_models"
            require_permission("ai.providers.update")
          when "credential_make_default", "credential_rotate"
            require_permission("ai.credentials.update")
          when "destroy"
            if is_credential_action
              require_permission("ai.credentials.delete")
            else
              require_permission("ai.providers.delete")
            end
          when "test_connection", "models", "usage_summary", "check_availability"
            require_permission("ai.providers.read")
          when "credential_test"
            require_permission("ai.credentials.read")
          end
        end

        # =============================================================================
        # PARAMETER HANDLING
        # =============================================================================

        def provider_params
          params.require(:provider).permit(
            :name, :provider_type, :api_base_url, :is_active,
            :priority_order, :description, :api_endpoint, :documentation_url,
            :status_url, :requires_auth, :supports_streaming, :supports_functions,
            :supports_vision, :supports_code_execution, :slug,
            capabilities: [],
            supported_models: [ :name, :id, :context_length, :max_output_tokens, :cost_per_token,
                              { cost_per_1k_tokens: [ :input, :output ] }, :capabilities, :features,
                              :default_parameters ],
            default_parameters: {},
            rate_limits: {},
            pricing_info: {},
            configuration_schema: {},
            metadata: {}
          )
        end

        def credential_params
          params.require(:credential).permit(
            :name, :is_active, :is_default, :expires_at,
            credentials: {}
          )
        end

        # =============================================================================
        # FILTERING & SORTING
        # =============================================================================

        def apply_provider_filters(providers)
          providers = providers.where(provider_type: params[:provider_type]) if params[:provider_type].present?
          providers = providers.supporting_capability(params[:capability]) if params[:capability].present?
          providers = providers.where("name ILIKE ?", "%#{params[:search]}%") if params[:search].present?
          providers
        end

        def apply_credential_filters(credentials)
          credentials = credentials.where(ai_provider_id: params[:provider_id]) if params[:provider_id].present?
          credentials = credentials.where(is_active: params[:active]) if params[:active].present?
          credentials = credentials.where(is_default: true) if params[:default_only] == "true"
          credentials = credentials.where("name ILIKE ?", "%#{params[:search]}%") if params[:search].present?
          credentials
        end

        def apply_sorting(collection)
          sort = params[:sort] || "priority"

          case sort
          when "name"
            collection.order(:name)
          when "priority"
            collection.order(:priority_order, :name)
          when "created_at"
            collection.order(created_at: :desc)
          else
            collection.ordered_by_priority rescue collection.order(:name)
          end
        end

        def apply_credential_sorting(credentials)
          sort = params[:sort] || "name"

          case sort
          when "name"
            credentials.order(:name)
          when "provider"
            credentials.joins(:ai_provider).order("ai_providers.name")
          when "last_used"
            credentials.order(last_used_at: :desc)
          when "created_at"
            credentials.order(created_at: :desc)
          else
            credentials.order(:name)
          end
        end

        def apply_pagination(collection)
          page = params[:page]&.to_i || 1
          per_page = [ params[:per_page]&.to_i || 20, 100 ].min

          collection.page(page).per(per_page)
        end

        def pagination_data(collection)
          {
            current_page: collection.current_page,
            per_page: collection.limit_value,
            total_pages: collection.total_pages,
            total_count: collection.total_count
          }
        end

        # =============================================================================
        # SERIALIZATION
        # =============================================================================

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
              credentials_count: provider.ai_provider_credentials.count,
              supported_models_count: provider.supported_models&.length || 0
            },
            # Add root-level counts for frontend compatibility
            credential_count: provider.ai_provider_credentials.count,
            model_count: provider.supported_models&.length || 0
          }
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
            credentials: provider.ai_provider_credentials.map { |c| serialize_credential(c) }
          )
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
              id: credential.ai_provider.id,
              name: credential.ai_provider.name,
              provider_type: credential.ai_provider.provider_type
            },
            stats: {
              success_count: credential.success_count,
              failure_count: credential.failure_count,
              success_rate: calculate_credential_success_rate(credential)
            }
          }
        end

        def serialize_credential_detail(credential)
          result = serialize_credential(credential).merge(
            credential_keys: credential.credentials&.keys || []
          )

          # Include decrypted credentials only for authorized users
          if current_user&.has_permission?("ai.credentials.decrypt")
            result[:credentials] = credential.credentials
          end

          result
        end

        # =============================================================================
        # HELPERS
        # =============================================================================

        def find_credential_for_test(credential_id)
          credential = current_user.account.ai_provider_credentials
                                  .includes(:ai_provider)
                                  .find_by(id: credential_id)

          unless credential
            render_error("Credential not found", status: :not_found)
            return nil
          end

          unless credential.ai_provider == @provider
            render_error("Credential does not belong to this provider", status: :bad_request)
            return nil
          end

          credential
        end

        def find_default_credential
          credential = current_user.account.ai_provider_credentials
                                  .includes(:ai_provider)
                                  .find_by(ai_provider: @provider, is_default: true, is_active: true)

          unless credential
            render_error("No active credentials found for this provider", status: :not_found)
            return nil
          end

          credential
        end

        def calculate_credential_success_rate(credential)
          total = credential.success_count + credential.failure_count
          return 0 if total.zero?

          ((credential.success_count.to_f / total) * 100).round(2)
        end

        def calculate_total_api_calls
          # Calculate across all agent executions and workflow runs
          agent_calls = AiAgentExecution.joins(ai_agent: :ai_provider)
                                       .where(ai_providers: { account_id: current_user.account_id })
                                       .count

          workflow_calls = AiWorkflowNodeExecution.joins(ai_workflow_run: { ai_workflow: :account })
                                                  .where(accounts: { id: current_user.account_id })
                                                  .where(node_type: "ai_agent")
                                                  .count

          agent_calls + workflow_calls
        end

        def calculate_total_cost
          agent_cost = AiAgentExecution.joins(ai_agent: :ai_provider)
                                      .where(ai_providers: { account_id: current_user.account_id })
                                      .sum(:cost_usd)

          workflow_cost = AiWorkflowNodeExecution.joins(ai_workflow_run: { ai_workflow: :account })
                                                 .where(accounts: { id: current_user.account_id })
                                                 .sum(:cost)

          (agent_cost + workflow_cost).round(2)
        end

        def calculate_provider_health_status(provider)
          # If provider is inactive, it's degraded
          return "degraded" unless provider.is_active

          # Check credentials health
          active_credentials = provider.ai_provider_credentials.where(is_active: true)

          # No credentials - degraded
          return "degraded" if active_credentials.empty?

          # Check last test results
          tested_credentials = active_credentials.where.not(last_test_at: nil)

          # No test results yet - assume healthy if has active credentials
          return "healthy" if tested_credentials.empty?

          # Calculate success rate from tested credentials
          successful = tested_credentials.where(last_test_status: "success").count
          total = tested_credentials.count
          success_rate = (successful.to_f / total * 100).round

          # Determine health based on success rate
          if success_rate >= 80
            "healthy"
          elsif success_rate >= 50
            "degraded"
          else
            "critical"
          end
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
                api_base_url: nil, # User must configure their Azure endpoint
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

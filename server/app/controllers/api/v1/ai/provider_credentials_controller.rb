# frozen_string_literal: true

module Api
  module V1
    module Ai
      class ProviderCredentialsController < ApplicationController
        include AuditLogging
        include ::Ai::CredentialSerialization

        before_action :set_provider
        before_action :set_credential, only: [
          :show, :update, :destroy,
          :test, :make_default, :rotate, :decrypt
        ]
        before_action :validate_permissions

        # GET /api/v1/ai/providers/:provider_id/credentials
        def index
          credentials = if current_worker
                          # Worker can access any credentials for background processing
                          ::Ai::ProviderCredential.includes(:provider)
          else
                          @provider.provider_credentials
          end

          credentials = apply_credential_filters(credentials)
          credentials = apply_credential_sorting(credentials)
          credentials = apply_pagination(credentials)

          render_success({
            credentials: credentials.map { |c| serialize_credential(c) },
            pagination: pagination_data(credentials),
            total_count: credentials.total_count
          })
        end

        # GET /api/v1/ai/providers/:provider_id/credentials/:id
        def show
          render_success({
            credential: serialize_credential_detail(@credential)
          })
        end

        # POST /api/v1/ai/providers/:provider_id/credentials
        def create
          # Extract credentials from params and convert to Hash with string keys
          credentials_data = credential_params[:credentials]&.to_h&.deep_stringify_keys || {}

          # Build options hash from permitted params
          options = {
            name: credential_params[:name],
            is_active: credential_params[:is_active],
            is_default: credential_params[:is_default],
            expires_at: credential_params[:expires_at]
          }.compact

          @credential = ::Ai::ProviderManagementService.create_provider_credential(
            @provider,
            current_user.account,
            credentials_data,
            **options
          )

          render_success({
            credential: serialize_credential_detail(@credential)
          }, status: :created)

          log_audit_event("ai.providers.credential.create", @credential,
            provider_name: @provider.name
          )
        rescue ActiveRecord::RecordNotFound
          render_error("Provider not found", status: :not_found)
        rescue ::Ai::ProviderManagementService::ValidationError => e
          render_error("Validation failed: #{e.message}", status: :unprocessable_content)
        rescue ::Ai::ProviderManagementService::CredentialError => e
          render_error("Credential error: #{e.message}", status: :unprocessable_content)
        end

        # PATCH /api/v1/ai/providers/:provider_id/credentials/:id
        def update
          update_params = credential_params.except(:credentials)

          # If credentials are being updated, validate and encrypt them
          if credential_params[:credentials].present?
            begin
              credentials_hash = credential_params[:credentials].to_h.deep_stringify_keys
              ::Ai::ProviderManagementService.validate_ai_provider_credentials(
                @credential.provider,
                credentials_hash
              )

              @credential.credentials = credentials_hash
            rescue ::Ai::ProviderManagementService::ValidationError => e
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
        end

        # DELETE /api/v1/ai/providers/:provider_id/credentials/:id
        def destroy
          credential_name = @credential.name
          provider_name = @credential.provider.name

          if @credential.destroy
            render_success({ message: "Credential deleted successfully" })

            log_audit_event("ai.providers.credential.delete", current_user.account,
              credential_name: credential_name,
              provider_name: provider_name
            )
          else
            if @credential.errors.any?
              render_validation_error(@credential.errors)
            else
              render_error("Failed to delete credential", status: :unprocessable_content)
            end
          end
        end

        # POST /api/v1/ai/providers/:provider_id/credentials/:id/test
        def test
          test_service = ::Ai::ProviderManagementService.new(@credential)
          test_result = test_service.test_with_details_simple

          provider = @credential.provider

          if test_result[:success]
            @credential.record_success!
            provider.update_health_metrics(true, test_result[:response_time_ms])
          else
            @credential.record_failure!(test_result[:error])
            provider.update_health_metrics(false, test_result[:response_time_ms], test_result[:error])
          end

          render_success(test_result)

          log_audit_event("ai.providers.credential.test", @credential,
            success: test_result[:success]
          )
        end

        # POST /api/v1/ai/providers/:provider_id/credentials/:id/make_default
        def make_default
          current_user.account.ai_provider_credentials
                     .where(provider: @credential.provider, is_default: true)
                     .where.not(id: @credential.id)
                     .update_all(is_default: false)

          @credential.update!(is_default: true)

          render_success({
            credential: serialize_credential(@credential),
            message: "Credential set as default"
          })

          log_audit_event("ai.providers.credential.make_default", @credential)
        end

        # POST /api/v1/ai/credentials/:id/decrypt
        # Worker-only endpoint — returns decrypted credential data
        def decrypt
          unless current_worker
            return render_error("Decrypt is only available to workers", status: :forbidden)
          end

          decrypted = @credential.credentials

          render_success({
            credentials: decrypted
          })
        end

        # POST /api/v1/ai/providers/:provider_id/credentials/:id/rotate
        def rotate
          render_success({
            credential: serialize_credential(@credential),
            message: "Credential rotation initiated"
          })

          log_audit_event("ai.providers.credential.rotate", @credential)
        end

        private

        def set_provider
          return if current_worker

          @provider = current_user.account.ai_providers.find(params[:provider_id])
        rescue ActiveRecord::RecordNotFound
          render_error("Provider not found", status: :not_found)
        end

        def set_credential
          credential_id = params[:id]

          if current_worker
            @credential = ::Ai::ProviderCredential.find_by!(id: credential_id)
          else
            @credential = current_user.account.ai_provider_credentials
                                     .includes(:provider)
                                     .find_by!(id: credential_id)
          end
        rescue ActiveRecord::RecordNotFound
          render_error("Credential not found", status: :not_found)
        end

        def validate_permissions
          return if current_worker

          case action_name
          when "index", "show"
            require_permission("ai.providers.read")
          when "create"
            require_permission("ai.credentials.create")
          when "update", "make_default", "rotate"
            require_permission("ai.credentials.update")
          when "destroy"
            require_permission("ai.credentials.delete")
          when "test", "decrypt"
            require_permission("ai.credentials.read")
          end
        end

        def credential_params
          params.require(:credential).permit(
            :name, :is_active, :is_default, :expires_at,
            credentials: {}
          )
        end

        def apply_credential_filters(credentials)
          credentials = credentials.where(ai_provider_id: params[:provider_id]) if params[:provider_id].present?
          credentials = credentials.where(is_active: params[:active]) if params[:active].present?
          credentials = credentials.where(is_default: true) if params[:default_only] == "true"
          credentials = credentials.where("name ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(params[:search])}%") if params[:search].present?
          credentials
        end

        def apply_credential_sorting(credentials)
          sort = params[:sort] || "name"

          case sort
          when "name"
            credentials.order(:name)
          when "provider"
            credentials.joins(:provider).order("ai_providers.name")
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
      end
    end
  end
end

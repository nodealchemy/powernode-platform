# frozen_string_literal: true

module Api
  module V1
    module Integrations
      class CredentialsController < ApplicationController
        before_action :authenticate_request
        before_action :set_credential, only: [:show, :update, :destroy, :rotate]

        # GET /api/v1/integrations/credentials
        def index
          authorize_action!("integrations.credentials.read")

          credentials = ::Devops::IntegrationCredential
            .where(account: current_account)
            .order(created_at: :desc)
            .page(pagination_params[:page])
            .per(pagination_params[:per_page])

          render_success({
            credentials: credentials.map(&:credential_summary),
            pagination: pagination_meta(credentials)
          })
        end

        # GET /api/v1/integrations/credentials/:id
        def show
          authorize_action!("integrations.credentials.read")

          render_success({ credential: @credential.credential_details })
        end

        # POST /api/v1/integrations/credentials
        def create
          authorize_action!("integrations.credentials.create")

          credential = ::Devops::RegistryService.create_credential(
            account: current_account,
            attributes: credential_params,
            created_by: current_user
          )

          render_success({ credential: credential.credential_summary }, status: :created)
        rescue ::Devops::RegistryService::ValidationError => e
          render_error(e.message, status: :unprocessable_content)
        end

        # PATCH /api/v1/integrations/credentials/:id
        def update
          authorize_action!("integrations.credentials.update")

          credential = ::Devops::RegistryService.update_credential(
            account: current_account,
            credential_id: @credential.id,
            attributes: credential_params
          )

          render_success({ credential: credential.credential_summary })
        rescue ::Devops::RegistryService::ValidationError => e
          render_error(e.message, status: :unprocessable_content)
        end

        # DELETE /api/v1/integrations/credentials/:id
        def destroy
          authorize_action!("integrations.credentials.delete")

          ::Devops::RegistryService.delete_credential(
            account: current_account,
            credential_id: @credential.id
          )

          render_success(message: "Credential deleted")
        rescue ::Devops::RegistryService::ValidationError => e
          render_error(e.message, status: :unprocessable_content)
        end

        # POST /api/v1/integrations/credentials/:id/rotate
        def rotate
          authorize_action!("integrations.credentials.update")

          ::Devops::CredentialEncryptionService.rotate_key(@credential)

          @credential.touch(:rotated_at)

          render_success({ credential: @credential.credential_summary }, message: "Credential rotated successfully")
        rescue ::Devops::CredentialEncryptionService::EncryptionError => e
          render_error("Failed to rotate credential: #{e.message}", status: :unprocessable_content)
        end

        # POST /api/v1/integrations/credentials/:id/verify
        def verify
          authorize_action!("integrations.credentials.read")

          valid = ::Devops::CredentialEncryptionService.valid?(@credential)

          render_success({ valid: valid })
        end

        private

        def set_credential
          @credential = ::Devops::IntegrationCredential.find_by(id: params[:id], account: current_account)

          render_not_found("Credential") unless @credential
        end

        def credential_params
          params.require(:credential).permit(
            :name, :credential_type,
            scopes: [],
            metadata: {},
            credentials: {}
          )
        end

        def authorize_action!(permission)
          unless current_user.has_permission?(permission)
            render_forbidden("You don't have permission to perform this action")
          end
        end

        def pagination_meta(collection)
          {
            current_page: collection.current_page,
            total_pages: collection.total_pages,
            total_count: collection.total_count,
            per_page: collection.limit_value
          }
        end
      end
    end
  end
end

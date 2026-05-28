# frozen_string_literal: true

module Api
  module V1
    module Internal
      module Ai
        # Worker-facing decrypted AI provider credentials over mTLS. The worker's
        # BackendApiClient is mTLS-only (no JWT), so credential resolution must run
        # through an InternalBaseController route — mirrors
        # Api::V1::Internal::Git::CredentialsController#decrypted. The user-facing
        # Api::V1::Ai::ProviderCredentialsController#decrypt stays JWT-gated for the
        # dashboard; this is its internal/mTLS counterpart.
        class CredentialsController < InternalBaseController
          before_action :set_credential

          # POST /api/v1/internal/ai/credentials/:id/decrypt
          # Authenticated as a worker by InternalBaseController#authenticate_worker_via_mtls!.
          def decrypt
            render_success({
              credentials: @credential.credentials
            })
          rescue StandardError => e
            # ID + error class only — never log decrypted material.
            Rails.logger.error "Failed to decrypt AI credential #{@credential&.id}: #{e.class.name}"
            render_error("Failed to decrypt credentials", status: :internal_server_error)
          end

          private

          def set_credential
            @credential = ::Ai::ProviderCredential.find_by!(id: params[:id])
          rescue ActiveRecord::RecordNotFound
            render_error("Credential not found", status: :not_found)
          end
        end
      end
    end
  end
end

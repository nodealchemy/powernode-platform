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
          include Api::V1::Internal::WorkerTenancy

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
            @credential = credential_scope.find_by!(id: params[:id])
          rescue ActiveRecord::RecordNotFound
            render_error("Credential not found", status: :not_found)
          end

          # Tenancy anchor for the worker-facing credential lookup.
          #
          # This action renders the DECRYPTED credential hash, so an unscoped
          # `find_by!(id:)` disclosed every account's plaintext provider API keys
          # to any principal that authenticated on this seam, by enumerable id.
          #
          # This is the SAME anchor Api::V1::Ai::ProviderCredentialsController
          # adopted in e9352723d, deliberately reused rather than re-derived: the
          # account of the authenticated Worker PRINCIPAL itself. A worker has no
          # `current_user`, and no caller-supplied parameter can widen it, so it
          # holds even when the forwarded-CN identity is FORGED — asserting a
          # worker CN gets you that worker's account and nothing beyond it.
          #
          # There is deliberately NO exemption for the `is_system` worker. The
          # principal on this seam in production is an ACCOUNT-BOUND worker:
          # `workers.node_instance_id` is written only by
          # extensions/system/server/lib/tasks/worker_provision.rake
          # (`provision` / `bootstrap_self_host` / `link_existing`), which binds
          # each Worker to an operator-supplied account and leaves `is_system` at
          # its column default of false. `EnsureSystemWorker#bind_dev_sentinel`
          # is the only producer that touches the system worker, and it binds
          # the sentinel ONLY in development. Outside development the sentinel is
          # actively REVOKED — by that method, and at boot by
          # config/initializers/worker_dev_sentinel_revocation.rb, which is what
          # reaches a database bootstrapped in development and later promoted
          # (IMP-b1c144ca9aa1). So the premise is enforced at boot rather than
          # merely observed. A system-worker exemption would still be inert in
          # production while, before that first boot,
          # handing unrestricted cross-account reach to anyone presenting the
          # PUBLISHED constant `EnsureSystemWorker::DEV_SENTINEL_NODE_ID` — the
          # exact hazard Api::V1::EmailSettingsController already guards against.
          #
          # Scoping by the `account_id` COLUMN rather than dereferencing
          # `current_worker.account` fails CLOSED: `workers.account_id` is
          # nullable at the DB level, and `where(account_id: nil)` matches no rows
          # instead of raising, while `ai_provider_credentials.account_id` is
          # `null: false` so no row is ever caught by a NULL scope. A
          # half-provisioned principal — or a nil one — is denied, not granted.
          #
          # The strict-PEM identity gate is deliberately NOT added here: it is
          # blocked on offer 01a028ab-f39b, because if core's no-PEM
          # `pass-tls-client-cert` wins the Traefik merge, `require_pem` would
          # reject the GENUINE worker and break AI chat. Unlike email settings,
          # which can mask four values and still return usable config, withholding
          # the API key here has no soft-failure mode. Tenancy scoping is safe
          # now; gating identity is not.
          def credential_scope
            # `worker_account_id` is the single, shared definition of this
            # anchor (Api::V1::Internal::WorkerTenancy) — a second inline copy of
            # `current_worker&.account_id` is exactly how this class regenerated
            # across the namespace.
            ::Ai::ProviderCredential.where(account_id: worker_account_id)
          end
        end
      end
    end
  end
end

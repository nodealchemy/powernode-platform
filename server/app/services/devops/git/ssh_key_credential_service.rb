# frozen_string_literal: true

module Devops
  module Git
    # SSH-key credentials for a git provider. The private key is held only by
    # the credential's encrypted store; this service never returns, logs or
    # audits it. Every key operation writes its audit row INSIDE the
    # transaction that stores or removes the key, so a failed audit write rolls
    # the operation back (fail closed) — a key is never stored or dropped
    # without a record.
    class SshKeyCredentialService
      # Raised when the audit row cannot be written; the operation was rolled back.
      class AuditUnavailable < StandardError; end

      CREATE_ACTION = "git.credentials.ssh_key.create"
      REPLACE_ACTION = "git.credentials.ssh_key.replace"
      DELETE_ACTION = "git.credentials.ssh_key.delete"

      class << self
        # @return [Devops::GitProviderCredential] persisted, or carrying errors
        def create!(provider:, account:, user:, params:, name:, request_meta: {})
          credential = account.git_provider_credentials.build(
            git_provider_id: provider.id, user: user, name: name, auth_type: "ssh_key",
            is_active: params[:is_active] != false, is_default: false, expires_at: params[:expires_at]
          )
          credential.credentials = params[:credentials].to_h.with_indifferent_access.slice(:private_key, :public_key, :passphrase).to_h

          ::Devops::GitProviderCredential.transaction(requires_new: true) do
            unless credential.save
              raise ActiveRecord::Rollback
            end

            audit!(CREATE_ACTION, credential, user, account, request_meta)
          end
          credential
        end

        def replace!(credential:, credentials:, user:, request_meta: {})
          ::Devops::GitProviderCredential.transaction(requires_new: true) do
            credential.credentials = credentials.to_h.with_indifferent_access.slice(:private_key, :public_key, :passphrase).to_h
            raise ActiveRecord::Rollback unless credential.save

            audit!(REPLACE_ACTION, credential, user, credential.account, request_meta)
          end
          credential
        end

        # @return [Boolean] whether the credential was removed
        def destroy!(credential:, user:, request_meta: {})
          removed = false
          ::Devops::GitProviderCredential.transaction(requires_new: true) do
            audit!(DELETE_ACTION, credential, user, credential.account, request_meta)
            removed = credential.destroy.present?
            raise ActiveRecord::Rollback unless removed
          end
          removed
        end

        private

        # Fingerprint and ids only — never key material.
        def audit!(action, credential, user, account, request_meta)
          ::AuditLog.log_action(
            action: action, resource: credential, user: user, account: account,
            source: "api", ip_address: request_meta[:ip_address], user_agent: request_meta[:user_agent],
            metadata: { git_provider_id: credential.git_provider_id, fingerprint: credential.ssh_fingerprint }
          )
        rescue StandardError => e
          Rails.logger.error("[Devops::Git::SshKeyCredentialService] audit write failed for #{action}: #{e.class}")
          raise AuditUnavailable, "Key operation could not be audited; nothing was changed"
        end
      end
    end
  end
end

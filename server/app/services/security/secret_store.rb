# frozen_string_literal: true

module Security
  # One seam over two interchangeable secret backends — Vault and DB-encrypted —
  # chosen by a global toggle. Callers read/write secrets through this and never
  # care which backend is active.
  #
  #   Security::SecretStore.write(account:, scope:, key:, value:)
  #   Security::SecretStore.read(account:, scope:, key:)
  #   Security::SecretStore.delete(account:, scope:, key:)
  #   Security::SecretStore.backend  # :vault | :database
  #
  # `scope` namespaces a secret within an account (e.g. "email"); `key` is the
  # logical name (e.g. "smtp_password"). Selection is the global `secret_backend`
  # setting, default :database (no Vault required).
  #
  # FAIL-CLOSED: when the toggle selects Vault but Vault is unreachable, secret
  # operations RAISE (BackendUnavailable) rather than silently downgrading to the
  # DB backend — a silent downgrade of secret storage would be a security surprise.
  module SecretStore
    SETTING_KEY = "secret_backend" # "vault" | "database"

    class BackendUnavailable < StandardError; end

    class << self
      # @return [Symbol] :vault | :database
      def backend
        AdminSetting.get(SETTING_KEY).to_s == "vault" ? :vault : :database
      end

      def write(account:, scope:, key:, value:)
        active_backend.write(account: account, scope: scope, key: key, value: value)
      end

      # `cache: false` reads past any backend-side cache (VaultClient keeps a
      # 5-minute per-process one); the database backend has none.
      def read(account:, scope:, key:, cache: true)
        active_backend.read(account: account, scope: scope, key: key, cache: cache)
      end

      def delete(account:, scope:, key:)
        active_backend.delete(account: account, scope: scope, key: key)
      end

      # Account teardown: with the vault backend an account's entries exist ONLY
      # in Vault KV (no DB row), so the dependents cannot reach them. Deletes
      # every entry under the account's path and returns how many. A no-op (0)
      # for the database backend, whose rows (Security::Secret) go with the
      # account. Raises BackendUnavailable if Vault is selected but unreachable.
      def purge_account(account_id:)
        raise ArgumentError, "purge_account needs an account_id" if account_id.blank?
        return 0 unless backend == :vault

        active_backend.purge_account(account_id)
      end

      private

      def active_backend
        if backend == :vault
          raise BackendUnavailable, "Vault secret backend selected but unreachable" unless VaultBackend.reachable?

          VaultBackend
        else
          DatabaseBackend
        end
      end
    end

    # DB-encrypted backend (default; works without Vault). Encryption at rest is
    # Rails `encrypts` on Security::Secret.
    module DatabaseBackend
      class << self
        def write(account:, scope:, key:, value:)
          secret = Security::Secret.find_or_initialize_by(account: account, scope: scope.to_s, key: key.to_s)
          secret.value = value
          secret.save!
          value
        end

        def read(account:, scope:, key:, cache: true) # rubocop:disable Lint/UnusedMethodArgument
          Security::Secret.find_by(account: account, scope: scope.to_s, key: key.to_s)&.value
        end

        def delete(account:, scope:, key:)
          Security::Secret.where(account: account, scope: scope.to_s, key: key.to_s).delete_all
          nil
        end
      end
    end

    # Vault backend — wraps the existing VaultClient KV store.
    module VaultBackend
      class << self
        def write(account:, scope:, key:, value:)
          Security::VaultClient.instance.write_secret(path_for(account, scope, key), { "value" => value })
          value
        end

        def read(account:, scope:, key:, cache: true)
          Security::VaultClient.instance.read_secret(path_for(account, scope, key), key: "value", cache: cache)
        end

        def delete(account:, scope:, key:)
          Security::VaultClient.instance.delete_secret(path_for(account, scope, key))
          nil
        end

        # Health probe used by the fail-closed gate. Any error ⇒ unreachable.
        def reachable?
          Security::VaultClient.instance.healthy?
        rescue StandardError
          false
        end

        def path_for(account, scope, key)
          "#{account_prefix(account&.id)}/#{scope}/#{key}"
        end

        def account_prefix(account_id)
          "powernode/secret-store/#{account_id}"
        end

        # The secret-store path has no `<mount>/data/` segment, so it is only
        # coherent with a KV v1 mount (see vault-test-instance.md); on KV v1 the
        # DELETE below is already a hard delete and LIST works on the path as is.
        # Walks the account's KV tree (folders are listed with a trailing "/")
        # and deletes each leaf. Returns the number of entries deleted.
        def purge_account(account_id)
          purge_tree(account_prefix(account_id))
        end

        def purge_tree(path)
          client = Security::VaultClient.instance
          client.list_secrets(path).sum do |entry|
            child = "#{path}/#{entry.to_s.chomp('/')}"
            if entry.to_s.end_with?("/")
              purge_tree(child)
            else
              client.delete_secret(child)
              1
            end
          end
        end
      end
    end
  end
end

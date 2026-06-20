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

      def read(account:, scope:, key:)
        active_backend.read(account: account, scope: scope, key: key)
      end

      def delete(account:, scope:, key:)
        active_backend.delete(account: account, scope: scope, key: key)
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

        def read(account:, scope:, key:)
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

        def read(account:, scope:, key:)
          Security::VaultClient.instance.read_secret(path_for(account, scope, key), key: "value")
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
          "powernode/secret-store/#{account&.id}/#{scope}/#{key}"
        end
      end
    end
  end
end

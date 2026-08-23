# frozen_string_literal: true

module Setup
  # Creates the very first administrator for a fresh install.
  #
  # Single source of truth shared by the headless CLI (`rake powernode:setup`)
  # and the web bootstrap endpoint (POST /api/v1/setup/admin) — "two drivers,
  # one definition of the first admin." Web-specific concerns (the bootstrap-token
  # gate, JWT issuance, and the `powernode.user.registered` billing notification)
  # live in the caller, not here.
  class FirstAdminService
    # Raised when an admin already exists — the bootstrap path is one-shot.
    class AlreadyBootstrapped < StandardError; end

    Result = Struct.new(:user, :account, keyword_init: true)

    # @param email [String]
    # @param password [String]
    # @param name [String, nil] admin display name
    # @param account_name [String, nil] account name (defaults to the admin name)
    # @return [Result]
    # @raise [AlreadyBootstrapped] if any user already exists
    # @raise [ActiveRecord::RecordInvalid] on invalid account/user attributes
    def self.call(email:, password:, name: nil, account_name: nil)
      raise AlreadyBootstrapped, "An administrator already exists" if User.exists?

      ensure_permissions_and_roles!

      result = ActiveRecord::Base.transaction do
        account = Account.first || Account.create!(
          name: account_name.presence || name.presence || "Powernode",
          subdomain: unique_subdomain
        )

        # No SMTP is configured at first-run, so the admin is auto-verified.
        user = account.users.create!(
          name: name.presence || "Admin",
          email: email,
          password: password,
          email_verified_at: Time.current
        )

        assign_super_admin!(user)

        Result.new(user: user, account: account)
      end

      # The system Worker authenticates worker→backend API calls; ensure it exists
      # on first-account bootstrap (core/prod), not just in seeded installs.
      ::Workers::EnsureSystemWorker.call(account: result.account)

      result
    end

    # Idempotently ensure the core permission/role catalog exists. At a genuinely
    # fresh install (before `rails db:seed`) the super_admin role may be absent,
    # which would otherwise leave the first admin without `system.admin`.
    # `sync_from_config!` is idempotent and config-driven — distinct from the
    # optional example-data seeding offered later in the wizard.
    def self.ensure_permissions_and_roles!
      return if Role.exists?(name: "super_admin")

      # Permissions are code-defined; only roles + their grants are seeded.
      Role.sync_from_config!
    end

    # The `assign_default_role` User callback only grants `owner` to the first
    # user, which lacks `system.admin` — so super_admin must be assigned explicitly.
    def self.assign_super_admin!(user)
      super_admin = Role.find_by(name: "super_admin")
      return unless super_admin

      user.roles << super_admin unless user.roles.include?(super_admin)
    end

    # PUBLIC: also used by Accounts::ProvisionService, the non-bootstrap path
    # that creates additional tenant accounts. Subdomain uniqueness is an Account
    # validation, so both creators must resolve it the same way.
    def self.unique_subdomain(base = "admin")
      candidate = base
      counter = 1
      while Account.exists?(subdomain: candidate)
        candidate = "#{base}#{counter}"
        counter += 1
      end
      candidate
    end

    private_class_method :assign_super_admin!
  end
end

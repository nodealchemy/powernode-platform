# frozen_string_literal: true

module Accounts
  # Creates a NEW tenant account together with its initial administrator.
  #
  # WHY THIS EXISTS
  # ---------------
  # Core's only other account-creating path is Setup::FirstAdminService, which is
  # one-shot by construction (`raise AlreadyBootstrapped if User.exists?`). Once a
  # platform is bootstrapped there was no way, anywhere in core, to add a second
  # Account — and the Account is the tenancy boundary between federated hubs, so
  # the open-source platform could not stand up a second tenant at all.
  #
  # WELL-FORMEDNESS
  # ---------------
  # Derived from Setup::FirstAdminService, the one place in core that has ever
  # built an account correctly. A bare `Account.create!` skips all of this and
  # yields a tenant nobody can log into:
  #
  #   1. The role catalog must exist BEFORE the first user is created, or that
  #      user's `assign_default_role` callback finds no `owner` role and the
  #      account's administrator lands with no permissions whatsoever. Reused
  #      directly: Setup::FirstAdminService.ensure_permissions_and_roles!
  #   2. The subdomain must be unique (Account validates uniqueness). Reused
  #      directly: Setup::FirstAdminService.unique_subdomain
  #   3. The account needs at least one user who can actually administer it.
  #      User#assign_default_role grants `owner` to the FIRST user in an account,
  #      which is exactly the tenant-administrator role wanted here — so the user
  #      is created inside the same transaction, with no explicit role, and the
  #      existing callback does the granting.
  #   4. Self-hosted installs are not guaranteed to have SMTP, so the initial
  #      administrator is created pre-verified — the same reasoning and the same
  #      `email_verified_at: Time.current` as the bootstrap path.
  #
  # Per-account infrastructure bootstrap is NOT invoked here and must not be:
  # Account's own `after_create_commit :run_account_bootstrap` already fires for
  # any account however it was created.
  #
  # SEEDED PER-ACCOUNT ROWS (IMP-e8513b30152d)
  # -------------------------------------------
  # Seeds run once, at first boot, so per-account baseline rows the seed
  # creates for the accounts that exist THEN must be created here for a tenant
  # provisioned LATER — through the seed's own seam, so the two paths cannot
  # drift. Today that is the inactive `claude-code` Ai::Provider scope
  # (Ai::ClaudeExport::ProviderScopeSeeder): the row Claude Code runs of
  # platform agents are recorded under, which the report path deliberately
  # cannot mint. This service is chosen over on-demand creation because it is
  # where core provisions a tenant AFTER bootstrap.
  #
  # It is NOT the only account creator, and db:seed does not backstop the
  # others — each covers itself through the same seam:
  #   * Setup::FirstAdminService — the FIRST account. Its own bootstrap calls
  #     the seam. db:seed is not a guarantee there: the wizard's seed step is
  #     Setup::SeedService (the extension :account_seeder seam), which no-ops in
  #     core mode and never loads db/seeds.rb, and only the hub module seeds
  #     after bootstrapping an admin.
  #   * accounts predating the seed on an ESTABLISHED install — db:seed is
  #     first-boot only; `rails db:seed:claude_code_provider_scopes` backfills.
  #   * Api::V1::Auth::RegistrationsController — SaaS-mode only (require_saas_mode),
  #     so an extension concern; it can call the same seam (open question).
  #   * Ai::ProviderManagementService::ProviderSpecs#setup_default_providers does
  #     `Account.find_or_create_by`, but has no production caller — every
  #     reference is in spec/ (verified 2026-09-03 with a grep that includes
  #     `find_or_create_by`, which the original survey pattern missed).
  #
  # DELIBERATELY NOT REUSED
  # -----------------------
  # Workers::EnsureSystemWorker. Setup::FirstAdminService calls it, but it
  # resolves a single GLOBAL system worker (`Worker.where(is_system: true).first`)
  # and REBINDS that worker to whatever account it is handed. Calling it for a
  # second account would move the running platform's worker identity onto the new
  # tenant and break worker->backend API calls platform-wide. The system worker is
  # a platform singleton, not per-account state.
  #
  # DELIBERATELY NOT EMITTED
  # ------------------------
  # The `powernode.user.registered` notification that the public self-serve
  # registration path fires. That event drives trial/subscription setup, which is
  # a billing concern owned by an extension; a tenancy boundary stood up by a
  # platform operator is not a self-serve signup, so a tenant created here has no
  # subscription and `account_data` serializes `subscription: nil`. Stated
  # explicitly because the divergence from the registration path is deliberate.
  #
  # DELIBERATELY NOT GRANTED
  # ------------------------
  # `super_admin`. Setup::FirstAdminService grants it because the first admin IS
  # the platform operator. An account created later is a tenant: its administrator
  # gets the account-scoped `owner` role only, so provisioning a tenant can never
  # mint platform-wide (`system.admin`) authority.
  class ProvisionService
    Result = Struct.new(:account, :administrator, keyword_init: true)

    # Subdomain stem used when the caller does not supply one. Derived from the
    # account name so the generated value is recognisable, and de-duplicated by
    # Setup::FirstAdminService.unique_subdomain.
    FALLBACK_SUBDOMAIN_STEM = "account"

    # Account validates `subdomain` at 3..30 characters and the column is
    # limit: 30, while `name` is validated at 2..100 — so a stem DERIVED from the
    # name overflows at both ends. Clamping here matters more than it looks: an
    # operator who left the subdomain field blank must never be handed a
    # validation error about that field. Counter room is reserved because
    # unique_subdomain appends a de-duplication suffix to whatever it is given.
    MIN_SUBDOMAIN_LENGTH = 3
    MAX_SUBDOMAIN_LENGTH = 30
    SUBDOMAIN_COUNTER_ROOM = 3

    # @param name [String] account name
    # @param admin_email [String]
    # @param admin_password [String]
    # @param admin_name [String, nil] administrator display name
    # @param subdomain [String, nil] explicit subdomain; derived from `name` when blank
    # @return [Result]
    # @raise [ActiveRecord::RecordInvalid] on invalid account/user attributes
    def self.call(name:, admin_email:, admin_password:, admin_name: nil, subdomain: nil)
      new(
        name: name,
        admin_email: admin_email,
        admin_password: admin_password,
        admin_name: admin_name,
        subdomain: subdomain
      ).call
    end

    def initialize(name:, admin_email:, admin_password:, admin_name: nil, subdomain: nil)
      @name = name
      @admin_email = admin_email
      @admin_password = admin_password
      @admin_name = admin_name
      @subdomain = subdomain
    end

    def call
      # Idempotent and config-driven; must run OUTSIDE nothing in particular but
      # BEFORE the user insert, so `assign_default_role` can find `owner`.
      Setup::FirstAdminService.ensure_permissions_and_roles!

      ActiveRecord::Base.transaction do
        account = Account.create!(name: @name, subdomain: resolved_subdomain)

        administrator = account.users.create!(
          name: @admin_name.presence || "Admin",
          email: @admin_email,
          password: @admin_password,
          email_verified_at: Time.current
        )

        ::Ai::ClaudeExport::ProviderScopeSeeder.ensure_for!(account)

        Result.new(account: account, administrator: administrator)
      end
    end

    private

    # An explicit subdomain is honoured as given (and validated by Account, so a
    # collision surfaces as a validation error the caller can correct). A derived
    # one is de-duplicated, because the caller never chose it.
    def resolved_subdomain
      return @subdomain if @subdomain.present?

      Setup::FirstAdminService.unique_subdomain(subdomain_stem)
    end

    def subdomain_stem
      stem = @name.to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
      stem = stem[0, MAX_SUBDOMAIN_LENGTH - SUBDOMAIN_COUNTER_ROOM].to_s.sub(/-+\z/, "")
      return FALLBACK_SUBDOMAIN_STEM if stem.length < MIN_SUBDOMAIN_LENGTH

      stem
    end
  end
end

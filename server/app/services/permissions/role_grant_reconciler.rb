# frozen_string_literal: true

module Permissions
  # Reconciles the CATALOG's global-role grants into the running database,
  # creating only what is ABSENT.
  #
  # WHY THIS EXISTS -----------------------------------------------------
  # Registering a grant (Permissions.register_role_permissions, or a
  # `grant:` in a Permissions.define / register_catalog block) changes CONFIG
  # only. Runtime authorization reads the role_permissions TABLE —
  # User#has_permission? and User#permission_names both query it, and the
  # latter is what feeds `currentUser.permissions` on the frontend.
  #
  # The only AUTOMATIC config->DB path is Role.sync_from_config!, and every one
  # of its non-test callers is first-install-only:
  #
  #   * db/seeds.rb — and db:seed runs on FIRST BOOT ONLY (the hub's
  #     rails-start.sh gates it behind a durable .db-initialized marker; every
  #     later boot runs db:migrate alone).
  #   * Setup::FirstAdminService — `return if Role.exists?(name: "super_admin")`.
  #   * lib/tasks/powernode_setup.rake — bails once any Account exists.
  #
  # config/initializers/ contains no sync. (`rails roles:standardize` is a
  # second, MANUAL path — lib/tasks/standardize_roles.rake:58 — and a worse one:
  # it syncs against `config[:permissions]`, the static ROLES hash, so it drops
  # every extension-registered and catalog-DSL grant. Nothing invokes it.)
  # So on an established deployment
  # every grant added to the catalog since its first boot is INERT: the
  # permission resolves for the role in Permissions.permissions_for_role, the
  # role_permissions row does not exist, and the operator is refused with
  # nothing logged — a silent-403 class that is invisible from the code side.
  # The workaround this replaces was a bespoke migration per changed grant.
  #
  # WHY IT IS NOT "JUST RUN Role.sync_from_config! ON EVERY BOOT" --------
  # Role#sync_permissions! is FULL DESTRUCTIVE RECONCILIATION:
  # `to_remove = current - desired`, then delete_all. Two things make running
  # that automatically a data-loss bug rather than a fix:
  #
  #   1. `desired` is filtered through Permissions.permission_exists?, and
  #      Permissions.all_permissions is core + the extensions LOADED IN THIS
  #      PROCESS. Instances are module-composed, so a boot that happens to
  #      compose without an extension has that extension's permissions absent
  #      from the catalog — and a destructive sync would delete every grant
  #      for them across every global role.
  #   2. It cannot distinguish "an older catalog wrote this" from "something
  #      deliberately granted this". Deletion is silent and unrecoverable.
  #
  # THE RULE: reconcile ABSENCE ONLY. Create a declared global role that does
  # not exist, and add a declared grant that is missing. Never update an
  # existing role's attributes, never delete a grant. Deliberate REVOCATION
  # stays an explicit operator action — Role.sync_from_config!, reached through
  # db:seed or a console — which is the right default for a destructive change
  # to authorization. `rails permissions:role_grant_drift` names what a full
  # sync would remove before anyone runs one.
  #
  # THE PRICE OF THAT RULE, stated plainly: once this runs per boot, the ONLY
  # durable way to revoke a grant the catalog still declares is to change the
  # CATALOG. A `Role#remove_permission` from a console, or a migration that
  # DELETEs the row, is undone at the next boot — the reconcile logs a
  # `created grant:` line and nothing else marks it as a reversal. That is the
  # intended direction (the catalog is the source of truth for global roles,
  # and the API already refuses to edit them — Api::V1::RolesController#update
  # returns 403 when account_id is nil), but a per-permission revocation
  # migration of the kind this class replaces will NOT hold. Change the catalog.
  #
  # WHAT RECONCILING COSTS: IT WIDENS ACCESS ----------------------------
  # Every row this creates grants a permission a role did not previously hold.
  # That is the intent — it converges an established install onto what its own
  # first boot would have written, and the catalog's grants are the platform
  # defaults — but it is a WIDENING, not a silent repair. The rake task and the
  # boot runner both print the count for that reason.
  #
  # SCOPE: GLOBAL roles (account_id nil) only. Account-scoped custom roles are
  # edited through Api::V1::RolesController and own their grants; the catalog
  # has nothing to say about them. Role.sync_from_config! excludes them the
  # same way (it iterates find_or_initialize_by(name:, account_id: nil)).
  class RoleGrantReconciler
    Result = Struct.new(:created, :already_present, :created_grants,
                        :created_roles, :failed, keyword_init: true) do
      def changed? = created.positive? || created_roles.any?
    end

    DriftReport = Struct.new(:missing_grants, :missing_roles, :extra_grants, :present,
                             keyword_init: true) do
      # A declared global role missing from the database is drift in its own
      # right: it contributes no missing GRANTS precisely because it was never
      # examined, so counting only missing_grants would report that install as
      # clean.
      #
      # extra_grants is deliberately NOT part of drifted?. Those are the rows a
      # destructive Role.sync_from_config! WOULD DELETE — reported so an
      # operator can see them before choosing to run one, never treated as a
      # defect this reconciler should act on. Absence-only is the decision.
      def drifted? = missing_grants.any? || missing_roles.any?
    end

    # Creates absent global roles and absent grants. Never updates, never
    # deletes. Safe to run on every boot and safe to run twice.
    def reconcile!
      created_grants = []
      created_roles = []
      already_present = 0
      failed = []

      each_declared_role do |name, config|
        role = Role.find_by(name: name, account_id: nil)

        if role.nil?
          role = create_global_role!(name, config)
          created_roles << name
        end

        desired = desired_grants(name)
        current = role.role_permissions.pluck(:permission_name)
        already_present += (desired & current).size

        (desired - current).each do |permission_name|
          role.role_permissions.find_or_create_by!(permission_name: permission_name)
          created_grants << "#{name}/#{permission_name}"
        rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
          # A concurrent boot winning the race leaves the row PRESENT, which is
          # the outcome this run wanted — nothing to report. Any other cause
          # leaves a grant that is missing forever while every subsequent run
          # reports a clean reconcile, which is the same silent state this class
          # exists to end. Decide by checking the ROW, not the exception class.
          next if role.role_permissions.exists?(permission_name: permission_name)

          failed << { role: name, error: "#{permission_name}: #{e.class}: #{e.message}" }
        end
      rescue StandardError => e
        # One bad role must not stop the rest — this runs at boot.
        failed << { role: name, error: "#{e.class}: #{e.message}" }
      end

      Result.new(
        created: created_grants.size,
        already_present: already_present,
        created_grants: created_grants,
        created_roles: created_roles,
        failed: failed
      )
    end

    # Read-only counterpart: what reconcile! WOULD create. Writes nothing.
    def drift
      missing_grants = []
      missing_roles = []
      extra_grants = []
      present = 0

      each_declared_role do |name, _config|
        role = Role.find_by(name: name, account_id: nil)

        if role.nil?
          missing_roles << name
          # Every declared grant for this role is missing too — say so, rather
          # than letting an absent role read as a role in sync.
          desired_grants(name).each { |p| missing_grants << "#{name}/#{p}" }
          next
        end

        current = role.role_permissions.pluck(:permission_name)
        desired = desired_grants(name)
        present += (desired & current).size
        (desired - current).each { |p| missing_grants << "#{name}/#{p}" }
        (current - desired).each { |p| extra_grants << "#{name}/#{p}" }
      end

      DriftReport.new(missing_grants: missing_grants, missing_roles: missing_roles,
                      extra_grants: extra_grants, present: present)
    end

    private

    # all_roles = core ROLES + every LOADED extension's registered roles. A
    # disabled extension never runs its initializer and so declares nothing —
    # which is exactly why nothing here may delete on the strength of a name's
    # absence from the catalog.
    def each_declared_role
      ::Permissions.all_roles.each { |name, config| yield(name.to_s, config) }
    end

    # Mirrors the filter in Role#sync_permissions!: only catalog-defined names
    # are grantable (RolePermission validates catalog membership, so an unknown
    # name would be rejected anyway).
    def desired_grants(role_name)
      ::Permissions.permissions_for_role(role_name)
                   .uniq
                   .select { |n| ::Permissions.permission_exists?(n) }
    end

    def create_global_role!(name, config)
      Role.create!(
        name: name,
        account_id: nil,
        display_name: config[:display_name],
        description: config[:description],
        role_type: config[:role_type],
        is_system: config[:is_system] || config[:role_type] == "system",
        immutable: config[:immutable] || false
      )
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
      # Usually a concurrent boot created it first. But RecordInvalid also
      # covers a catalog role that simply cannot be saved (blank display_name, a
      # role_type outside the inclusion list, a name failing Role's format
      # validation) — and re-finding it would then raise RecordNotFound,
      # replacing "Display name can't be blank" with a cause that names nothing.
      # For a mechanism whose whole point is that the current failure is
      # invisible, discarding the reason is the wrong trade.
      existing = Role.find_by(name: name, account_id: nil)
      raise e if existing.nil?

      existing
    end
  end
end

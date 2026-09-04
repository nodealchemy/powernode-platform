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
  # config/initializers/ contains no sync. (A second, MANUAL path once existed in
  # a `roles` rake namespace and was a worse one: it passed config[:permissions]
  # to Role#sync_permissions! instead of Permissions.permissions_for_role, so its
  # destructive reconcile dropped every grant contributed by
  # register_role_permissions or a catalog-DSL `grant:`; and its cleanup pass ran
  # Role.where.not(name: ...).destroy! with NO account_id scope, destroying unused
  # account-scoped custom roles. No code path invoked it. Deleted in
  # IMP-6477865679f4; guarded by spec/lib/tasks/roles_standardize_removed_spec.rb.)
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
  # stays an explicit operator action — Role.sync_from_config! — which is the
  # right default for a destructive change to authorization.
  # `rails permissions:role_grant_drift` names what a full sync would remove
  # before anyone runs one.
  #
  # READ THE CAVEAT BEFORE TAKING THAT ROUTE. `db:seed` calls
  # Role.sync_from_config! UNCONDITIONALLY (server/db/seeds.rb), so running it
  # on a module-composed instance triggers exactly the deletion described above:
  # every grant belonging to an extension THIS PROCESS did not load is dropped
  # from every global role, silently and unrecoverably. Sending an operator to
  # `db:seed` to revoke one grant, without saying that, hands them the data-loss
  # bug this class exists to refuse to automate. Revoke by removing the grant
  # from the CATALOG; if a full sync is genuinely wanted, run it from a process
  # that has loaded every extension the deployment composes, and read
  # `permissions:role_grant_drift`'s EXTRA lines first.
  #
  # THE PRICE OF THAT RULE, stated plainly: once this runs per boot, the ONLY
  # durable way to revoke a grant the catalog still declares is to change the
  # CATALOG. A `Role#remove_permission` from a console, or a migration that
  # DELETEs the row, is undone at the next boot. That is the intended direction
  # (the catalog is the source of truth for global roles, and the API already
  # refuses to edit them — Api::V1::RolesController#update returns 403 when
  # account_id is nil), but a per-permission revocation migration of the kind
  # this class replaces will NOT hold. Change the catalog.
  #
  # WHAT MARKS THE REVERSAL (IMP-222dd9bce564) ---------------------------
  # A grant that never landed and a grant an operator revoked five minutes ago
  # are both simply ABSENT, so no log wording alone can separate them. The
  # reconciler therefore keeps a LEDGER of every declared grant it has observed
  # PRESENT (already there, or created by it) — one json SiteSetting row,
  # LEDGER_SETTING, keyed "role/permission" => first-seen timestamp. A creation
  # whose key is already in the ledger is reported in Result#recreated_grants:
  # the row was held by this deployment and removed outside the catalog, and
  # this run has just put it back. The boot runner
  # (extensions/system .../role-grants-reconcile.rb) prints that on its own line
  # and emits a System::FleetEvent for it.
  #
  # #drift carries the same memory from the other direction as
  # DriftReport#previously_held — missing rows this deployment once held. That
  # member is a reporting SURFACE, not a printed signal: as of this change
  # `permissions:role_grant_drift` still prints one undifferentiated `MISSING`
  # line for every absent grant, and `permissions:reconcile_role_grants` one
  # undifferentiated `+ grant` line for every creation. Wiring both printers to
  # these members is a follow-up in lib/tasks/permissions.rake; do not describe
  # the rake output as distinguishing them until it does.
  #
  # Detection changes what is REPORTED, never what is DONE: the re-creation is
  # not suppressed. Suppressing it would give this class hidden state that can
  # silently deny a legitimate catalog grant — trading a visible surprise for
  # an invisible one. Additive and predictable is the contract.
  #
  # The ledger forgets a key only when the CATALOG withdraws that grant: the
  # permission is still known to this process but the role no longer holds it.
  # A key whose permission is unknown here is KEPT, because on a
  # module-composed instance "unknown" usually means "that extension was not
  # composed into this boot", and forgetting there would turn the very next
  # revocation into an unflagged one. A ledger failure never stops the
  # reconcile (Result#ledger_error carries it); it only degrades the signal —
  # and a run that could not READ the ledger does not WRITE one either, because
  # persisting this run's observations over memory it could not read would
  # re-date every key to now and leave the next revocation unflagged.
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
    # SiteSetting key holding the ledger of declared grants this deployment has
    # been observed to hold: { "role/permission" => first-seen ISO-8601 }.
    # State, not configuration — read and written only by this class.
    LEDGER_SETTING = "role_grant_reconciler_ledger"

    # recreated_grants ⊆ created_grants: the keys the ledger already held, i.e.
    # rows removed outside the catalog that this run has restored. Reported,
    # never suppressed. ledger_error is nil unless the ledger could not be read
    # or written; the reconcile itself is unaffected by that.
    Result = Struct.new(:created, :already_present, :created_grants,
                        :created_roles, :failed, :recreated_grants, :ledger_error,
                        keyword_init: true) do
      def changed? = created.positive? || created_roles.any?
    end

    # previously_held ⊆ missing_grants: missing rows the ledger says this
    # deployment once held — a revocation made outside the catalog, which the
    # next boot's reconcile will undo.
    DriftReport = Struct.new(:missing_grants, :missing_roles, :extra_grants,
                             :orphan_grants, :present, :previously_held, keyword_init: true) do
      # A declared global role missing from the database is drift in its own
      # right: it contributes no missing GRANTS precisely because it was never
      # examined, so counting only missing_grants would report that install as
      # clean.
      #
      # extra_grants is deliberately NOT part of drifted?. Those are the rows a
      # destructive Role.sync_from_config! WOULD DELETE — reported so an
      # operator can see them before choosing to run one, never treated as a
      # defect this reconciler should act on. Absence-only is the decision.
      # orphan_grants IS part of drifted?. A grant registered against a role name
      # the catalog does not declare can never be reconciled — each_declared_role
      # iterates all_roles, so the name is skipped with no error, no failed entry
      # and no missing_grants entry. Left out of this predicate, the drift task
      # prints a clean bill over a grant that is permanently inert, which is the
      # same silent state this class exists to end — only now with an affirmative
      # certification on top of it. Its remedy is different from a missing
      # grant's (fix the registration, not run the reconcile), so the task
      # reports it separately.
      def drifted? = missing_grants.any? || missing_roles.any? || orphan_grants.any?
    end

    # Creates absent global roles and absent grants. Never updates, never
    # deletes. Safe to run on every boot and safe to run twice.
    def reconcile!
      created_grants = []
      created_roles = []
      already_present = 0
      failed = []
      ledger, ledger_error = load_ledger
      observed = []
      desired_by_role = {}

      each_declared_role do |name, config|
        role = Role.find_by(name: name, account_id: nil)

        if role.nil?
          role = create_global_role!(name, config)
          created_roles << name
        end

        desired = desired_grants(name)
        desired_by_role[name] = desired
        current = role.role_permissions.pluck(:permission_name)
        already_present += (desired & current).size
        (desired & current).each { |p| observed << "#{name}/#{p}" }

        (desired - current).each do |permission_name|
          role.role_permissions.find_or_create_by!(permission_name: permission_name)
          created_grants << "#{name}/#{permission_name}"
          observed << "#{name}/#{permission_name}"
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

      # Decide against the ledger AS LOADED, before this run's own observations
      # are merged in — otherwise every creation would count as a re-creation.
      recreated_grants = created_grants.select { |key| ledger.key?(key) }
      # A run that could not READ the ledger must not WRITE one: `ledger` is the
      # empty fallback there, so saving would replace the deployment's memory
      # with a view in which every key is first-seen NOW — and the next
      # revocation would come back unflagged. Carry the read error instead.
      ledger_error = save_ledger(ledger, observed, desired_by_role) if ledger_error.nil?

      Result.new(
        created: created_grants.size,
        already_present: already_present,
        created_grants: created_grants,
        created_roles: created_roles,
        failed: failed,
        recreated_grants: recreated_grants,
        ledger_error: ledger_error
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

      ledger, _error = load_ledger

      DriftReport.new(missing_grants: missing_grants, missing_roles: missing_roles,
                      extra_grants: extra_grants, orphan_grants: orphan_grant_keys,
                      present: present,
                      previously_held: missing_grants.select { |key| ledger.key?(key) })
    end

    private

    # [ledger_hash, error_or_nil]. An unreadable ledger reads as EMPTY so the
    # reconcile proceeds; the error rides along so the caller can say the signal
    # is degraded rather than silently reporting "no reversals".
    #
    # The row is read RAW rather than through SiteSetting.get. That accessor's
    # json branch is `JSON.parse(setting.value) rescue {}`
    # (app/models/site_setting.rb), which hands back an empty Hash for a corrupt
    # value with nothing to say it was corrupt — and the row is operator-editable
    # through Api::V1::SiteSettingsController#update, so corruption is reachable.
    # Laundered through that rescue, a garbled ledger would produce exactly the
    # state this mechanism exists to prevent: recreated_grants=0 reading as
    # clean, every key re-dated to now, and the NEXT revocation unflagged.
    def load_ledger
      row = ::SiteSetting.find_by(key: LEDGER_SETTING)
      return [ {}, nil ] if row.nil?

      parsed = JSON.parse(row.value.to_s)
      return [ parsed, nil ] if parsed.is_a?(Hash)

      [ {}, "ledger malformed: expected a JSON object, got #{parsed.class}" ]
    rescue JSON::ParserError => e
      [ {}, "ledger malformed: #{e.class}: #{e.message}" ]
    rescue StandardError => e
      [ {}, "ledger read failed: #{e.class}: #{e.message}" ]
    end

    # Merges this run's observations into the ledger and persists it. Returns
    # nil, or the error string if the write failed. Only writes when something
    # changed, so the steady-state boot touches nothing.
    #
    # Pruning is deliberately NARROW. A key is dropped only when the catalog
    # loaded here KNOWS the permission and the role no longer holds it — the
    # catalog withdrew the grant, which is the sanctioned revocation route, and
    # remembering "held" past that would flag a later re-declaration as a
    # reversal. A key whose permission is unknown to this process is kept:
    # Permissions.all_permissions is process-local, and on a module-composed
    # instance "unknown" is usually "not composed into this boot".
    def save_ledger(ledger, observed, desired_by_role)
      updated = ledger.reject do |key, _first_seen|
        role_name, permission_name = key.split("/", 2)
        desired = desired_by_role[role_name]
        desired && ::Permissions.permission_exists?(permission_name) && !desired.include?(permission_name)
      end

      now = Time.current.utc.iso8601
      observed.each { |key| updated[key] ||= now }

      return nil if updated == ledger

      ::SiteSetting.set(LEDGER_SETTING, updated, setting_type: "json", is_public: false,
                        description: "Declared global-role grants this deployment has been observed to hold " \
                                     "(Permissions::RoleGrantReconciler reversal ledger; state, not configuration)")
      nil
    rescue StandardError => e
      "ledger write failed: #{e.class}: #{e.message}"
    end

    # all_roles = core ROLES + every LOADED extension's registered roles. A
    # disabled extension never runs its initializer and so declares nothing —
    # which is exactly why nothing here may delete on the strength of a name's
    # absence from the catalog.
    def each_declared_role
      ::Permissions.all_roles.each { |name, config| yield(name.to_s, config) }
    end

    # Role names that grants were registered AGAINST but that all_roles does not
    # declare. Nothing validates the role key at registration time —
    # Permissions.register_role_permissions accepts any string
    # (config/permissions.rb), and the catalog DSL's `grant:` hash autovivifies
    # on any key (config/permissions/catalog.rb) — so a typo, or a role whose
    # definition was removed while its grants stayed, produces a grant that
    # each_declared_role never yields and therefore never reconciles.
    #
    # Empty lists are skipped, but NOT for the reason it looks like. Every caller
    # of permissions_for_role passes a name drawn from all_roles (this class via
    # each_declared_role, Role.sync_from_config!, permissions:verify_admin), so
    # the keys its indexing autovivifies are all DECLARED and the filter below
    # already removes them. What the empty-list skip actually catches is a
    # STALE UNDECLARED key: a grant list that was registered and then emptied,
    # or a key autovivified by a read against an undeclared name. Those hold no
    # grants, so reporting them would be a phantom orphan.
    #
    # NOT a deletion trigger and not something reconcile! can repair: the fix is
    # to correct the registration. This exists so the drift report cannot
    # certify such a grant as clean.
    def orphan_grant_keys
      declared = ::Permissions.all_roles.keys.map(&:to_s)

      keys = ::Permissions.extension_role_permissions.reject { |_k, v| Array(v).empty? }.keys.map(&:to_s)
      if ::Permissions.respond_to?(:catalog_grants)
        keys += ::Permissions.catalog_grants.reject { |_k, v| Array(v).empty? }.keys.map(&:to_s)
      end

      keys.uniq.reject { |k| declared.include?(k) }.sort
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

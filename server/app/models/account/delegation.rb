# frozen_string_literal: true

class Account::Delegation < ApplicationRecord
    self.table_name = "account_delegations"

    # Associations
    belongs_to :account
    belongs_to :delegated_user, class_name: "User", foreign_key: "delegated_user_id"
    belongs_to :delegated_by, class_name: "User", foreign_key: "delegated_by_id"
    belongs_to :revoked_by, class_name: "User", foreign_key: "revoked_by_id", optional: true
    belongs_to :role, optional: true

    # Permission associations
    # Permissions are code-defined (the Permissions catalog) and referenced by
    # NAME (string) through delegation_permissions — there is no Permission AR
    # model or through-association.
    has_many :delegation_permissions, class_name: "Account::DelegationPermission", foreign_key: "account_delegation_id", dependent: :destroy

    # Validations
    validates :delegated_by_id, uniqueness: { scope: [ :account_id, :delegated_user_id ],
                                             message: "has already delegated to this user for this account" }
    validates :status, presence: true, inclusion: { in: %w[active inactive revoked] }

    # Scopes
    scope :active, -> { where(status: "active") }
    scope :inactive, -> { where(status: "inactive") }
    scope :revoked, -> { where(status: "revoked") }
    scope :for_account, ->(account) { where(account: account) }
    scope :for_user, ->(user) { where(delegated_user: user) }
    scope :not_expired, -> { where("expires_at IS NULL OR expires_at >= ?", Time.current) }
    scope :expired, -> { where("expires_at IS NOT NULL AND expires_at < ?", Time.current) }
    scope :with_role, ->(role) { where(role: role) }
    scope :by_role_name, ->(role_name) { joins(:role).where(roles: { name: role_name }) }

    # Callbacks
    before_create :set_defaults

    # State management
    def active?
      status == "active" && !expired?
    end

    def inactive?
      status == "inactive"
    end

    def revoked?
      status == "revoked"
    end

    def expired?
      expires_at && expires_at < Time.current
    end

    def activate!
      update!(status: "active")
    end

    def deactivate!
      update!(status: "inactive")
    end

    def revoke!(revoked_by_user)
      update!(status: "revoked", revoked_at: Time.current, revoked_by: revoked_by_user)
    end

    # Permission methods
    #
    # THESE THREE ANSWER FROM THE ROLE ALONE and ignore the custom permission
    # set entirely, so on a custom+role delegation they report authority the
    # delegation does not actually confer through #effective_permissions. They
    # have no callers anywhere — server, worker, frontend, or any extension —
    # which is the only reason that is not a defect.
    #
    # Read this before wiring any of them to a gate: they are the standing
    # exception to the reasoning in
    # Accounts::DelegationService#unconferrable_reason, which does NOT re-vet the
    # role on a custom+role row precisely because the role cannot contribute
    # beyond the custom set. Route a new caller through #has_permission? instead,
    # or that becomes false and activation has to start checking the role.
    def can_manage_account?
      active? && (role&.name == "Admin" || role&.name == "Owner")
    end

    def can_view_analytics?
      active? && role&.has_permission?("analytics.read")
    end

    def can_manage_users?
      active? && role&.has_permission?("users.create")
    end

    # Permission names assigned directly to this delegation (custom overrides).
    def permission_names
      delegation_permissions.pluck(:permission_name)
    end

    # The permission set this delegation is CONFIGURED to carry, independent of
    # status: the custom delegation permissions when any are assigned, otherwise
    # the delegation role's permission names.
    #
    # Split out of #effective_permissions because two callers must reason about a
    # delegation that is NOT (or not yet) active, and #effective_permissions
    # deliberately returns [] for those:
    #
    #   - Accounts::DelegationService#activate_delegation re-checks the row
    #     BEFORE flipping it active. Asking #effective_permissions there always
    #     answers [], so the check would pass vacuously on every row.
    #   - Accounts::DelegationService#remove_permission_from_delegation asks what
    #     the set WOULD become; the answer must not depend on status.
    #
    # Note this is the seat of the removal hazard: an empty custom set falls back
    # to the role (#role_backed_permissions — the role's live grants bounded by
    # the delegator since IMP-1635cb7fa768, which at mint IS the whole role), so
    # emptying the custom set WIDENS the delegation.
    # The fallback stays — a role-only delegation (which create_delegation
    # explicitly permits) carries nothing without it — and the write path guards
    # the transition instead.
    def configured_permissions
      configured_permissions_for(permission_names)
    end

    # What this delegation WOULD carry if its custom set were `custom`.
    #
    # The fallback rule lives here once so a write-path guard asking "what would
    # this become?" cannot drift from what the delegation actually resolves —
    # Accounts::DelegationService#widening_from_removal restating the rule for
    # itself would leave two copies to keep in step, and the weaker one becomes
    # the way in.
    #
    # THE EXPLICIT SET IS BOUNDED BY THE ROLE, LIVE (IMP-7964b5d261b4).
    # Five write sites already enforce "every custom name is within the role's
    # scope": DelegationService create / update / add_permission,
    # #assign_permission below, and Account::DelegationPermission's own
    # before_create. All five bind the WRITE, so the invariant held only until
    # the ROLE changed underneath an existing row — which is exactly what a
    # catalog-remap migration does (`delegation_permissions` is a second,
    # independent store of permission NAMES that such a migration does not
    # reach). Resolving the explicit set verbatim let a delegation keep
    # conferring a name its role no longer grants, permanently:
    # Authentication#has_permission? short-circuits a delegated session to this
    # set and never falls through to roles, and the row itself carries the name,
    # so no token lifetime bounds it.
    #
    # Re-applying the same predicate at RESOLUTION is what makes a role-side
    # revoke reach delegation-borne grants. It also gives the explicit set the
    # live read the EMPTY set has always had — that fallback is the only reason
    # the role-backed case was never affected.
    #
    # THE PREDICATE MUST BE Role#has_permission?, NOT Role#permission_names.
    # The two agree for an ordinary role (both read role_permissions rows) and
    # DIVERGE on a system.admin role: has_permission? answers true for any name,
    # while permission_names answers the RUNNING PROCESS'S catalog
    # (Permissions.all_permissions = core + whichever extension engines
    # initialized). Filtering against that would strip an extension permission
    # off a system.admin-backed delegation in any process where the extension is
    # not loaded — and strip any name since removed from the catalog — neither of
    # which the five write sites would have refused. So system.admin is
    # short-circuited (one query, and no whole-catalog materialization), and only
    # an ordinary role reaches the row-backed filter.
    #
    # A role-LESS delegation has no role to bound it; its bound is the
    # delegator's own grantable set, applied at create/update/add and re-checked
    # at activation.
    #
    # NOT the other half of a catalog remap. A migration that narrows a
    # permission also GRANTS its own-account replacement to whoever held the old
    # name; this guard only stops the stale name resolving. On a deployment that
    # does carry delegations, an operator must still rewrite such a set through
    # DelegationService#update_delegation — removing the LAST stale name one at
    # a time is refused by #widening_from_removal, because emptying the custom
    # set falls back to the role (#role_backed_permissions).
    def configured_permissions_for(custom)
      custom = Array(custom)
      # Keyed on the RAW set being empty, never on the FILTERED result: a
      # delegation whose every custom name went stale must resolve to NOTHING,
      # not be promoted to its role's set. Falling back on the filtered set
      # would turn this guard into the widening it exists to close.
      return role_backed_permissions if custom.empty?
      return custom if role.blank?
      return custom if role.has_permission?("system.admin")

      granted = role.permission_names.to_set
      custom.select { |name| granted.include?(name) }
    end

    # THE ROLE-BACKED SET: the role's live grants, bounded by what the DELEGATOR
    # actually holds (IMP-1635cb7fa768 item 2).
    #
    # A delegation with an empty custom set resolves through the role, so the
    # role IS its authority — and conferring that role was authorised exactly
    # once, at mint time, against the delegator's own permissions
    # (Role#assignable_by?). Nothing re-asked the question when the role changed
    # underneath: Api::V1::RolesController#update gates on the EDITOR's grantable
    # set and knows nothing about outstanding delegations, so a SECOND admin
    # widening a role retroactively grew every delegation minted against it.
    # Authentication#has_permission? resolves a delegated session straight from
    # #effective_permissions ahead of any role lookup, so the widened set was
    # live authority the delegator never held and could not have conferred.
    #
    # THIS IS THE PROPAGATION ANSWER, NOT A GATING ONE. Tightening
    # RolesController#update would only narrow who can trigger it; the bound
    # belongs where the delegation RESOLVES, for the same reason the explicit
    # set's bound does (see #configured_permissions_for): a write-site hook is
    # bypassed by Role.sync_from_config! at seed time and by any raw-SQL grant
    # change, neither of which fires an ActiveRecord callback.
    #
    # NOT A MINT-TIME SNAPSHOT, which is the other way this question could have
    # been answered. Freezing the set would reintroduce IMP-7964b5d261b4: the
    # live read is the only reason a role-side REVOKE reaches a delegation-borne
    # grant at all. Intersecting keeps narrowing live and stops only the
    # widening. At mint the intersection is the whole role — #assignable_by?
    # guarantees the subset — so nothing legitimately conferred changes.
    #
    # Fails CLOSED with no delegator: an authority with no source bounds nothing.
    # system.admin short-circuits for the reason spelled out above — its
    # #permission_names is the running process's catalog, not its true set.
    #
    # COST, since this adds a USER resolution to a path that previously touched
    # only roles: User#permission_names is Rails.cache-backed, but its key calls
    # #role_cache_key, which is deliberately `self.class.uncached` and NOT
    # memoized (it must observe another process's narrowing), so every call
    # issues a `roles.order(:id).pluck`. Memoized per delegation instance below
    # so a row resolved more than once in a request pays it once. It is still
    # once per ROW in DelegationsController#index — `includes(:delegated_by)`
    # cannot help, because #role_cache_key spawns a fresh unloaded relation on
    # purpose. Hoist a delegator_id -> set map into the serializer if that index
    # ever grows hot.
    def role_backed_permissions
      return [] if role.blank?

      names = role.permission_names
      delegator = delegated_by
      return [] if delegator.nil?
      return names if delegator.has_permission?("system.admin")

      held = delegator_permission_set
      names.select { |name| held.include?(name) }
    end

    # The delegator's own grants, resolved once per delegation instance. Scoped
    # to the instance rather than the class: it is a snapshot of another user's
    # live authority, and holding it beyond one request would be exactly the
    # staleness User#role_cache_key refuses to introduce.
    def delegator_permission_set
      @delegator_permission_set ||= delegated_by.permission_names.to_set
    end

    # Stored custom names this delegation NO LONGER CONFERS: the
    # delegation_permissions rows minus what #configured_permissions actually
    # resolves to.
    #
    # No write site MINTS one — DelegationService create / update /
    # add_permission, #assign_permission below and
    # Account::DelegationPermission's before_create all refuse to STORE a name
    # outside the role's scope. A stale name appears when the ROLE changes
    # underneath an already-stored set, which has two producers, not one:
    #
    #   - the role's grant is revoked underneath the row (a catalog remap);
    #   - the delegation is moved to a DIFFERENT role without a permission
    #     rewrite. Accounts::DelegationService#update_delegation validates the
    #     custom set against the target role, and rewrites it, only when
    #     `permission_names` is supplied, so a role-only PATCH leaves the
    #     existing rows in place and unchecked against the new role.
    #
    # So a non-empty stale set does NOT by itself imply a remap.
    #
    # This exists so the API can keep the stale set VISIBLE while reporting the
    # resolved set as the delegation's permissions. Dropping the stale names
    # silently would leave an operator cleaning up after a role change with no
    # way to see which stored names need rewriting. Clearing them one at a time
    # only goes so far: DelegationService#remove_permission_from_delegation
    # refuses the removal that would EMPTY the custom set (an empty set falls
    # back to #role_backed_permissions, so that removal WIDENS), and refuses any
    # name that has left the code-defined catalog altogether
    # (`Permissions.permission_exists?`). A wholly-stale set is therefore
    # rewritten through #update_delegation.
    #
    # Derived from #configured_permissions rather than restating the filter, so
    # the display cannot drift from the resolver — which is the exact split this
    # method was added to close. `resolved` is an optimisation seam for a caller
    # that has ALREADY resolved THIS delegation (each resolution costs two role
    # queries that nothing memoizes, plus — on a role-backed row — the
    # delegator's own permission resolution, which #role_backed_permissions
    # memoizes per instance; the API serializer renders both sets in one
    # payload); every other caller passes nothing.
    def stale_permission_names(resolved = configured_permissions)
      permission_names - resolved
    end

    # Effective permission NAME strings: the configured set, but only while the
    # delegation is actually active.
    def effective_permissions
      return [] unless active?

      configured_permissions
    end

    # Display helpers
    def role_display_name
      role&.name || "No Role"
    end

    def status_display
      case status
      when "active"
        expired? ? "Expired" : "Active"
      when "inactive"
        "Inactive"
      when "revoked"
        "Revoked"
      else
        status.humanize
      end
    end

    def expires_in_days
      return nil unless expires_at
      ((expires_at - Time.current) / 1.day).ceil
    end

    # Permission management methods
    def has_permission?(permission_key)
      return false unless active?

      effective_permissions.include?(permission_key)
    end

    def assign_permission(permission_name)
      return false unless active?

      # Only check if custom permission is already assigned (not role permissions)
      return false if delegation_permissions.exists?(permission_name: permission_name)

      # Validate permission is within role scope if role is assigned
      if role.present? && !role.has_permission?(permission_name)
        return false
      end

      # THE RETURN VALUE IS THE CONTRACT, so it must reflect what actually
      # happened. A bare `create` followed by an unconditional `true` reported
      # success for every record that failed to persist — a failed validation,
      # or Account::DelegationPermission's own `before_create` throwing :abort.
      #
      # Accounts::DelegationService#update_delegation rewrites the custom set as
      # destroy_all + assign_permission and rolls the whole transaction back on a
      # false. A silent success there would leave the custom set EMPTY, which
      # falls back to #role_backed_permissions — the exact promotion that guard
      # exists to prevent, audit-logged as a success.
      #
      # #persisted? rather than create!: it answers both failure modes with one
      # expression, where create! raises RecordInvalid for the first and
      # RecordNotSaved for the second.
      delegation_permissions.create(permission_name: permission_name).persisted?
    rescue ActiveRecord::RecordInvalid
      false
    end

    def remove_permission(permission_name)
      delegation_permissions.where(permission_name: permission_name).destroy_all
    end

    def permission_source
      if permission_names.any?
        "custom"
      elsif role.present?
        "role"
      else
        "none"
      end
    end

    # Role permission names that aren't already specifically assigned.
    def available_permissions
      return [] unless role.present?

      role.permission_names - permission_names
    end

    def permissions_summary
      perms = effective_permissions
      return "No permissions" if perms.empty?

      # Group "resource.sub.action" by everything-but-the-last-segment -> action.
      grouped = perms.group_by { |name| name.split(".")[0..-2].join(".") }
      summary_parts = grouped.map do |resource, names|
        actions = names.map { |name| name.split(".").last }.sort
        "#{resource}: #{actions.join(', ')}"
      end

      summary_parts.join(" | ")
    end

  private

  def set_defaults
    self.status = "active" if status.blank?
  end
end

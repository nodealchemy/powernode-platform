# frozen_string_literal: true

module Accounts
  class DelegationService
    attr_reader :delegator, :account

    def initialize(delegator, account)
      @delegator = delegator
      @account = account
    end

    def create_delegation(delegated_user_email:, role_id: nil, permission_names: nil, expires_at: nil, notes: nil)
      begin
        # Find the user to delegate to
        delegated_user = User.find_by(email: delegated_user_email)
        unless delegated_user
          return { success: false, errors: [ "User with email #{delegated_user_email} not found" ] }
        end

        # Validate the user isn't delegating to themselves
        if delegated_user == delegator
          return { success: false, errors: [ "Cannot delegate to yourself" ] }
        end

        # Validate the user isn't already an owner of this account
        if account.users.include?(delegated_user)
          return { success: false, errors: [ "User is already a member of this account" ] }
        end

        # Validate role exists and is appropriate for delegation
        role = Role.find_by(id: role_id) if role_id.present?
        if role_id.present? && !role
          return { success: false, errors: [ "Role not found" ] }
        end

        # Validate role permissions (don't allow delegating Owner role)
        if role&.name == "Owner"
          return { success: false, errors: [ "Cannot delegate Owner role" ] }
        end

        # Conferring a whole ROLE is bound by Role#assignable_by? — see
        # #unassignable_role_error for why the rule lives here as well as in the
        # controller.
        if role.present? && !role.assignable_by?(delegator)
          return { success: false, errors: [ unassignable_role_error(role) ] }
        end

        # Validate and process custom permissions (by NAME) if provided
        specific_permissions = []
        if permission_names.present?
          specific_permissions = Array(permission_names)

          # All names must exist in the code-defined permission catalog
          unknown = specific_permissions.reject { |name| Permissions.permission_exists?(name) }
          if unknown.any?
            return { success: false, errors: [ "Some permissions not found" ] }
          end

          # No privilege escalation: only permissions the delegator itself holds.
          escalating = ungrantable_permission_names(specific_permissions)
          if escalating.any?
            return { success: false, errors: [ escalation_error(escalating) ] }
          end

          # If role is specified, ensure all permissions are within the role's scope
          if role.present?
            invalid_permissions = specific_permissions.reject { |name| role.has_permission?(name) }
            if invalid_permissions.any?
              return { success: false, errors: [ "Permissions #{invalid_permissions.join(', ')} are not available in the #{role.name} role" ] }
            end
          end
        end

        # Require either role or specific permissions
        if role.blank? && specific_permissions.empty?
          return { success: false, errors: [ "Must specify either a role or specific permissions" ] }
        end

        # Check if delegation already exists for this user
        existing_delegation = account.account_delegations
                                    .where(delegated_user: delegated_user)
                                    .where(status: [ "active", "inactive" ])
                                    .first

        if existing_delegation
          return { success: false, errors: [ "Active delegation already exists for this user" ] }
        end

        # Create the delegation
        delegation = account.account_delegations.build(
          delegated_user: delegated_user,
          delegated_by: delegator,
          role: role,
          expires_at: expires_at,
          notes: notes,
          status: "active"
        )

        # SAME SHAPE AS update_delegation, AND FOR THE SAME REASON. The row and
        # its custom permission set must commit together, and every
        # #assign_permission return value must be checked: a delegation saved
        # ACTIVE with a role whose custom set then failed to populate is a
        # delegation with an EMPTY custom set, which falls back to the ROLE's
        # FULL permission set (Account::Delegation#configured_permissions_for) —
        # a narrowed grant silently promoted to the whole role, audit-logged as a
        # success. Reachable only through a duplicate name or a concurrent role
        # change today, since every name is pre-validated above; the point is
        # that the guarantee should not rest on that.
        result = nil
        ActiveRecord::Base.transaction do
          unless delegation.save
            result = { success: false, errors: delegation.errors.full_messages }
            raise ActiveRecord::Rollback
          end

          specific_permissions.each do |permission_name|
            next if delegation.assign_permission(permission_name)

            result = { success: false, errors: [ "Could not assign permission #{permission_name}: the delegation must be active and the permission within its role" ] }
            raise ActiveRecord::Rollback
          end

          # Create audit log entry
          create_audit_log("delegation_created", delegation)

          result = { success: true, delegation: delegation }
        end
        result
      rescue StandardError => e
        Rails.logger.error "Account::DelegationService#create_delegation failed: #{e.message}"
        { success: false, errors: [ "Failed to create delegation: #{e.message}" ] }
      end
    end

    def update_delegation(delegation:, role_id: nil, permission_names: nil, expires_at: nil, notes: nil)
      begin
        # Validate delegation belongs to account
        unless delegation.account == account
          return { success: false, errors: [ "Delegation not found" ] }
        end

        # Validate delegation can be updated
        if delegation.revoked?
          return { success: false, errors: [ "Cannot update revoked delegation" ] }
        end

        # Prepare update parameters
        update_params = {}

        # Update role if provided
        if role_id.present?
          role = Role.find_by(id: role_id)
          unless role
            return { success: false, errors: [ "Role not found" ] }
          end

          # Validate role permissions (don't allow delegating Owner role)
          if role.name == "Owner"
            return { success: false, errors: [ "Cannot delegate Owner role" ] }
          end

          # A ROLE CHANGE IS AN AUTHORITY TRANSFER, and on a role-only row it is
          # the WHOLE of the delegation's authority: an empty custom set falls
          # back to the role's full permission set
          # (Account::Delegation#configured_permissions_for). Bounding the
          # explicit set by the live role (IMP-7964b5d261b4) does not reach this
          # — that guard can only ever SUBTRACT from a non-empty custom set,
          # while this path replaces the fallback wholesale.
          if !role.assignable_by?(delegator)
            return { success: false, errors: [ unassignable_role_error(role) ] }
          end

          update_params[:role] = role
        end

        # Update expires_at if provided
        update_params[:expires_at] = expires_at if expires_at.present?

        # Update notes if provided
        update_params[:notes] = notes if notes.present?

        # Handle permission updates (by NAME)
        if permission_names.present?
          specific_permissions = Array(permission_names)

          # All names must exist in the code-defined permission catalog
          unknown = specific_permissions.reject { |name| Permissions.permission_exists?(name) }
          if unknown.any?
            return { success: false, errors: [ "Some permissions not found" ] }
          end

          # No privilege escalation: only permissions the delegator itself holds.
          escalating = ungrantable_permission_names(specific_permissions)
          if escalating.any?
            return { success: false, errors: [ escalation_error(escalating) ] }
          end

          # If role is being updated, validate permissions against new role
          target_role = update_params[:role] || delegation.role
          if target_role.present?
            invalid_permissions = specific_permissions.reject { |name| target_role.has_permission?(name) }
            if invalid_permissions.any?
              return { success: false, errors: [ "Permissions #{invalid_permissions.join(', ')} are not available in the #{target_role.name} role" ] }
            end
          end
        end

        result = nil
        # Atomic: the role change + permission rewrite must commit together. The
        # update MUST be inside the transaction, or a mid-loop failure would leave
        # the delegation with the NEW role but a partial/empty permission set.
        ActiveRecord::Base.transaction do
          unless delegation.update(update_params)
            result = { success: false, errors: delegation.errors.full_messages }
            raise ActiveRecord::Rollback
          end

          # Update specific permissions if provided
          if permission_names.present?
            # Remove existing delegation permissions
            delegation.delegation_permissions.destroy_all

            # Add new permissions (by name).
            #
            # The return value is NOT optional. Account::Delegation#assign_permission
            # returns false for a NON-ACTIVE delegation, and this method guards
            # only against `revoked?` — so on an inactive or expired row every
            # assignment silently no-ops, the destroy_all above stands alone, and
            # the delegation is left with an EMPTY custom set. An empty custom
            # set falls back to the ROLE's full set, which is precisely the
            # promotion remove_permission_from_delegation refuses: "narrow this
            # delegation to [X]" became "promote it to its whole role", audit-
            # logged as a success. Fail the whole transaction instead, so the
            # previous set survives intact.
            specific_permissions.each do |permission_name|
              next if delegation.assign_permission(permission_name)

              result = { success: false, errors: [ "Could not assign permission #{permission_name}: the delegation must be active and the permission within its role" ] }
              raise ActiveRecord::Rollback
            end
          end

          # Create audit log entry
          create_audit_log("delegation_updated", delegation)

          result = { success: true, delegation: delegation }
        end
        result
      rescue StandardError => e
        Rails.logger.error "Account::DelegationService#update_delegation failed: #{e.message}"
        { success: false, errors: [ "Failed to update delegation: #{e.message}" ] }
      end
    end

    def activate_delegation(delegation)
      begin
        unless delegation.account == account
          return { success: false, errors: [ "Delegation not found" ] }
        end

        if delegation.revoked?
          return { success: false, errors: [ "Cannot activate revoked delegation" ] }
        end

        if delegation.expired?
          return { success: false, errors: [ "Cannot activate expired delegation" ] }
        end

        # RE-CHECK ON ACTIVATION. Every other guard here binds a write, so they
        # are forward-only: a row that already carries authority the activator
        # could not confer — minted before those guards existed, or left behind
        # by a role that has since gained permissions — was honoured verbatim the
        # moment it went active. Activation is the point where a stored row
        # becomes live authority, so it is re-checked against the same rules the
        # write paths apply, with `delegator` being whoever is activating.
        blocked = unconferrable_reason(delegation)
        if blocked
          return { success: false, errors: [ blocked ] }
        end

        if delegation.activate!
          create_audit_log("delegation_activated", delegation)
          { success: true, delegation: delegation }
        else
          { success: false, errors: delegation.errors.full_messages }
        end
      rescue StandardError => e
        Rails.logger.error "Account::DelegationService#activate_delegation failed: #{e.message}"
        { success: false, errors: [ "Failed to activate delegation: #{e.message}" ] }
      end
    end

    def deactivate_delegation(delegation)
      begin
        unless delegation.account == account
          return { success: false, errors: [ "Delegation not found" ] }
        end

        if delegation.revoked?
          return { success: false, errors: [ "Cannot deactivate revoked delegation" ] }
        end

        if delegation.deactivate!
          create_audit_log("delegation_deactivated", delegation)
          { success: true, delegation: delegation }
        else
          { success: false, errors: delegation.errors.full_messages }
        end
      rescue StandardError => e
        Rails.logger.error "Account::DelegationService#deactivate_delegation failed: #{e.message}"
        { success: false, errors: [ "Failed to deactivate delegation: #{e.message}" ] }
      end
    end

    def revoke_delegation(delegation)
      begin
        unless delegation.account == account
          return { success: false, errors: [ "Delegation not found" ] }
        end

        if delegation.revoked?
          return { success: false, errors: [ "Delegation already revoked" ] }
        end

        if delegation.revoke!(delegator)
          create_audit_log("delegation_revoked", delegation)
          { success: true, delegation: delegation }
        else
          { success: false, errors: delegation.errors.full_messages }
        end
      rescue StandardError => e
        Rails.logger.error "Account::DelegationService#revoke_delegation failed: #{e.message}"
        { success: false, errors: [ "Failed to revoke delegation: #{e.message}" ] }
      end
    end

    def list_available_users_for_delegation
      # Users that can be delegated to (not already members of the account)
      User.where.not(id: account.user_ids)
          .where.not(id: delegator.id)
          .active
          .order(:name)
    end

    def list_available_permissions_for_delegation(role_id: nil)
      # Only ever offer what the delegator could actually grant — the picker must
      # not present permissions the create/update guards will then refuse.
      grantable = grantable_permission_names

      if role_id.present?
        role = Role.find_by(id: role_id)
        return [] unless role && role.name != "Owner"

        # Permission NAME strings granted to this role
        role.permission_names & grantable
      else
        # No role specified: every catalog permission the delegator may grant
        grantable.sort
      end
    end

    def add_permission_to_delegation(delegation:, permission_name:)
      begin
        unless delegation.account == account
          return { success: false, errors: [ "Delegation not found" ] }
        end

        if delegation.revoked?
          return { success: false, errors: [ "Cannot modify revoked delegation" ] }
        end

        unless Permissions.permission_exists?(permission_name)
          return { success: false, errors: [ "Permission not found" ] }
        end

        # No privilege escalation: only permissions the delegator itself holds.
        escalating = ungrantable_permission_names([ permission_name ])
        if escalating.any?
          return { success: false, errors: [ escalation_error(escalating) ] }
        end

        # Validate permission is within role scope if role is assigned
        if delegation.role.present? && !delegation.role.has_permission?(permission_name)
          return { success: false, errors: [ "Permission #{permission_name} is not available in the #{delegation.role.name} role" ] }
        end

        if delegation.assign_permission(permission_name)
          create_audit_log("delegation_permission_added", delegation, {
            permission: permission_name
          })
          { success: true, delegation: delegation }
        else
          { success: false, errors: [ "Permission already assigned or invalid" ] }
        end
      rescue StandardError => e
        Rails.logger.error "Account::DelegationService#add_permission_to_delegation failed: #{e.message}"
        { success: false, errors: [ "Failed to add permission: #{e.message}" ] }
      end
    end

    def remove_permission_from_delegation(delegation:, permission_name:)
      begin
        unless delegation.account == account
          return { success: false, errors: [ "Delegation not found" ] }
        end

        if delegation.revoked?
          return { success: false, errors: [ "Cannot modify revoked delegation" ] }
        end

        unless Permissions.permission_exists?(permission_name)
          return { success: false, errors: [ "Permission not found" ] }
        end

        # A REMOVAL MUST NOT WIDEN. Account::Delegation#configured_permissions
        # falls back to the role's full set when the custom set is empty, so
        # dropping the last custom name PROMOTES the delegation to everything the
        # role grants — a call named "remove" raising effective authority. See
        # the fork this settles in #widening_from_removal.
        widened = widening_from_removal(delegation, permission_name)
        if widened.any?
          return { success: false, errors: [ widening_error(delegation, widened) ] }
        end

        delegation.remove_permission(permission_name)
        create_audit_log("delegation_permission_removed", delegation, {
          permission: permission_name
        })

        { success: true, delegation: delegation }
      rescue StandardError => e
        Rails.logger.error "Account::DelegationService#remove_permission_from_delegation failed: #{e.message}"
        { success: false, errors: [ "Failed to remove permission: #{e.message}" ] }
      end
    end

    private

    # Privilege-escalation guard shared by every delegation write path.
    #
    # A delegation is LIVE AUTHORITY in the target account: for a delegated
    # session Authentication#has_permission? resolves straight from
    # Account::Delegation#effective_permissions, ahead of any role lookup. So a
    # delegation may only carry authority the DELEGATOR already holds. That is
    # exactly the rule the role editor applies via User#can_grant_permission?
    # (grantable == held, and never the system tier) — reused here rather than
    # restated, so the two cannot drift.
    #
    # Scope: this binds the CUSTOM permission names only, which is the right
    # noun — Account::Delegation#effective_permissions returns the custom set
    # whenever one exists and only falls back to role.permission_names when it
    # is empty. Conferring a whole ROLE is a different question with its own
    # existing answer (RoleAssignmentGuard#can_assign_role?), applied by
    # Api::V1::DelegationsController#authorize_delegated_role!.
    #
    # Fails closed: with no delegator, nothing is grantable.
    #
    # The grantable SET is hoisted out of the loop rather than calling
    # can_grant_permission? per name — a delegated role can carry hundreds of
    # names and each call re-derives the same set. Same hoist, same rule, as
    # RolesController#assignable does for the role subset test.
    def ungrantable_permission_names(names)
      names = Array(names)
      return [] if names.empty?

      grantable = grantable_permission_names
      names.reject { |name| grantable.include?(name) }
    end

    def grantable_permission_names
      return [] if delegator.blank?

      delegator.grantable_permission_names
    end

    def escalation_error(names)
      "You cannot grant permissions you do not hold (or system-tier permissions): #{Array(names).join(', ')}"
    end

    # THE ROLE HALF OF THE CONFERRAL RULE, APPLIED IN THE SERVICE.
    #
    # Conferring a whole role through a delegation is the same authority
    # transfer as assigning that role, so it is bound by Role#assignable_by? —
    # the shared rule RoleAssignmentGuard#can_assign_role? delegates to. NOT
    # User#grantable_permission_names, which binds a list of permission NAMES:
    # extensions register real system.* names onto the seeded global admin and
    # manager roles, so the grantable (held-minus-system-tier) rule would make
    # the platform's two broadest roles undelegatable by everyone, including a
    # system.admin holder.
    #
    # 4da742156 placed this check in Api::V1::DelegationsController
    # (#authorize_delegated_role!) alone, and that controller is the service's
    # only production caller today — so for the controller path this is a
    # provable no-op. It is DEPTH, not replacement: the controller check stays.
    # A rule that lives only in a controller concern is unavailable to every
    # non-controller caller and gets skipped by all of them, and this service has
    # non-controller significance.
    #
    # This helper deduplicates the service's OWN copies — create, update and
    # #unconferrable_reason now share one string. The controller's literal
    # (Api::V1::DelegationsController#authorize_delegated_role!) is a third copy
    # that this cannot reach and nothing ties to it; it is byte-identical today,
    # not structurally prevented from drifting. The predicate is shared
    # (Role#assignable_by?) even where the wording is not, which is the half that
    # matters.
    def unassignable_role_error(role)
      "You cannot delegate the #{role.name} role: it grants privileges beyond your own"
    end

    # Names the delegation would GAIN if `permission_name` were removed.
    #
    # THE DESIGN FORK THIS SETTLES. An empty custom set currently promotes the
    # delegation to the role's full set, so "remove" can widen. Two readings were
    # on the table:
    #
    #   (a) an empty custom set means the delegation carries nothing beyond what
    #       is explicitly listed — i.e. drop the role fallback; or
    #   (b) apply the same grantable check to the RESULTING set that addition does.
    #
    # Neither, taken literally, is right. (a) as a change to
    # #configured_permissions would strand every role-only delegation:
    # create_delegation explicitly permits "role, no custom permissions", and the
    # fallback is the only thing that makes such a row carry anything. (b) is too
    # weak on its own: the widening is INTRINSIC to the fallback and happens even
    # when every gained name is one the delegator holds and could have added by
    # hand — a grantable test passes straight over that, exactly as a row-level
    # assertion does.
    #
    # So: (a)'s SEMANTICS — an empty custom set must not silently promote —
    # enforced at the write rather than by changing what #configured_permissions
    # means. The invariant is the property, not the mechanism: a removal may
    # never add a name to the set the delegation carries. Removals that genuinely
    # narrow (including emptying a role-LESS delegation down to nothing) stay
    # allowed; the one that would promote is refused, and the operator rewrites
    # the set through update_delegation or revokes the delegation instead.
    #
    # Computed as a set delta rather than special-casing "custom set becomes
    # empty", and the hypothetical set is resolved THROUGH the model's own
    # fallback rule (#configured_permissions_for) rather than restated here, so
    # a future change to that rule cannot leave this guard testing the old one.
    def widening_from_removal(delegation, permission_name)
      before = delegation.configured_permissions
      after = delegation.configured_permissions_for(delegation.permission_names - [ permission_name ])

      after - before
    end

    def widening_error(delegation, gained)
      role_name = delegation.role&.name
      "Removing this permission would widen the delegation" \
        "#{role_name ? " to the full #{role_name} role" : ''}, granting: #{Array(gained).sort.join(', ')}. " \
        "Update the delegation's permissions or revoke it instead."
    end

    # Reason the ACTIVATOR may not confer what this row already carries, or nil.
    #
    # Mirrors the same split the write paths use, because the two halves are
    # different questions with different existing answers:
    #
    #   - a CUSTOM permission set is bound by the grantable rule
    #     (User#grantable_permission_names — held, never the system tier), the
    #     same rule create/update/add apply;
    #   - a whole ROLE is bound by Role#assignable_by?, the shared
    #     RoleAssignmentGuard rule Api::V1::DelegationsController applies on
    #     create/update. Using the grantable rule here instead would be a
    #     LOCKOUT: extensions register real system.* names onto the seeded global
    #     admin and manager roles, so it would make the platform's two broadest
    #     roles unactivatable by everyone, including a system.admin holder.
    #
    # WHY A CUSTOM+ROLE ROW DOES NOT ALSO GET THE ROLE CHECK (IMP-ee308f92ea6a).
    # It was asked whether the custom branch should re-vet the role too. It must
    # not, and the reason is a property rather than a convenience: EVERY branch
    # of Account::Delegation#configured_permissions_for that a non-empty custom
    # set reaches returns a SUBSET of that custom set (verbatim, or filtered by
    # the role, or filtered by nothing on a system.admin role). So on such a row
    # the role can only ever SUBTRACT. It confers nothing the custom set does not
    # already carry, and the custom set is exactly what this branch vets — a role
    # check there would narrow nothing.
    #
    # It would, however, cost something real. The two rows that reach activation
    # want different answers: one whose role WAS conferrable when minted and no
    # longer is (a role that gained a permission, or an activator less privileged
    # than the delegator) is legitimate and must still go live; one whose role was
    # NEVER conferrable is the security case — and that one is already answered,
    # because whatever its role carries cannot exceed the vetted custom set.
    # Re-vetting here would strand the first to no benefit against the second.
    #
    # THE LINE THIS DEPENDS ON is the fallback KEY in #configured_permissions_for
    # — `return role&.permission_names || [] if custom.empty?`, i.e. only an
    # EMPTY custom set resolves from the role. NOT the role filter added by
    # IMP-7964b5d261b4: that filter can only subtract, and deleting it returns
    # `custom` verbatim (which is literally what the method did before that
    # commit), so it is not what stands between this branch and an escalation.
    # If the empty-set key ever moved — if a non-empty custom set could resolve
    # from the role — this branch would have to check the role. The filter itself
    # is pinned by spec/models/account_delegation_spec.rb
    # ('explicit custom set bounded by the live role').
    #
    # THE EXCEPTION TO "THE ROLE CONFERS NOTHING": Account::Delegation's
    # #can_manage_account? / #can_view_analytics? / #can_manage_users? answer
    # from the ROLE alone and ignore the custom set entirely. They have no
    # callers anywhere (server, worker, frontend, all extensions), so they do not
    # reach this decision today — but wiring any of them to a gate would invert
    # it, because then an unvetted role WOULD confer authority directly.
    #
    # NOT IN TENSION WITH create/update REFUSING SUCH A ROLE. Those paths are
    # forward-looking and deliberately stricter: a custom+role row whose role the
    # delegator cannot confer can no longer be MINTED, matching the controller's
    # long-standing behaviour on both endpoints. This branch governs rows that
    # ALREADY EXIST — minted before those guards, or whose role drifted since —
    # and refusing to honour them buys nothing. Both directions are pinned in
    # spec/services/accounts/delegation_service_role_conferral_spec.rb.
    def unconferrable_reason(delegation)
      custom = delegation.permission_names
      if custom.any?
        escalating = ungrantable_permission_names(custom)
        return escalating.any? ? escalation_error(escalating) : nil
      end

      role = delegation.role
      return nil if role.blank?
      return nil if role.assignable_by?(delegator)

      unassignable_role_error(role)
    end

    def create_audit_log(action, delegation, additional_details = {})
      base_details = {
        delegated_user_email: delegation.delegated_user.email,
        role_name: delegation.role&.name,
        status: delegation.status,
        expires_at: delegation.expires_at,
        permission_source: delegation.permission_source,
        permissions_count: delegation.effective_permissions.count
      }

      AuditLog.create!(
        user: delegator,
        account: account,
        action: action,
        auditable: delegation,
        details: base_details.merge(additional_details),
        ip_address: delegator&.current_sign_in_ip,
        user_agent: "Account::DelegationService"
      )
    rescue StandardError => e
      Rails.logger.warn "Failed to create audit log for #{action}: #{e.message}"
    end
  end
end

# Backwards compatibility alias

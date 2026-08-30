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

        if delegation.save
          # Assign specific permissions (by name) if provided
          if specific_permissions.any?
            specific_permissions.each do |permission_name|
              delegation.assign_permission(permission_name)
            end
          end

          # Create audit log entry
          create_audit_log("delegation_created", delegation)

          { success: true, delegation: delegation }
        else
          { success: false, errors: delegation.errors.full_messages }
        end
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

    def list_available_roles_for_delegation
      # Roles that can be delegated (exclude Owner role)
      Role.where.not(name: "Owner")
          .where(system_role: true)
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
    def unconferrable_reason(delegation)
      custom = delegation.permission_names
      if custom.any?
        escalating = ungrantable_permission_names(custom)
        return escalating.any? ? escalation_error(escalating) : nil
      end

      role = delegation.role
      return nil if role.blank?
      return nil if role.assignable_by?(delegator)

      "You cannot delegate the #{role.name} role: it grants privileges beyond your own"
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

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

            # Add new permissions (by name)
            specific_permissions.each do |permission_name|
              delegation.assign_permission(permission_name)
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

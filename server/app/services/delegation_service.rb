# frozen_string_literal: true

class DelegationService
  attr_reader :delegator, :account

  def initialize(delegator, account)
    @delegator = delegator
    @account = account
  end

  def create_delegation(delegated_user_email:, role_id: nil, permission_ids: nil, expires_at: nil, notes: nil)
    begin
      # Find the user to delegate to
      delegated_user = User.find_by(email: delegated_user_email)
      unless delegated_user
        return { success: false, errors: ["User with email #{delegated_user_email} not found"] }
      end

      # Validate the user isn't delegating to themselves
      if delegated_user == delegator
        return { success: false, errors: ["Cannot delegate to yourself"] }
      end

      # Validate the user isn't already an owner of this account
      if account.users.include?(delegated_user)
        return { success: false, errors: ["User is already a member of this account"] }
      end

      # Validate role exists and is appropriate for delegation
      role = Role.find_by(id: role_id) if role_id.present?
      if role_id.present? && !role
        return { success: false, errors: ["Role not found"] }
      end

      # Validate role permissions (don't allow delegating Owner role)
      if role&.name == 'Owner'
        return { success: false, errors: ["Cannot delegate Owner role"] }
      end

      # Validate and process custom permissions if provided
      specific_permissions = []
      if permission_ids.present?
        specific_permissions = Permission.where(id: permission_ids)
        
        if specific_permissions.count != permission_ids.count
          return { success: false, errors: ["Some permissions not found"] }
        end

        # If role is specified, ensure all permissions are within the role's scope
        if role.present?
          invalid_permissions = specific_permissions - role.permissions
          if invalid_permissions.any?
            invalid_names = invalid_permissions.map { |p| "#{p.resource}.#{p.action}" }
            return { success: false, errors: ["Permissions #{invalid_names.join(', ')} are not available in the #{role.name} role"] }
          end
        end
      end

      # Require either role or specific permissions
      if role.blank? && specific_permissions.empty?
        return { success: false, errors: ["Must specify either a role or specific permissions"] }
      end

      # Check if delegation already exists for this user
      existing_delegation = account.account_delegations
                                  .where(delegated_user: delegated_user)
                                  .where(status: ['active', 'inactive'])
                                  .first

      if existing_delegation
        return { success: false, errors: ["Active delegation already exists for this user"] }
      end

      # Create the delegation
      delegation = account.account_delegations.build(
        delegated_user: delegated_user,
        delegated_by: delegator,
        role: role,
        expires_at: expires_at,
        notes: notes,
        status: 'active'
      )

      if delegation.save
        # Assign specific permissions if provided
        if specific_permissions.any?
          specific_permissions.each do |permission|
            delegation.assign_permission(permission)
          end
        end

        # Create audit log entry
        create_audit_log('delegation_created', delegation)
        
        { success: true, delegation: delegation }
      else
        { success: false, errors: delegation.errors.full_messages }
      end
    rescue => e
      Rails.logger.error "DelegationService#create_delegation failed: #{e.message}"
      { success: false, errors: ["Failed to create delegation: #{e.message}"] }
    end
  end

  def update_delegation(delegation:, role_id: nil, permission_ids: nil, expires_at: nil, notes: nil)
    begin
      # Validate delegation belongs to account
      unless delegation.account == account
        return { success: false, errors: ["Delegation not found"] }
      end

      # Validate delegation can be updated
      if delegation.revoked?
        return { success: false, errors: ["Cannot update revoked delegation"] }
      end

      # Prepare update parameters
      update_params = {}
      
      # Update role if provided
      if role_id.present?
        role = Role.find_by(id: role_id)
        unless role
          return { success: false, errors: ["Role not found"] }
        end
        
        # Validate role permissions (don't allow delegating Owner role)
        if role.name == 'Owner'
          return { success: false, errors: ["Cannot delegate Owner role"] }
        end
        
        update_params[:role] = role
      end

      # Update expires_at if provided
      update_params[:expires_at] = expires_at if expires_at.present?

      # Update notes if provided
      update_params[:notes] = notes if notes.present?

      # Handle permission updates
      if permission_ids.present?
        specific_permissions = Permission.where(id: permission_ids)
        
        if specific_permissions.count != permission_ids.count
          return { success: false, errors: ["Some permissions not found"] }
        end

        # If role is being updated, validate permissions against new role
        target_role = update_params[:role] || delegation.role
        if target_role.present?
          invalid_permissions = specific_permissions - target_role.permissions
          if invalid_permissions.any?
            invalid_names = invalid_permissions.map { |p| "#{p.resource}.#{p.action}" }
            return { success: false, errors: ["Permissions #{invalid_names.join(', ')} are not available in the #{target_role.name} role"] }
          end
        end
      end

      if delegation.update(update_params)
        # Update specific permissions if provided
        if permission_ids.present?
          # Remove existing delegation permissions
          delegation.delegation_permissions.destroy_all
          
          # Add new permissions
          specific_permissions.each do |permission|
            delegation.assign_permission(permission)
          end
        end

        # Create audit log entry
        create_audit_log('delegation_updated', delegation)
        
        { success: true, delegation: delegation }
      else
        { success: false, errors: delegation.errors.full_messages }
      end
    rescue => e
      Rails.logger.error "DelegationService#update_delegation failed: #{e.message}"
      { success: false, errors: ["Failed to update delegation: #{e.message}"] }
    end
  end

  def activate_delegation(delegation)
    begin
      unless delegation.account == account
        return { success: false, errors: ["Delegation not found"] }
      end

      if delegation.revoked?
        return { success: false, errors: ["Cannot activate revoked delegation"] }
      end

      if delegation.expired?
        return { success: false, errors: ["Cannot activate expired delegation"] }
      end

      if delegation.activate!
        create_audit_log('delegation_activated', delegation)
        { success: true, delegation: delegation }
      else
        { success: false, errors: delegation.errors.full_messages }
      end
    rescue => e
      Rails.logger.error "DelegationService#activate_delegation failed: #{e.message}"
      { success: false, errors: ["Failed to activate delegation: #{e.message}"] }
    end
  end

  def deactivate_delegation(delegation)
    begin
      unless delegation.account == account
        return { success: false, errors: ["Delegation not found"] }
      end

      if delegation.revoked?
        return { success: false, errors: ["Cannot deactivate revoked delegation"] }
      end

      if delegation.deactivate!
        create_audit_log('delegation_deactivated', delegation)
        { success: true, delegation: delegation }
      else
        { success: false, errors: delegation.errors.full_messages }
      end
    rescue => e
      Rails.logger.error "DelegationService#deactivate_delegation failed: #{e.message}"
      { success: false, errors: ["Failed to deactivate delegation: #{e.message}"] }
    end
  end

  def revoke_delegation(delegation)
    begin
      unless delegation.account == account
        return { success: false, errors: ["Delegation not found"] }
      end

      if delegation.revoked?
        return { success: false, errors: ["Delegation already revoked"] }
      end

      if delegation.revoke!(delegator)
        create_audit_log('delegation_revoked', delegation)
        { success: true, delegation: delegation }
      else
        { success: false, errors: delegation.errors.full_messages }
      end
    rescue => e
      Rails.logger.error "DelegationService#revoke_delegation failed: #{e.message}"
      { success: false, errors: ["Failed to revoke delegation: #{e.message}"] }
    end
  end

  def list_available_users_for_delegation
    # Users that can be delegated to (not already members of the account)
    User.where.not(id: account.user_ids)
        .where.not(id: delegator.id)
        .active
        .order(:first_name, :last_name)
  end

  def list_available_roles_for_delegation
    # Roles that can be delegated (exclude Owner role)
    Role.where.not(name: 'Owner')
        .where(system_role: true)
        .order(:name)
  end

  def list_available_permissions_for_delegation(role_id: nil)
    if role_id.present?
      role = Role.find_by(id: role_id)
      return [] unless role && role.name != 'Owner'
      
      role.permissions.order(:resource, :action)
    else
      # Return all non-owner permissions if no role specified
      Permission.joins(:roles)
              .where.not(roles: { name: 'Owner' })
              .distinct
              .order(:resource, :action)
    end
  end

  def add_permission_to_delegation(delegation:, permission_id:)
    begin
      unless delegation.account == account
        return { success: false, errors: ["Delegation not found"] }
      end

      if delegation.revoked?
        return { success: false, errors: ["Cannot modify revoked delegation"] }
      end

      permission = Permission.find_by(id: permission_id)
      unless permission
        return { success: false, errors: ["Permission not found"] }
      end

      # Validate permission is within role scope if role is assigned
      if delegation.role.present? && !delegation.role.permissions.include?(permission)
        return { success: false, errors: ["Permission #{permission.resource}.#{permission.action} is not available in the #{delegation.role.name} role"] }
      end

      if delegation.assign_permission(permission)
        create_audit_log('delegation_permission_added', delegation, {
          permission: "#{permission.resource}.#{permission.action}"
        })
        { success: true, delegation: delegation }
      else
        { success: false, errors: ["Permission already assigned or invalid"] }
      end
    rescue => e
      Rails.logger.error "DelegationService#add_permission_to_delegation failed: #{e.message}"
      { success: false, errors: ["Failed to add permission: #{e.message}"] }
    end
  end

  def remove_permission_from_delegation(delegation:, permission_id:)
    begin
      unless delegation.account == account
        return { success: false, errors: ["Delegation not found"] }
      end

      if delegation.revoked?
        return { success: false, errors: ["Cannot modify revoked delegation"] }
      end

      permission = Permission.find_by(id: permission_id)
      unless permission
        return { success: false, errors: ["Permission not found"] }
      end

      delegation.remove_permission(permission)
      create_audit_log('delegation_permission_removed', delegation, {
        permission: "#{permission.resource}.#{permission.action}"
      })
      
      { success: true, delegation: delegation }
    rescue => e
      Rails.logger.error "DelegationService#remove_permission_from_delegation failed: #{e.message}"
      { success: false, errors: ["Failed to remove permission: #{e.message}"] }
    end
  end

  private

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
      user_agent: 'DelegationService'
    )
  rescue => e
    Rails.logger.warn "Failed to create audit log for #{action}: #{e.message}"
  end
end
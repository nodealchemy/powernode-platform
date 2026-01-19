# frozen_string_literal: true

module Auth
  class AccountSwitchService
    # Error classes
    class SwitchError < StandardError; end
    class UnauthorizedAccountError < SwitchError; end
    class InactiveAccountError < SwitchError; end
    class InactiveDelegationError < SwitchError; end

    def initialize(user)
      @user = user
      @primary_account = user.account
    end

    # Get all accounts accessible by the current user
    def accessible_accounts
      accounts = []

      # Add primary account (always accessible)
      accounts << format_account(@primary_account, "owner", true)

      # Add delegated accounts
      active_delegations.each do |delegation|
        accounts << format_account(
          delegation.account,
          delegation.role&.name || "delegated",
          false,
          delegation
        )
      end

      accounts
    end

    # Switch to a target account
    def switch_to(target_account_id, metadata: {})
      target_account = Account.find(target_account_id)

      # Check if user has access to target account
      unless has_access_to?(target_account)
        raise UnauthorizedAccountError, "You do not have access to this account"
      end

      # Check if target account is active
      unless target_account.active?
        raise InactiveAccountError, "Target account is not active"
      end

      # Get delegation if switching to delegated account
      delegation = find_delegation_for(target_account)

      # If switching to delegated account, verify delegation is still active
      if delegation && !delegation.active?
        raise InactiveDelegationError, "Your delegation to this account has expired or been revoked"
      end

      # Generate new tokens with account context
      generate_switched_tokens(target_account, delegation, metadata)
    end

    # Switch back to primary account
    def switch_to_primary(metadata: {})
      switch_to(@primary_account.id, metadata: metadata)
    end

    private

    def active_delegations
      Account::Delegation.active
                       .not_expired
                       .for_user(@user)
                       .includes(:account, :role)
    end

    def has_access_to?(account)
      return true if account.id == @primary_account.id

      active_delegations.exists?(account: account)
    end

    def find_delegation_for(account)
      return nil if account.id == @primary_account.id

      active_delegations.find_by(account: account)
    end

    def format_account(account, role_name, is_primary, delegation = nil)
      {
        id: account.id,
        name: account.name,
        subdomain: account.subdomain,
        status: account.status,
        role: role_name,
        is_primary: is_primary,
        is_current: account.id == @user.account_id,
        delegation: delegation ? {
          id: delegation.id,
          expires_at: delegation.expires_at,
          permissions: delegation.permissions_summary
        } : nil,
        subscription: account.subscription ? {
          plan_name: account.subscription.plan&.name,
          status: account.subscription.status
        } : nil
      }
    end

    def generate_switched_tokens(target_account, delegation, metadata)
      # Build the effective permissions for the user in the target account
      permissions = if delegation
        delegation.effective_permissions.map { |p| "#{p.resource}.#{p.action}" }
      else
        @user.permission_names
      end

      # Create a new token with the switched account context
      payload = {
        sub: @user.id,
        account_id: target_account.id,
        email: @user.email,
        primary_account_id: @primary_account.id,
        is_switched: target_account.id != @primary_account.id,
        delegation_id: delegation&.id,
        switched_at: Time.current.to_i
      }

      access_token = Security::JwtService.encode(payload.merge(type: "access"), metadata: metadata)
      refresh_token = Security::JwtService.encode(
        payload.slice(:sub, :account_id, :primary_account_id).merge(type: "refresh"),
        metadata: metadata
      )

      # Log the account switch
      log_account_switch(target_account, delegation)

      {
        access_token: access_token,
        refresh_token: refresh_token,
        expires_at: Security::JwtService::EXPIRATION_TIMES[:access].from_now,
        account: format_account(target_account, delegation&.role&.name || "owner", target_account.id == @primary_account.id, delegation),
        permissions: permissions,
        user: format_user(@user, target_account)
      }
    end

    def format_user(user, account)
      {
        id: user.id,
        email: user.email,
        name: user.name,
        account: {
          id: account.id,
          name: account.name,
          status: account.status
        }
      }
    end

    def log_account_switch(target_account, delegation)
      AuditLog.create!(
        account: @primary_account,
        user: @user,
        action: "account.switch",
        resource_type: "Account",
        resource_id: target_account.id,
        details: {
          target_account_id: target_account.id,
          target_account_name: target_account.name,
          delegation_id: delegation&.id,
          delegated_by_id: delegation&.delegated_by_id,
          ip_address: Current.ip_address,
          user_agent: Current.user_agent
        }
      )
    rescue StandardError => e
      Rails.logger.error "Failed to log account switch: #{e.message}"
      # Don't fail the switch if logging fails - but track the error
      # for alerting. This is intentionally swallowed.
    end
  end
end


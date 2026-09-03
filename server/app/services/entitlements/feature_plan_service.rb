# frozen_string_literal: true

module Entitlements
  # Service for managing feature plan-based role assignments and access control.
  #
  # Plan/subscription knowledge lives in an extension, injected as the
  # `:entitlements` provider (Powernode::ExtensionRegistry.provider(:entitlements)).
  # When no provider is registered the platform runs unmetered (core mode):
  #   - provider absent          → unlimited / all-features-on
  #   - provider present, no plan → restrictive defaults (unsubscribed account)
  class FeaturePlanService
    class << self
      # Check if a user can be assigned a specific role based on their account's plan
      def can_assign_role_to_user?(user, role_name)
        provider = entitlements_provider
        return true unless provider

        plan = provider.plan_for(user&.account)
        return false unless plan

        available_roles = plan.metadata&.dig("available_roles") || []
        available_roles.include?(role_name)
      end

      # Get all roles available for assignment within a plan
      def available_roles_for_plan(plan)
        available_roles = plan&.metadata&.dig("available_roles") || []
        return [] if available_roles.empty?

        Role.where(name: available_roles).includes(:role_permissions)
      end

      # Get the default roles that should be assigned to new users in this plan
      def default_roles_for_plan(plan)
        return [] unless plan&.default_roles

        Role.where(name: plan.default_roles)
      end

      # Check if a user has access to a specific feature based on their roles and plan
      def user_has_feature_access?(user, feature_permission)
        return false unless user

        # Check if user has the permission through their roles
        return true if user.has_permission?(feature_permission)

        provider = entitlements_provider
        return true unless provider

        # Check plan-level feature gates
        plan = provider.plan_for(user.account)
        return false unless plan

        check_plan_feature_gate(plan, feature_permission)
      end

      # Get feature limits for a user's plan
      def get_plan_limits(user)
        provider = entitlements_provider
        return unlimited_core_limits unless provider

        plan = provider.plan_for(user&.account)
        return default_limits unless plan&.features

        plan.features.with_defaults(default_limits)
      end

      # Check if user is within their plan limits for a specific feature
      def within_plan_limit?(user, feature, current_count)
        return true unless entitlements_provider

        limits = get_plan_limits(user)
        limit = limits["#{feature}_limit"]

        return true if limit.nil? || limit == 999999 # Unlimited

        current_count < limit
      end

      # Upgrade user roles when plan is upgraded.
      #
      # A plan's `default_roles` are free-form role NAMES on an operator-owned
      # row, so conferring them is a privilege-escalation surface, not a
      # bookkeeping step: `admin` is a GLOBAL role (account_id nil). Every name
      # is bounded by the platform's existing rule for conferring a whole role
      # (Role#assignable_by?, which RoleAssignmentGuard#can_assign_role? also
      # delegates to), so this path cannot grant authority `assigned_by` lacks.
      # `assigned_by` is required and fails closed when nil — a conferral with
      # no actor has nothing to bound it.
      def upgrade_user_roles_for_plan(user, new_plan, assigned_by: nil)
        available_roles = new_plan&.metadata&.dig("available_roles") || []
        return if available_roles.empty?

        # Get current roles
        current_roles = user.role_names

        # Get new available roles

        # If user had roles in previous plan that aren't available in new plan,
        # we keep them (grandfathering). Only add default roles if they're new.
        new_default_roles = new_plan.default_roles || []
        roles_to_add = new_default_roles - current_roles

        # Add new default roles
        roles_to_add = roles_to_add.select do |role_name|
          role = Role.find_by(name: role_name)
          next false unless role&.assignable_by?(assigned_by)

          user.roles << role unless user.roles.include?(role)
          true
        end

        user.save! if roles_to_add.any?

        {
          roles_added: roles_to_add,
          roles_available: available_roles,
          roles_current: user.reload.role_names
        }
      end

      # Remove roles that are no longer available when plan is downgraded
      # Removal needs no escalation check; the ADDITIVE half at the end does, for
      # the same reason as #upgrade_user_roles_for_plan.
      def downgrade_user_roles_for_plan(user, new_plan, assigned_by: nil)
        return unless new_plan

        current_roles = user.role_names
        available_roles = new_plan&.metadata&.dig("available_roles") || []

        # Remove roles that are no longer available in the new plan
        roles_to_remove = current_roles - available_roles

        roles_to_remove.each do |role_name|
          role = Role.find_by(name: role_name)
          user.roles.delete(role) if role
        end

        # Ensure user has at least the default roles for new plan
        default_roles = new_plan.default_roles || []
        default_roles.each do |role_name|
          role = Role.find_by(name: role_name)
          next unless role&.assignable_by?(assigned_by)

          user.roles << role unless user.roles.include?(role)
        end

        user.save!

        {
          roles_removed: roles_to_remove,
          roles_available: available_roles,
          roles_current: user.reload.role_names
        }
      end

      # Get a summary of what features/roles each plan provides
      def plan_comparison_matrix
        provider = entitlements_provider
        return [] unless provider

        plans = provider.plan_catalog
        return [] if plans.blank?

        plans.map do |plan|
          available_permissions = available_roles_for_plan(plan)
                                  .flat_map(&:permissions)
                                  .pluck(:name)
                                  .uniq
                                  .sort

          {
            plan_name: plan.name,
            price_monthly: plan.price_cents / 100.0,
            available_roles: plan.metadata&.dig("available_roles") || [],
            default_roles: plan.default_roles || [],
            permissions_count: available_permissions.count,
            key_permissions: available_permissions,
            limits: plan.features || {},
            active_subscriptions: plan.subscriptions.active.count
          }
        end
      end

      # Generate a user's feature access report
      def user_feature_report(user)
        return {} unless user&.account

        provider = entitlements_provider
        return core_mode_feature_report(user) unless provider

        plan = provider.plan_for(user.account)
        user_roles = user.roles.includes(:role_permissions)
        user_permissions = user.permission_names

        {
          user: {
            id: user.id,
            name: user.full_name,
            email: user.email
          },
          account: {
            id: user.account.id,
            name: user.account.name
          },
          plan: plan ? {
            name: plan.name,
            price: plan.price_cents / 100.0,
            available_roles: plan.metadata&.dig("available_roles") || [],
            limits: plan.features
          } : nil,
          current_roles: user_roles.map { |role|
            {
              name: role.name,
              permissions: role.permission_names
            }
          },
          total_permissions: user_permissions.count,
          feature_access: {
            can_manage_team: user_permissions.include?("team.assign_roles"),
            can_manage_billing: user_permissions.include?("billing.update"),
            can_use_api: user_permissions.include?("api.write"),
            can_manage_webhooks: user_permissions.include?("webhook.create"),
            can_export_analytics: user_permissions.include?("analytics.export"),
            can_view_audit_logs: user_permissions.include?("audit.view")
          },
          plan_limits: get_plan_limits(user)
        }
      end

      private

      # The injected entitlements policy (plan/limits/roles), or nil in core mode.
      def entitlements_provider
        Powernode::ExtensionRegistry.provider(:entitlements)
      end

      def check_plan_feature_gate(plan, permission)
        # This could be extended to check plan.features for specific feature gates
        # For now, we rely on role-based permissions
        false
      end

      def unlimited_core_limits
        {
          "pages_limit" => 999999,
          "api_calls_per_month" => 999999,
          "team_members_limit" => 999999,
          "webhooks_limit" => 999999,
          "support_level" => "full"
        }
      end

      def core_mode_feature_report(user)
        {
          user: { id: user.id, name: user.full_name, email: user.email },
          account: { id: user.account.id, name: user.account.name },
          plan: nil,
          current_roles: user.roles.map { |role|
            { name: role.name, permissions: role.permission_names }
          },
          total_permissions: user.permission_names.count,
          feature_access: {
            can_manage_team: true, can_manage_billing: false,
            can_use_api: true, can_manage_webhooks: true,
            can_export_analytics: true, can_view_audit_logs: true
          },
          plan_limits: unlimited_core_limits
        }
      end

      def default_limits
        {
          "pages_limit" => 5,
          "api_calls_per_month" => 1000,
          "team_members_limit" => 3,
          "webhooks_limit" => 0,
          "support_level" => "community"
        }
      end
    end
  end
end

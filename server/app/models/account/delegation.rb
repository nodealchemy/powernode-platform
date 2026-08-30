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
    # to the ROLE's full set, so emptying the custom set WIDENS the delegation.
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
    def configured_permissions_for(custom)
      custom = Array(custom)
      return custom if custom.any?

      role&.permission_names || []
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

      delegation_permissions.create(permission_name: permission_name)
      true
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

# frozen_string_literal: true

require_relative "../../config/permissions"

class Role < ApplicationRecord
  # Associations
  # account_id nil => global (code-defined, catalog-seeded) role shared across
  # all accounts; account_id set => account-scoped custom role (customizable).
  belongs_to :account, optional: true
  has_many :role_permissions, dependent: :delete_all
  has_many :user_roles, dependent: :destroy
  has_many :users, through: :user_roles
  has_many :worker_roles, dependent: :destroy
  has_many :workers, through: :worker_roles

  # Validations
  validates :name, presence: true, uniqueness: { scope: :account_id }, format: {
    with: /\A[a-z_.]+\z/,
    message: "must be lowercase with underscores or dots only"
  }
  validates :display_name, presence: true
  validates :role_type, presence: true, inclusion: { in: %w[user admin system] }
  validates :immutable, inclusion: { in: [ true, false ] }
  # Account-scoped roles must not shadow a global role name (avoids ambiguity)
  validate :account_role_name_not_shadowing_global

  # Scopes
  scope :global, -> { where(account_id: nil) }
  scope :account_scoped, -> { where.not(account_id: nil) }
  scope :owned_by_account, ->(account_id) { where(account_id: account_id) }
  scope :for_account, ->(account_id) { where(account_id: [ nil, account_id ]) }
  scope :user_roles, -> { where(role_type: "user") }
  scope :admin_roles, -> { where(role_type: "admin") }
  scope :system_roles, -> { where(role_type: "system") }
  scope :non_system, -> { where(is_system: false) }
  scope :mutable, -> { where(immutable: false) }
  scope :immutable, -> { where(immutable: true) }

  # Callbacks
  # Disabled to prevent conflicts during seeding
  # after_create :sync_permissions_from_config
  before_destroy :prevent_super_admin_deletion
  before_update :prevent_super_admin_modification

  # Class methods
  class << self
    def sync_from_config!
      # all_roles = core ROLES + enabled-extension roles (register_roles).
      # Extension roles seed as GLOBAL (account_id nil) when their extension is
      # loaded; a disabled extension contributes none. Names no extension.
      Permissions.all_roles.each do |name, config|
        # Catalog roles are GLOBAL (account_id nil); account-scoped roles are
        # created at runtime via the API and are never seeded here.
        role = find_or_initialize_by(name: name, account_id: nil)
        attrs = {
          display_name: config[:display_name],
          description: config[:description],
          role_type: config[:role_type],
          is_system: config[:is_system] || config[:role_type] == "system",
          immutable: config[:immutable] || false
        }

        if role.new_record?
          role.assign_attributes(attrs)
          begin
            role.save!
          rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
            role = find_by!(name: name, account_id: nil)
            role.update!(attrs) unless role.immutable?
          end
        elsif !role.immutable?
          role.update!(attrs)
        end

        # Sync permissions — Permissions.permissions_for_role merges the
        # static config with extension-registered grants so extension
        # permissions (registered via engine initializers) survive db:seed.
        role.sync_permissions!(Permissions.permissions_for_role(name.to_s))
      end
    end

    def find_by_name(name, account_id: nil)
      find_by(name: name.to_s, account_id: account_id)
    end
  end

  # Instance methods
  def user_role?
    role_type == "user"
  end

  def admin_role?
    role_type == "admin"
  end

  def system_role?
    role_type == "system"
  end

  def super_admin?
    name == "super_admin"
  end

  def immutable?
    immutable || super_admin?
  end

  def add_permission(permission_name)
    return if role_permissions.exists?(permission_name: permission_name)

    role_permissions.create!(permission_name: permission_name)
  end

  def remove_permission(permission_name)
    role_permissions.where(permission_name: permission_name).delete_all
  end

  def has_permission?(permission_name)
    # Roles granted system.admin have all permissions programmatically
    return true if role_permissions.exists?(permission_name: "system.admin")

    role_permissions.exists?(permission_name: permission_name)
  end

  def permission_names
    # Roles granted system.admin have all permissions programmatically
    return Permissions.all_permissions.keys.sort if role_permissions.exists?(permission_name: "system.admin")

    role_permissions.pluck(:permission_name).uniq.sort
  end

  # THE privilege-escalation rule for CONFERRING A WHOLE ROLE.
  #
  # It lives on the model rather than only in RoleAssignmentGuard because role
  # conferral also happens outside controllers — plan `default_roles` appliers,
  # services, extensions — and those callers have no `current_user`. Restating
  # the rule there is what the guard's own header warns about: two copies drift,
  # and the weaker one becomes the way in. RoleAssignmentGuard#can_assign_role?
  # now delegates here, so RolesController#assign_to_user,
  # Admin::UsersController#update, DelegationsController and every non-controller
  # caller answer the same question with the same code.
  #
  # NOT to be confused with User#grantable_permission_names / #can_grant_permission?,
  # which govern a list of permission NAMES. Conferring a role is a different
  # question with a different rule (see Accounts::DelegationService's note).
  #
  # Fails closed: with no actor, nothing is assignable.
  #
  # THE SUBSET TEST HAS NO ADMIN EXEMPTION (IMP-1635cb7fa768). It used to open
  # with `return true if Role.assignment_admin?(user)`, which admits any
  # admin.access holder — so an `admin` could confer `super_admin`, whose single
  # grant `system.admin` short-circuits User#has_permission? to true for EVERY
  # name. Conferring authority the caller does not itself hold is the one thing
  # this guard exists to stop, so exempting the broadest case made it advisory.
  # Fixing it here rather than at a call site is what makes RolesController,
  # Admin::UsersController, the delegation channel and the plan appliers all
  # inherit the correction.
  #
  # What survives is a bypass gated on something strictly ABOVE any role:
  # `system.admin` itself. That is not a hole — a system.admin holder already
  # holds every permission by definition, so the subset test would admit it
  # anyway; the short-circuit only avoids materialising a whole-catalog set to
  # prove it. It is also the CORRECT predicate rather than a cheaper one: a
  # system.admin user's #permission_names answers the RUNNING PROCESS's catalog,
  # so comparing against it would refuse a role carrying an extension permission
  # in a process where that extension is not loaded. Account::Delegation
  # #configured_permissions_for documents the same divergence.
  #
  # NO LOCKOUT for the ordinary operator: measured against the real seeded
  # roles, `admin` holds every grant on `admin`, `owner`, `manager`, `member`,
  # `developer`, `content_manager` and `ai_specialist`, so it confers all of
  # them exactly as before. What it loses is `super_admin` and the worker roles
  # — every one of which carries system.* grants an admin does not hold, which
  # is precisely the escalation being closed. Worker provisioning is unaffected:
  # that goes through #grant_to_worker, not this predicate.
  def assignable_by?(user)
    return false if user.nil?
    return false if system_role? && !Role.assignment_admin?(user)
    return true if user.has_permission?("system.admin")

    user_permissions = user.permission_names
    permission_names.all? { |perm| user_permissions.include?(perm) }
  end

  # Who may reach the SYSTEM-ROLE tier at all. This is the whole of what the
  # old "admin bypass" still governs: it no longer exempts anyone from the
  # subset test (see #assignable_by?), it only decides whether a role_type
  # "system" role is refused outright before the subset test is even asked.
  # An admin.access holder therefore reaches the question but still has to hold
  # the role's grants to pass it. The set lives here so a change applies to
  # every conferral site at once.
  def self.assignment_admin?(user)
    return false if user.nil?

    user.has_permission?("system.admin") || user.has_permission?("admin.access")
  end

  # Destructively reconcile this role's grants to the given catalog permission
  # names. Used by Role.sync_from_config! for GLOBAL (code-defined) roles, whose
  # grants are owned by the catalog. Account-scoped roles are NOT synced here —
  # they are edited through the API and persist independently.
  def sync_permissions!(permission_names)
    return unless permission_names.is_a?(Array)

    # Only catalog-defined permissions are grantable; drop any unknown names
    # (e.g. a permission removed from the catalog) so stale grants prune.
    desired = permission_names.uniq.select { |name| Permissions.permission_exists?(name) }
    current = role_permissions.pluck(:permission_name)

    to_remove = current - desired
    role_permissions.where(permission_name: to_remove).delete_all if to_remove.any?

    (desired - current).each do |name|
      role_permissions.find_or_create_by!(permission_name: name)
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      # Already exists (race) or rejected by validation — ignore.
    end
  end

  def grant_to_user(user, granted_by = nil)
    UserRole.find_or_create_by!(
      user: user,
      role: self
    ) do |ur|
      # `granted_by` is the granting User (see User#assign_role), not an id —
      # assign the association (UserRole#granted_by_user, FK granted_by_id).
      # There is no `granted_by` attribute on UserRole; that writer never
      # existed and raised NoMethodError on every new attributed grant.
      ur.granted_by_user = granted_by
    end
  end

  def revoke_from_user(user)
    user_roles.where(user: user).destroy_all
  end

  def grant_to_worker(worker)
    WorkerRole.find_or_create_by!(
      worker: worker,
      role: self
    )
  end

  def revoke_from_worker(worker)
    worker_roles.where(worker: worker).destroy_all
  end

  private

  def sync_permissions_from_config
    config = Permissions.all_roles[name]
    return unless config

    sync_permissions!(config[:permissions]) if config[:permissions]
  end

  def account_role_name_not_shadowing_global
    return if account_id.nil? # global roles define the canonical names
    return if name.blank?

    errors.add(:name, "is reserved by a global role") if Role.global.where(name: name).exists?
  end

  def prevent_super_admin_deletion
    if super_admin?
      errors.add(:base, "Super admin role cannot be deleted")
      throw :abort
    end

    # Ensure at least one super_admin user exists before allowing deletion
    if name == "super_admin" && User.joins(:roles).where(roles: { name: "super_admin" }).count <= 1
      errors.add(:base, "Cannot delete super_admin role - at least one super admin user must exist")
      throw :abort
    end
  end

  def prevent_super_admin_modification
    if immutable? && (changed? - [ "updated_at" ])
      errors.add(:base, "Immutable role cannot be modified")
      throw :abort
    end
  end
end

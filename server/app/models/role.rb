# frozen_string_literal: true

require_relative "../../config/permissions"

class Role < ApplicationRecord
  # Associations
  has_many :role_permissions, dependent: :delete_all
  has_many :permissions, through: :role_permissions
  has_many :user_roles, dependent: :destroy
  has_many :users, through: :user_roles
  has_many :worker_roles, dependent: :destroy
  has_many :workers, through: :worker_roles

  # Validations
  validates :name, presence: true, uniqueness: true, format: {
    with: /\A[a-z_.]+\z/,
    message: "must be lowercase with underscores or dots only"
  }
  validates :display_name, presence: true
  validates :role_type, presence: true, inclusion: { in: %w[user admin system] }
  validates :immutable, inclusion: { in: [ true, false ] }

  # Scopes
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
      Permissions::ROLES.each do |name, config|
        role = find_or_initialize_by(name: name)
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
            role = find_by!(name: name)
            role.update!(attrs) unless role.immutable?
          end
        elsif !role.immutable?
          role.update!(attrs)
        end

        # Sync permissions
        role.sync_permissions!(config[:permissions])
      end
    end

    def find_by_name(name)
      find_by(name: name.to_s)
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
    permission = Permission.find_or_create_from_name!(permission_name)
    permissions << permission unless permissions.include?(permission)
  end

  def remove_permission(permission_name)
    permission = Permission.find_by(name: permission_name)
    permissions.delete(permission) if permission
  end

  def has_permission?(permission_name)
    # Roles with system.admin permission have all permissions programmatically
    return true if permissions.exists?(name: "system.admin")

    permissions.exists?(name: permission_name)
  end

  def permission_names
    # Roles with system.admin permission have all permissions programmatically
    return Permissions::ALL_PERMISSIONS.keys.sort if permissions.exists?(name: "system.admin")

    permissions.pluck(:name).sort
  end

  def sync_permissions!(permission_names)
    return unless permission_names.is_a?(Array)

    # Deduplicate permission names first, then get or create all permissions
    new_permissions = permission_names.uniq.filter_map do |name|
      Permission.find_or_create_from_name!(
        name,
        Permissions::ALL_PERMISSIONS[name]
      )
    end

    # Get unique permission IDs we want
    desired_ids = new_permissions.map(&:id).uniq
    current_ids = role_permissions.pluck(:permission_id)

    # Remove permissions no longer needed
    ids_to_remove = current_ids - desired_ids
    role_permissions.where(permission_id: ids_to_remove).delete_all if ids_to_remove.any?

    # Add new permissions not yet assigned
    ids_to_add = desired_ids - current_ids
    ids_to_add.each do |pid|
      role_permissions.find_or_create_by!(permission_id: pid)
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      # Already exists (caught by DB constraint or model validation), ignore
    end
  end

  def grant_to_user(user, granted_by = nil)
    UserRole.find_or_create_by!(
      user: user,
      role: self
    ) do |ur|
      ur.granted_by = granted_by&.id
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
    return unless Permissions::ROLES[name]

    config = Permissions::ROLES[name]
    sync_permissions!(config[:permissions]) if config[:permissions]
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

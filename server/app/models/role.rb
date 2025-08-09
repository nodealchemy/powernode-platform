class Role < ApplicationRecord
  # Associations
  has_many :role_permissions, dependent: :destroy
  has_many :permissions, through: :role_permissions
  has_many :user_roles, dependent: :destroy
  has_many :users, through: :user_roles

  # Validations
  validates :name, presence: true, uniqueness: { case_sensitive: false }, length: { minimum: 2, maximum: 50 }
  validates :description, length: { maximum: 255 }

  # Scopes
  scope :system_roles, -> { where(system_role: true) }
  scope :custom_roles, -> { where(system_role: false) }

  # Callbacks
  before_validation :normalize_name

  # Instance methods
  def system_role?
    system_role
  end

  def has_permission?(permission_name)
    permissions.exists?(name: permission_name)
  end

  def add_permission(permission)
    permissions << permission unless has_permission?(permission.name)
  end

  def remove_permission(permission)
    permissions.delete(permission)
  end

  private

  def normalize_name
    self.name = name&.strip&.titleize
  end
end

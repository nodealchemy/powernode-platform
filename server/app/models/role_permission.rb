class RolePermission < ApplicationRecord
  # Associations
  belongs_to :role
  belongs_to :permission

  # Validations
  validates :role_id, uniqueness: { scope: :permission_id }
end

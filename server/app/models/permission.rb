class Permission < ApplicationRecord
  # Associations
  has_many :role_permissions, dependent: :destroy
  has_many :roles, through: :role_permissions

  # Validations
  validates :name, presence: true, uniqueness: { case_sensitive: false }, length: { minimum: 2, maximum: 100 }
  validates :resource, presence: true, length: { minimum: 2, maximum: 50 }
  validates :action, presence: true, length: { minimum: 2, maximum: 50 }
  validates :description, length: { maximum: 255 }
  validates :resource, uniqueness: { scope: :action }

  # Scopes
  scope :for_resource, ->(resource) { where(resource: resource) }
  scope :for_action, ->(action) { where(action: action) }

  # Callbacks
  before_validation :normalize_attributes
  before_validation :generate_name

  # Instance methods
  def full_name
    "#{resource}.#{action}"
  end

  private

  def normalize_attributes
    self.resource = resource&.strip&.downcase
    self.action = action&.strip&.downcase
  end

  def generate_name
    self.name = full_name if name.blank?
  end
end

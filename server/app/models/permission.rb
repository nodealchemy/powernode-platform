# frozen_string_literal: true

require_relative '../../config/permissions'

class Permission < ApplicationRecord
  # Associations
  has_many :role_permissions, dependent: :delete_all
  has_many :roles, through: :role_permissions
  
  # Validations
  validates :name, uniqueness: true, length: { in: 2..100 }, allow_blank: true
  validates :resource, presence: true, length: { in: 2..50 }
  validates :action, presence: true, length: { in: 2..50 }
  validates :description, length: { maximum: 255 }, allow_blank: true
  validates :category, presence: true, inclusion: { in: %w[resource admin system] }
  validate :validate_resource_action_uniqueness
  
  # Scopes
  scope :resource_permissions, -> { where(category: 'resource') }
  scope :admin_permissions, -> { where(category: 'admin') }
  scope :system_permissions, -> { where(category: 'system') }
  scope :by_resource, ->(resource) { where(resource: resource) }
  scope :by_action, ->(action) { where(action: action) }
  scope :for_resource, ->(resource) { where(resource: resource) }
  scope :for_action, ->(action) { where(action: action) }
  
  # Callbacks
  before_validation :normalize_attributes
  before_validation :generate_name
  before_validation :extract_components_from_name
  before_validation :set_default_category
  
  # Class methods
  class << self
    def find_or_create_from_name!(name, description = nil)
      # Ensure name is a string
      name = name.to_s if name.respond_to?(:to_s)
      
      # First try to find by name
      permission = find_by(name: name)
      return permission if permission
      
      # Extract components
      parts = name.split('.')
      category = determine_category(parts)
      resource, action = extract_resource_action(parts, category)
      
      # Try to find by resource, action AND category to avoid conflicts
      permission = find_by(resource: resource, action: action, category: category)
      if permission
        # Update the name if it doesn't match
        permission.update!(name: name) if permission.name != name
        return permission
      end

      # Create new permission with race-safe find_or_create_by!
      # Use rescue to handle race conditions where another thread creates between find and create
      begin
        create!(
          name: name,
          category: category,
          resource: resource,
          action: action,
          description: description || "Permission for #{name}"
        )
      rescue ActiveRecord::RecordNotUnique
        # Another thread created it, find and return
        find_by(name: name) || find_by(resource: resource, action: action, category: category)
      end
    end
    
    def sync_from_config!
      Permissions::ALL_PERMISSIONS.each do |name, description|
        find_or_create_from_name!(name, description)
      end
    end
    
    private
    
    def determine_category(parts)
      return 'admin' if parts[0] == 'admin'
      return 'system' if parts[0] == 'system'
      'resource'
    end
    
    def extract_resource_action(parts, category)
      case category
      when 'admin', 'system'
        # Format: admin.resource.action or system.resource.action
        if parts.length >= 3
          # admin.ai.agents.delete -> resource: ai.agents, action: delete
          resource = parts[1..-2].join('.')  # Everything except first and last part
          action = parts[-1]  # Last part
        else
          # admin.access -> resource: admin, action: access
          resource = parts[0]
          action = parts[1]
        end
      else
        # Format: resource.action (e.g., ai.agents.create, user.read)
        if parts.length >= 3 && parts[0] == 'ai'
          # ai.agents.create -> resource: agents, action: create
          resource = parts[1]
          action = parts[2]
        else
          # user.read -> resource: user, action: read
          # api.manage_keys -> resource: api, action: manage_keys
          resource = parts[0]
          action = parts[1..].join('_')
        end
      end
      
      [resource, action]
    end
  end
  
  # Instance methods
  def resource_permission?
    category == 'resource'
  end
  
  def admin_permission?
    category == 'admin'
  end
  
  def system_permission?
    category == 'system'
  end
  
  def full_name
    "#{resource}.#{action}"
  end
  
  def display_name
    "#{resource.humanize} - #{action.humanize}"
  end
  
  private
  
  def normalize_attributes
    self.resource = resource.to_s.downcase.strip if resource.present?
    self.action = action.to_s.downcase.strip if action.present?
  end
  
  def generate_name
    if name.blank? && resource.present? && action.present?
      self.name = "#{resource}.#{action}"
    end
  end
  
  def extract_components_from_name
    return unless name.present?
    return if resource.present? && action.present?
    
    parts = name.split('.')
    self.category ||= self.class.send(:determine_category, parts)
    
    resource, action = self.class.send(:extract_resource_action, parts, category)
    self.resource ||= resource
    self.action ||= action
  end
  
  def validate_resource_action_uniqueness
    if resource.present? && action.present? && category.present?
      # Allow same resource/action combination if categories are different
      existing = Permission.where(resource: resource, action: action, category: category)
      existing = existing.where.not(id: id) if persisted?
      if existing.exists?
        errors.add(:resource, 'and action combination has already been taken for this category')
        errors.add(:base, 'Permission with this resource, action, and category already exists')
      end
    end
  end
  
  def set_default_category
    if category.blank? && (resource.present? || name.present?)
      # Try to determine from name first
      if name.present?
        parts = name.split('.')
        self.category = self.class.send(:determine_category, parts)
      else
        # Default to resource if we can't determine
        self.category = 'resource'
      end
    end
  end
end
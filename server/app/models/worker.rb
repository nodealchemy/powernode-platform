# frozen_string_literal: true

# Worker Authentication Model
# Manages individual workers with their own tokens and permissions
class Worker < ApplicationRecord
  self.table_name = 'workers'
  include AASM
  
  # Validations
  validates :name, presence: true, length: { minimum: 3, maximum: 50 }
  validates :description, length: { maximum: 255 }
  validates :token, presence: true, uniqueness: true, on: :update
  validates :token, uniqueness: true, allow_blank: true, on: :create
  # Permissions now handled through roles
  validates :status, presence: true
  # Role field will be deprecated - roles now handled through worker_roles association
  validate :only_one_system_worker_globally
  
  # Associations
  belongs_to :account, optional: true  # System workers don't belong to an account
  has_many :worker_roles, dependent: :destroy
  has_many :roles, through: :worker_roles
  has_many :worker_activities, dependent: :destroy
  
  # Permissions are now inherited through roles, not directly assigned
  
  # State machine for status
  aasm column: 'status' do
    state :active, initial: true
    state :suspended
    state :revoked
    
    event :suspend do
      transitions from: :active, to: :suspended
      after do
        log_status_change('suspended')
      end
    end
    
    event :activate do
      transitions from: [:suspended], to: :active
      after do
        log_status_change('activated')
      end
    end
    
    event :revoke do
      transitions from: [:active, :suspended], to: :revoked
      after do
        log_status_change('revoked')
      end
    end
  end
  
  # Scopes
  scope :active, -> { where(status: 'active') }
  scope :for_account, ->(account) { where(account: account) }
  scope :by_permission, ->(perm) { where(permissions: perm) }
  scope :system_worker, -> { where(role: 'system') }
  scope :account_workers, -> { where(role: 'account') }
  
  # Callbacks
  before_create :generate_token
  before_save :update_last_activity
  after_create :log_creation
  
  # Class methods
  def self.authenticate(token)
    return nil if token.blank?
    
    worker = find_by(token: token, status: 'active')
    return nil unless worker
    
    worker.touch(:last_seen_at)
    worker.increment!(:request_count)
    worker
  end
  
  def self.create_worker!(name:, description: nil, permissions: 'standard', account: nil, role: 'account')
    worker = create!(
      name: name,
      description: description,
      permissions: permissions,
      account: account,
      token: generate_secure_token,
      status: 'active',
      role: role
    )
    
    worker
  end
  
  def self.system_worker
    find_by(role: 'system')
  end
  
  # Permission checking methods (similar to User model)
  def has_role?(role_name)
    roles.joins(:worker_roles).where('worker_roles.expires_at IS NULL OR worker_roles.expires_at > ?', Time.current)
         .exists?(name: role_name)
  end
  
  def has_permission?(permission_name)
    # Check permissions through all active roles
    worker_roles.active.includes(role: :permissions).any? do |worker_role|
      worker_role.role.has_permission?(permission_name)
    end
  end
  
  def assign_role(role_or_name, assigned_by: nil, expires_at: nil)
    role = role_or_name.is_a?(Role) ? role_or_name : Role.find_by!(name: role_or_name)
    
    worker_roles.create!(
      role: role,
      assigned_by: assigned_by,
      expires_at: expires_at
    )
  end
  
  def remove_role(role_or_name)
    role = role_or_name.is_a?(Role) ? role_or_name : Role.find_by!(name: role_or_name)
    worker_roles.where(role: role).destroy_all
  end
  
  def all_permissions
    # Aggregate permissions from all active roles
    Permission.joins(role_permissions: { role: :worker_roles })
             .where(worker_roles: { worker_id: id })
             .where('worker_roles.expires_at IS NULL OR worker_roles.expires_at > ?', Time.current)
             .distinct
  end
  
  def active_roles
    worker_roles.active.includes(:role)
  end
  
  def role_names
    roles.joins(:worker_roles).where('worker_roles.expires_at IS NULL OR worker_roles.expires_at > ?', Time.current)
         .pluck(:name)
  end
  
  def can_access?(resource_type, action = :read)
    return false unless active?
    
    # Check through permission system
    permission_name = "#{resource_type}.#{action}"
    has_permission?(permission_name)
  end
  
  def regenerate_token!
    update!(
      token: self.class.generate_secure_token,
      token_regenerated_at: Time.current
    )
    log_token_regeneration
    token
  end
  
  def record_activity!(action, details = {})
    worker_activities.create!(
      action: action,
      details: details,
      performed_at: Time.current,
      ip_address: details[:ip_address],
      user_agent: details[:user_agent]
    )
  end
  
  def last_activity
    worker_activities.order(:performed_at).last
  end
  
  def active_in_last_hours(hours = 24)
    last_seen_at && last_seen_at > hours.hours.ago
  end
  
  def display_name
    "#{name} (#{account.name})"
  end
  
  def masked_token
    return '' if token.blank?
    "#{token[0..7]}#{'*' * (token.length - 12)}#{token[-4..-1]}"
  end
  
  def system?
    has_role?('system_worker') || has_role?('super_admin')
  end
  
  def account?
    !system?
  end
  
  private
  
  def generate_token
    self.token = self.class.generate_secure_token if token.blank?
  end
  
  def self.generate_secure_token
    "swt_#{SecureRandom.urlsafe_base64(32)}"
  end
  
  def update_last_activity
    self.last_seen_at = Time.current if status_changed? && active?
  end
  
  def log_creation
    # Only log if account exists (system workers might not have an account)
    return unless account.present?
    
    AuditLog.create!(
      user: nil, # System created
      account: account,
      action: 'create',
      resource_type: 'Worker',
      resource_id: id,
      source: 'system',
      new_values: {
        name: name,
        status: status
      },
      metadata: {
        worker_type: 'authentication_worker'
      }
    )
  end
  
  def log_status_change(new_status)
    AuditLog.create!(
      user: nil, # System change
      account: account,
      action: 'update',
      resource_type: 'Worker',
      resource_id: id,
      source: 'system',
      old_values: { status: status_was },
      new_values: { status: new_status },
      metadata: {
        status_change: true,
        changed_at: Time.current.iso8601
      }
    )
  end
  
  def log_token_regeneration
    return unless account.present?
    
    AuditLog.create!(
      user: nil,
      account: account,
      action: 'update',
      resource_type: 'Worker',
      resource_id: id,
      source: 'system',
      new_values: {
        token_regenerated_at: token_regenerated_at.iso8601
      },
      metadata: {
        token_regeneration: true
      }
    )
  end
  
  def only_one_system_worker_globally
    # Check if this worker has or will have system_worker role
    return unless name == 'Powernode System Worker'
    
    # Check through the roles association
    system_worker_role = Role.find_by(name: 'system_worker')
    return unless system_worker_role
    
    existing_system = Worker.joins(:roles).where(roles: { id: system_worker_role.id }).where.not(id: id).first
    if existing_system
      errors.add(:base, "Only one system worker is allowed globally")
    end
  end
end
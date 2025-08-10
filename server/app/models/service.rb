# Service Authentication Model
# Manages individual services with their own tokens and permissions
class Service < ApplicationRecord
  include AASM
  
  # Validations
  validates :name, presence: true, length: { minimum: 3, maximum: 50 }
  validates :description, length: { maximum: 255 }
  validates :token, presence: true, uniqueness: true
  validates :permissions, presence: true
  validates :status, presence: true
  
  # Associations
  belongs_to :account
  has_many :service_activities, dependent: :destroy
  
  # Enums
  enum :permissions, {
    readonly: 'readonly',           # Can only read data via API
    standard: 'standard',           # Can process jobs and read/write data
    admin: 'admin',                 # Can manage jobs and access admin functions
    super_admin: 'super_admin'      # Full access including service management
  }, prefix: :permission
  
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
  
  def self.create_service!(name:, description: nil, permissions: 'standard', account: nil)
    create!(
      name: name,
      description: description,
      permissions: permissions,
      account: account,
      token: generate_secure_token,
      status: 'active'
    )
  end
  
  # Instance methods
  def can_access?(resource_type, action = :read)
    return false unless active?
    
    case permissions.to_sym
    when :readonly
      action == :read
    when :standard
      [:read, :write, :process_jobs].include?(action.to_sym)
    when :admin
      [:read, :write, :process_jobs, :manage_jobs, :admin_functions].include?(action.to_sym)
    when :super_admin
      true # Full access
    else
      false
    end
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
    service_activities.create!(
      action: action,
      details: details,
      performed_at: Time.current,
      ip_address: details[:ip_address],
      user_agent: details[:user_agent]
    )
  end
  
  def last_activity
    service_activities.order(:performed_at).last
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
    AuditLog.create!(
      user: nil, # System created
      account: account,
      action: 'create',
      resource_type: 'Service',
      resource_id: id,
      source: 'system',
      new_values: {
        name: name,
        permissions: permissions
      },
      metadata: {
        service_type: 'authentication_service'
      }
    )
  end
  
  def log_status_change(new_status)
    AuditLog.create!(
      user: nil, # System change
      account: account,
      action: 'update',
      resource_type: 'Service',
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
    AuditLog.create!(
      user: nil,
      account: account,
      action: 'update',
      resource_type: 'Service',
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
end
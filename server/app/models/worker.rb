# frozen_string_literal: true

# Worker Authentication Model
# Manages individual workers with their own tokens and permissions
class Worker < ApplicationRecord
  self.table_name = "workers"
  include AASM

  # Virtual attributes
  attr_accessor :token

  # Method alias for test compatibility
  def auth_token
    token
  end

  # Validations
  validates :name, presence: true, length: { minimum: 3, maximum: 50 }
  validates :description, length: { maximum: 255 }
  validates :token_digest, presence: true, on: :update
  validates :status, presence: true
  validates :account, presence: true
  validate :only_one_system_worker_globally

  # Associations
  belongs_to :account
  has_many :worker_activities, dependent: :destroy
  has_many :worker_roles, dependent: :destroy
  has_many :roles, through: :worker_roles

  # Permissions are derived from assigned roles

  # State machine for status
  aasm column: "status" do
    state :active, initial: true
    state :suspended
    state :revoked

    event :suspend do
      transitions from: :active, to: :suspended
      after do
        log_status_change("suspended")
      end
    end

    event :activate do
      transitions from: [ :suspended ], to: :active
      after do
        log_status_change("activated")
      end
    end

    event :revoke do
      transitions from: [ :active, :suspended ], to: :revoked
      after do
        log_status_change("revoked")
      end
    end
  end

  # Scopes
  scope :active, -> { where(status: "active") }
  scope :for_account, ->(account) { where(account: account) }
  scope :with_permission, ->(perm) { joins(roles: :permissions).where(permissions: { name: perm }) }
  scope :system_workers, -> { where(is_system: true) }
  scope :account_workers, -> { where(is_system: false) }

  # Callbacks
  before_create :generate_token
  before_save :update_last_activity
  after_create :log_creation

  # Class methods
  def self.authenticate(token, update_last_seen: true)
    return nil if token.blank?

    # Hash the provided token to compare with stored digest
    token_digest = Digest::SHA256.hexdigest(token)
    worker = where(status: "active", token_digest: token_digest).first
    return nil unless worker

    # Only update last_seen_at when explicitly requested (not for cached verifications)
    worker.touch(:last_seen_at) if update_last_seen
    worker
  end

  def self.authenticate_without_touch(token)
    authenticate(token, update_last_seen: false)
  end

  def self.create_worker!(name:, description: nil, roles: [], account: nil, token: nil, is_system: false)
    # Generate token if not provided
    token ||= generate_secure_token

    worker = create!(
      name: name,
      description: description,
      account: account,
      is_system: is_system,
      token_digest: Digest::SHA256.hexdigest(token),
      status: "active"
    )

    # Set virtual attribute for return
    worker.token = token

    # Assign roles if provided, with validation
    Array(roles).each do |role_name|
      unless worker.assign_role(role_name)
        worker.errors.add(:roles, "Role '#{role_name}' is not compatible with #{worker.system? ? 'system' : 'account'} workers")
        worker.destroy! # Clean up if role assignment fails
        raise ActiveRecord::RecordInvalid.new(worker)
      end
    end

    worker
  end

  def self.system_worker
    system_workers.first
  end

  # Permission checking methods - role-based permissions
  def has_role?(role_name)
    roles.exists?(name: role_name.to_s)
  end

  def has_permission?(permission_name)
    return false unless active?

    # Get all permissions from all assigned roles
    roles.joins(:permissions)
         .where(permissions: { name: permission_name.to_s })
         .exists?
  end

  def assign_role(role_name)
    role = Role.find_by(name: role_name.to_s)
    return false unless role

    # Validate role type is appropriate for workers
    unless valid_worker_role?(role)
      Rails.logger.warn "Invalid role assignment: #{role_name} (#{role.role_type}) cannot be assigned to worker"
      return false
    end

    worker_roles.find_or_create_by(role: role)
    true
  end

  def assign_roles(role_names)
    Array(role_names).each { |role_name| assign_role(role_name) }
  end

  def remove_role(role_name)
    role = Role.find_by(name: role_name.to_s)
    return false unless role

    worker_roles.where(role: role).destroy_all
    true
  end

  def remove_roles(role_names)
    Array(role_names).each { |role_name| remove_role(role_name) }
  end

  def all_permissions
    # Get unique permissions from all roles
    roles.joins(:permissions)
         .pluck("permissions.name")
         .uniq
         .sort
  end

  def permission_names
    all_permissions
  end

  def role_names
    roles.pluck(:name)
  end

  def valid_worker_role?(role)
    # Role assignments are based on worker type: system workers vs account workers
    case role.role_type
    when "system"
      # System roles only valid for system workers (no account_id)
      system?
    when "user"
      # User roles only valid for account workers (has account_id)
      # Only specific user roles are allowed for management interface access
      system? ? false : [ "member", "manager", "billing_admin", "developer", "owner" ].include?(role.name)
    when "admin"
      # Admin roles only for system workers
      system?
    else
      false
    end
  end

  def assignable_roles
    # Return roles that can be assigned to this worker based on type
    if system?
      # System workers can have system and admin roles
      Role.where(role_type: [ "system", "admin" ])
    else
      # Account workers can only have specific user roles for management interface
      Role.where(role_type: "user").where(name: [ "member", "manager", "billing_admin", "developer", "owner" ])
    end
  end


  def can_access?(resource_type, action = :read)
    return false unless active?

    # Check through permission system
    permission_name = "#{resource_type}.#{action}"
    has_permission?(permission_name)
  end

  def regenerate_token!
    new_token = self.class.generate_secure_token
    update!(
      token_digest: Digest::SHA256.hexdigest(new_token),
      updated_at: Time.current
    )
    self.token = new_token
    log_token_regeneration
    new_token
  end

  def record_activity!(action, details = {})
    worker_activities.create!(
      activity_type: action,
      details: details.merge(
        ip_address: details[:ip_address],
        user_agent: details[:user_agent]
      ).compact,
      occurred_at: Time.current
    )
  end

  def last_activity
    worker_activities.order(:occurred_at).last
  end

  def active_in_last_hours(hours = 24)
    last_seen_at && last_seen_at > hours.hours.ago
  end

  def display_name
    "#{name} (#{account.name})"
  end

  def masked_token
    return "" if token_digest.blank?
    # Return a masked hash of the token digest for authenticity verification
    # Users can verify their token by computing SHA256(SHA256(their_token)) and comparing the visible portions
    verification_hash = Digest::SHA256.hexdigest(token_digest)
    # Show first 6 characters, mask middle with asterisks, show last 4 characters
    "#{verification_hash[0..5]}******#{verification_hash[-4..-1]}"
  end

  def full_token_hash
    return "" if token_digest.blank?
    # Return the complete hash of the token digest for full verification
    # Users can verify their token by comparing this hash with SHA256(SHA256(their_token))
    Digest::SHA256.hexdigest(token_digest)
  end

  def token_verification_hash
    return "" if token.blank?
    # Generate a hash that users can verify against their actual token
    # Users can verify by running: SHA256(SHA256(their_token))[0..15] == this_hash
    token_digest_value = Digest::SHA256.hexdigest(token)
    verification_hash = Digest::SHA256.hexdigest(token_digest_value)
    verification_hash[0..15]
  end

  def system?
    is_system?
  end

  def account?
    !system?
  end

  # Promote this worker to be the system worker.
  # Fails if another system worker already exists — demote it first.
  def promote_to_system!
    raise "Another system worker already exists. Demote it first." if Worker.system_workers.where.not(id: id).exists?

    transaction do
      update!(is_system: true)
      assign_role("system_worker")
    end
  end

  # Demote the system worker back to a regular account worker.
  def demote_from_system!
    raise "Worker is not the system worker" unless system?

    transaction do
      update!(is_system: false)
      remove_role("system_worker")
    end
  end

  # Worker Configuration Methods
  def effective_config
    self.class.default_config.deep_merge(config || {})
  end

  def self.default_config
    {
      "security" => {
        "token_rotation_enabled" => false,
        "token_expiry_days" => 90,
        "require_ip_whitelist" => false,
        "allowed_ips" => [],
        "max_concurrent_sessions" => 10,
        "enforce_https" => true
      },
      "rate_limiting" => {
        "enabled" => true,
        "requests_per_minute" => 60,
        "burst_limit" => 100,
        "throttle_delay_ms" => 1000
      },
      "monitoring" => {
        "activity_logging" => true,
        "performance_tracking" => true,
        "error_reporting" => true,
        "metrics_retention_days" => 30
      },
      "notifications" => {
        "alert_on_failures" => true,
        "alert_threshold" => 5,
        "notify_on_token_rotation" => true,
        "notify_on_suspension" => true
      },
      "operational" => {
        "auto_cleanup_activities" => true,
        "cleanup_after_days" => 30,
        "enable_health_checks" => true,
        "health_check_interval_minutes" => 5
      }
    }
  end

  def reset_config!
    update!(config: self.class.default_config)
    effective_config
  end

  private

  def generate_token
    if token_digest.blank? && token.blank?
      self.token = self.class.generate_secure_token
      self.token_digest = Digest::SHA256.hexdigest(self.token)
    elsif token.present? && token_digest.blank?
      self.token_digest = Digest::SHA256.hexdigest(self.token)
    end
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
      action: "create",
      resource_type: "Worker",
      resource_id: id,
      source: "system",
      new_values: {
        name: name,
        status: status
      },
      metadata: {
        worker_type: "authentication_worker"
      }
    )
  end

  def log_status_change(new_status)
    AuditLog.create!(
      user: nil, # System change
      account: account,
      action: "update",
      resource_type: "Worker",
      resource_id: id,
      source: "system",
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
      action: "update",
      resource_type: "Worker",
      resource_id: id,
      source: "system",
      new_values: {
        token_regenerated_at: Time.current.iso8601
      },
      metadata: {
        token_regeneration: true
      }
    )
  end

  def only_one_system_worker_globally
    return unless is_system?

    existing_system = Worker.system_workers.where.not(id: id).first
    if existing_system
      errors.add(:base, "Only one system worker is allowed globally. Demote the existing system worker first.")
    end
  end
end

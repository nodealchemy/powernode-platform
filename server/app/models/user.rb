# frozen_string_literal: true

# User model with new permission system
class User < ApplicationRecord
  # PII Encryption - GDPR/SOC2 Compliance
  # Deterministic encryption for email allows querying (find_by email)
  # Non-deterministic encryption for other PII fields (more secure)
  encrypts :email, deterministic: true, downcase: true
  encrypts :name
  encrypts :two_factor_secret
  encrypts :backup_codes
  encrypts :last_login_ip

  # Authentication
  has_secure_password

  # Include concerns - must come after has_secure_password
  include PasswordSecurity
  include Auditable
  include OpensshKeyValidatable

  # Attributes
  attr_reader :reset_token

  # Associations
  belongs_to :account
  has_many :user_roles, dependent: :destroy
  has_many :roles, through: :user_roles
  has_many :audit_logs, dependent: :nullify
  has_many :password_histories, dependent: :destroy
  has_many :pages, foreign_key: "author_id", dependent: :destroy
  has_many :impersonation_sessions_as_impersonator,
           class_name: "ImpersonationSession",
           foreign_key: "impersonator_id",
           dependent: :destroy
  has_many :impersonation_sessions_as_target,
           class_name: "ImpersonationSession",
           foreign_key: "impersonated_user_id",
           dependent: :destroy
  has_many :notifications, dependent: :destroy
  has_many :user_tokens, dependent: :destroy
  has_many :mcp_sessions, dependent: :destroy

  # Serialization
  serialize :preferences, coder: JSON
  serialize :notification_preferences, coder: JSON
  serialize :backup_codes, coder: JSON

  # Validations
  validates :email, presence: true,
                   format: { with: URI::MailTo::EMAIL_REGEXP },
                   uniqueness: { case_sensitive: false }
  validates :name, presence: true, length: { minimum: 1, maximum: 100 }
  validates :status, presence: true, inclusion: { in: %w[active inactive suspended] }
  validate :authorized_keys_format

  # Operator-supplied OpenSSH `authorized_keys` lines. Aggregated by
  # `System::Node#authorized_keys` (cross-extension) so every node owned by
  # this user's account picks them up via the agent's heartbeat-driven
  # /node_api/config/authorized_keys reconciler — no per-node config push
  # required.
  def authorized_keys=(value)
    super(Array(value).compact_blank.uniq)
  end

  private

  def authorized_keys_format
    keys = authorized_keys
    return unless keys.is_a?(Array)
    keys.each_with_index do |line, idx|
      next if openssh_authorized_key?(line)
      errors.add(:authorized_keys, "entry #{idx + 1} is not a valid OpenSSH authorized_keys line")
    end
  end

  public

  # Callbacks
  before_validation :normalize_email
  after_create :assign_default_role
  after_create :assign_permissions_after_create
  after_update :clear_reset_token_on_password_change, if: :saved_change_to_password_digest?
  before_save :set_password_changed_at, if: :password_digest_changed?
  after_touch :clear_permission_cache

  # Constants
  MAX_FAILED_ATTEMPTS = 5
  LOCKOUT_DURATION = 30.minutes
  PASSWORD_HISTORY_COUNT = 12

  # Scopes
  scope :active, -> { where(status: "active") }
  scope :verified, -> { where.not(email_verified_at: nil) }
  scope :unverified, -> { where(email_verified_at: nil) }
  scope :locked, -> { where("locked_until > ?", Time.current) }
  scope :unlocked, -> { where("locked_until IS NULL OR locked_until <= ?", Time.current) }
  scope :with_role, ->(role_name) { joins(:roles).where(roles: { name: role_name }) }

  # Returns users who hold a specific permission either directly via a role,
  # or implicitly via the system.admin grant-all rule. The two cohorts are
  # union-ed via raw IDs to keep the query simple under both code paths.
  scope :with_permission, ->(permission_name) {
    direct_ids = joins(roles: :role_permissions).where(role_permissions: { permission_name: permission_name }).pluck(:id)
    admin_ids  = joins(roles: :role_permissions).where(role_permissions: { permission_name: "system.admin" }).pluck(:id)
    where(id: (direct_ids + admin_ids).uniq)
  }

  # JSON serialization - exclude sensitive fields
  def as_json(options = {})
    super(options.merge(except: [
      :password_digest, :failed_login_attempts, :locked_until, :password_changed_at,
      :two_factor_secret, :backup_codes
    ]))
  end

  # Instance methods
  def full_name
    name.to_s.strip
  end

  def initials
    name_parts = name.to_s.split(" ")
    return "" if name_parts.empty?

    if name_parts.length == 1
      name_parts[0][0].upcase
    else
      "#{name_parts.first[0]}#{name_parts.last[0]}".upcase
    end
  end

  def active?
    status == "active"
  end

  # NEW: Permission-based access control methods
  def has_permission?(permission_name)
    # system.admin (held through any role) grants every permission
    return true if roles.joins(:role_permissions).exists?(role_permissions: { permission_name: "system.admin" })

    # Otherwise the user has it if any of their roles grants it
    roles.joins(:role_permissions).exists?(role_permissions: { permission_name: permission_name })
  end

  def has_any_permission?(*permission_names)
    permission_names.any? { |p| has_permission?(p) }
  end

  def has_all_permissions?(*permission_names)
    permission_names.all? { |p| has_permission?(p) }
  end

  # Effective permission names for this user. The Permissions catalog is the
  # source of truth; system.admin expands to the entire catalog. Array<String>.
  def permissions
    permission_names
  end

  # Permissions this user may GRANT to an account-scoped custom role. Enforces
  # "no privilege escalation": you can only grant permissions you yourself hold,
  # and never the SYSTEM tier (platform/infra control, incl system.admin).
  # RESOURCE and ADMIN tier permissions are grantable iff held.
  def grantable_permission_names
    permission_names.reject { |name| name.start_with?("system.") }
  end

  def can_grant_permission?(permission_name)
    grantable_permission_names.include?(permission_name)
  end

  # UNCACHED WRAPS THE WHOLE BODY, NOT JUST THE KEY. Computing a fresh key is
  # only half the job: on a miss the block re-reads the grants, and ActiveRecord's
  # per-request query cache would answer those reads from the PRE-narrowing
  # snapshot taken earlier in the same request (it is dirtied only by writes on
  # THIS connection, and the narrowing is another process's). The wide set would
  # then be written to the SHARED store under the correct post-narrowing key —
  # the original defect, with a larger blast radius than the one it replaced.
  def permission_names
    # PERFORMANCE FIX: Cache permission names to avoid expensive queries on every token refresh
    # Cache expires after 5 minutes or when user's roles/permissions change
    self.class.uncached do
      Rails.cache.fetch(permission_names_cache_key, expires_in: 5.minutes) do
        if roles.joins(:role_permissions).exists?(role_permissions: { permission_name: "system.admin" })
          # system.admin grants the entire catalog
          Permissions.all_permissions.keys.sort
        else
          roles.joins(:role_permissions).pluck("role_permissions.permission_name").uniq.sort
        end
      end
    end
  end

  # Virtual attribute for setting permissions (useful for testing)
  # Creates or finds a role with the specified permissions and assigns it to the user
  def permissions=(permission_list)
    # Set flag to skip default role assignment (even for empty arrays)
    @permissions_explicitly_set = true
    # Store pending permissions for after_create callback
    @pending_permissions = Array(permission_list)
  end

  def assign_permissions_after_create
    # Use nil? instead of blank? to allow empty arrays (users with no permissions)
    return if @pending_permissions.nil?

    # Find or create a test role with these specific permissions
    # Use alphanumeric string that matches Role name validation
    #
    # SCOPED TO THIS USER'S ACCOUNT, never global. account_id nil is the marker
    # for a GLOBAL role — the scope Role.sync_from_config! seeds the real
    # catalog into, and the scope every "no global role holds <verb>" catalog
    # assertion selects on. Minting the ad-hoc role there put a harness artefact
    # in the catalog's own scope, reachable by a sweep two ways:
    #   1. SAME transaction — a sweep example whose enclosing describe builds an
    #      actor with `permissions: [...]` in a `let!`/`before` sees the harness
    #      row immediately. No commit is involved; transactional rollback does
    #      not help, because the sweep runs before it.
    #   2. COMMITTED rows on the shared test DB — the suite is transactional
    #      (spec/rails_helper.rb), but any non-transactional example commits:
    #      `truncation: true` (rails_helper.rb) or `type: :performance` /
    #      `:integration` (spec/support/ai_test_configuration.rb). There are
    #      none today, so this arm is latent rather than active.
    # Either way the failure reads "global <role> unexpectedly holds <verb>" —
    # indistinguishable from the real catalog re-widening the sweep exists to
    # catch. An account-scoped role is equally assignable
    # (UserRole#role_available_to_user_account admits a role owned by the user's
    # own account) and is invisible to Role.global.
    #
    # NOTE the remaining vector: `create(:role)` (spec/factories/roles.rb) still
    # mints a GLOBAL `test_role_*` row, and its `:with_permissions` trait puts
    # real catalog verbs on it, so a `test_role_*` red is not automatically
    # stale. Fix such a red by scoping the role where it is CREATED — never by
    # excluding the `test_role_*` prefix in the sweep, which every future author
    # would then have to remember.
    # See spec/models/user_factory_role_scope_spec.rb.
    role_name = "test_role_#{('a'..'z').to_a.sample(8).join}"
    role = Role.create!(
      name: role_name,
      display_name: "Test Role",
      role_type: "user",
      description: "Test role with custom permissions",
      account_id: account_id
    )

    # Grant permissions by name (the catalog is the source of truth). Tests may
    # reference ad-hoc permission names, so register any unknown name at runtime
    # to satisfy the catalog-membership validation.
    @pending_permissions.each do |permission_name|
      unless Permissions.permission_exists?(permission_name)
        Permissions.register_permissions(permission_name => "Test permission")
      end
      role.role_permissions.find_or_create_by!(permission_name: permission_name)
    end

    # Assign role to user
    roles << role unless roles.include?(role)

    @pending_permissions = nil
    clear_permission_cache
  end

  # Cache key for the memoized permission set. EVERY input the set is derived
  # from has to be observable here, or a narrowing leaves the stale, WIDER set
  # addressable for the whole TTL — and Role#assignable_by? resolves its
  # privilege-escalation subset check through #permission_names, so a blind key
  # makes conferring a whole role fail OPEN (IMP-95e4904258c8).
  #
  #   updated_at      — the user's own row
  #   role_cache_key  — WHICH roles the user holds, and WHAT each one grants
  def permission_names_cache_key
    "user:#{id}:permission_names:#{updated_at.to_i}:#{role_cache_key}"
  end

  # Identity AND grant-version of every role this user holds.
  #
  # roles.permissions_version is bumped by a DB trigger on role_permissions (see
  # db/migrate/20260901000000_add_permissions_version_to_roles.rb), which is why
  # a permission removed by a raw-SQL remap migration — firing no ActiveRecord
  # callback — still changes this key.
  #
  # DELIBERATELY NOT MEMOIZED, AND DELIBERATELY UNCACHED. The version is bumped
  # underneath this object by the database, so:
  #   - memoizing it on the instance would reintroduce the same staleness one
  #     object-lifetime wide, and
  #   - letting ActiveRecord's per-request query cache serve it would do the
  #     same one REQUEST wide. That cache is only dirtied by writes on THIS
  #     connection, so a narrowing committed by another process (a remap
  #     migration is exactly that) would not evict it.
  # Either is precisely long enough for a conferral to be decided on a
  # superseded permission set, and a conferral is durable.
  #
  # `.order(:id)` is LOAD-BEARING, not cosmetic. It spawns a fresh unloaded
  # relation off the association scope; drop it and CollectionProxy#pluck takes
  # its `loaded?` short-circuit and answers from stale in-memory Role objects,
  # which no amount of trigger correctness can fix.
  def role_cache_key
    self.class.uncached do
      roles.order(:id).pluck(:id, :permissions_version)
           .map { |role_id, version| "#{role_id}.#{version}" }.join("-")
    end
  end

  # Role checking methods
  def has_role?(role_name)
    roles.exists?(name: role_name)
  end

  def has_any_role?(*role_names)
    roles.where(name: role_names).exists?
  end

  def role_names
    roles.pluck(:name)
  end

  def add_role(role_name)
    role = Role.find_by(name: role_name)
    return false unless role

    roles << role unless roles.include?(role)
    true
  end

  # Assign a role to this user. Accepts a Role or a role name; an optional
  # assigned_by user is recorded on the user_roles join (via grant_to_user).
  def assign_role(role_or_name, assigned_by: nil)
    role = role_or_name.is_a?(Role) ? role_or_name : Role.find_by(name: role_or_name)
    return false unless role

    if assigned_by
      role.grant_to_user(self, assigned_by)
    else
      roles << role unless roles.include?(role)
    end
    true
  end

  def remove_role(role_name)
    role = Role.find_by(name: role_name)
    return false unless role

    roles.delete(role)
    true
  end

  # Grant a single permission to this user via their first role
  def grant_permission(permission_name)
    role = roles.first || Role.find_or_create_by!(name: "custom_#{id}") do |r|
      r.display_name = "Custom Role"
      r.role_type = "user"
    end
    role.add_permission(permission_name)
    self.roles << role unless self.roles.include?(role)
    reload
  end

  # Convenience methods for common role checks
  def super_admin?
    has_role?("super_admin")
  end

  def admin?
    has_role?("admin") || has_role?("super_admin")
  end

  def owner?
    has_role?("owner")
  end

  def manager?
    has_role?("manager")
  end

  def member?
    has_role?("member")
  end

  def billing_admin?
    has_role?("billing_admin")
  end

  # Check if user can perform action on resource
  def can?(permission_or_action, resource = nil)
    if resource
      # Format: can?('edit', 'user') => checks 'user.edit'
      has_permission?("#{resource}.#{permission_or_action}")
    else
      # Format: can?('user.edit')
      has_permission?(permission_or_action)
    end
  end

  def cannot?(permission_or_action, resource = nil)
    !can?(permission_or_action, resource)
  end

  # Override authenticate to integrate with lockout mechanism
  def authenticate(unencrypted_password)
    if locked?
      return false
    end

    result = super(unencrypted_password)

    if result
      record_successful_login! if respond_to?(:record_successful_login!)
      result
    else
      record_failed_login! if respond_to?(:record_failed_login!) && unencrypted_password.present?
      false
    end
  end

  # Email verification
  def verified?
    email_verified_at.present?
  end

  alias_method :email_verified?, :verified?

  def verify_email!
    update!(email_verified_at: Time.current) unless verified?
  end

  def generate_email_verification_token
    self.email_verification_token = SecureRandom.urlsafe_base64
    self.email_verification_sent_at = Time.current
    save!
  end

  def email_verification_expired?
    return true unless email_verification_sent_at
    email_verification_sent_at < 24.hours.ago
  end

  # Password reset

  def create_reset_digest
    @reset_token = SecureRandom.urlsafe_base64
    update!(
      reset_digest: BCrypt::Password.create(@reset_token),
      reset_sent_at: Time.current
    )
  end

  def authenticated?(attribute, token)
    digest = send("#{attribute}_digest")
    return false if digest.nil?
    BCrypt::Password.new(digest).is_password?(token)
  end

  def reset_password!(new_password, token)
    # Verify the token matches what we stored
    return false unless reset_token_digest.present?
    return false unless BCrypt::Password.new(reset_token_digest).is_password?(token)
    return false if reset_token_expires_at && reset_token_expires_at < Time.current
    return false if new_password.blank?

    # Enforce the SAME strength + reuse policy as every other password-set path.
    # update_columns below skips validate_password_strength, so validate the new
    # password here — directly, without mutating @password, so no validation
    # state lingers on the instance — and bail before writing on failure. Errors
    # land on :password so the controller's render_validation_error surfaces them.
    strength = Security::PasswordStrengthService.validate_password(new_password)
    unless strength[:valid]
      strength[:errors].each { |message| errors.add(:password, message) }
      return false
    end
    if password_previously_used?(new_password)
      errors.add(:password, "has been used recently. For security, please choose a different password that you haven't used in your last #{PASSWORD_HISTORY_COUNT} password changes")
      return false
    end

    transaction do
      new_digest = BCrypt::Password.create(new_password)

      update_columns(
        password_digest: new_digest,
        reset_token_digest: nil,
        reset_token_expires_at: nil,
        password_changed_at: Time.current
      )

      # Create password history entry manually (update_columns skips the callback)
      password_histories.create!(
        password_digest: new_digest,
        created_at: Time.current
      )

      # Keep only the last N passwords
      old_passwords = password_histories.order(created_at: :desc).offset(PASSWORD_HISTORY_COUNT)
      old_passwords.destroy_all if old_passwords.any?

      true
    end
  rescue StandardError => e
    Rails.logger.error "Password reset failed: #{e.message}"
    errors.add(:base, "Password reset failed: #{e.message}")
    false
  end

  def password_reset_expired?
    return true unless reset_sent_at
    reset_sent_at < 2.hours.ago
  end

  # Account locking
  def locked?
    locked_until.present? && locked_until > Time.current
  end

  def lock_account!
    update!(
      locked_until: LOCKOUT_DURATION.from_now,
      failed_login_attempts: 0
    )
  end

  def unlock_account!
    update!(
      locked_until: nil,
      failed_login_attempts: 0
    )
  end

  def increment_failed_attempts!
    self.failed_login_attempts ||= 0
    self.failed_login_attempts += 1

    if failed_login_attempts >= MAX_FAILED_ATTEMPTS
      lock_account!
    else
      save!
    end
  end

  def reset_failed_attempts!
    update!(failed_login_attempts: 0) if failed_login_attempts&.positive?
  end

  def record_login!
    update!(
      last_login_at: Time.current,
      failed_login_attempts: 0
    )
  end

  # Two-factor authentication
  def two_factor_enabled?
    two_factor_secret.present?
  end

  def enable_two_factor!(secret = nil)
    new_secret = secret || ROTP::Base32.random
    new_codes = generate_backup_codes
    update!(
      two_factor_secret: new_secret,
      two_factor_enabled: true,
      two_factor_enabled_at: Time.current,
      backup_codes: new_codes,
      two_factor_backup_codes_generated_at: Time.current
    )
    new_secret
  end

  def disable_two_factor!
    update!(
      two_factor_secret: nil,
      two_factor_enabled: false,
      two_factor_enabled_at: nil,
      backup_codes: nil,
      two_factor_backup_codes_generated_at: nil
    )
  end

  def verify_two_factor_token(token)
    return false unless two_factor_enabled?

    totp = ROTP::TOTP.new(two_factor_secret)
    totp.verify(token, drift_behind: 30, drift_ahead: 30)
  end

  def verify_backup_code(code)
    return false unless backup_codes&.include?(code)

    remaining_codes = backup_codes - [ code ]
    update!(backup_codes: remaining_codes)
    true
  end

  # Generate QR code URI for authenticator apps
  def two_factor_qr_code
    return nil unless two_factor_secret.present?

    totp = ROTP::TOTP.new(two_factor_secret, issuer: "Powernode")
    totp.provisioning_uri(email)
  end

  # Alias for controller compatibility
  def two_factor_backup_codes
    backup_codes || []
  end

  # Regenerate backup codes
  def regenerate_backup_codes!
    new_codes = generate_backup_codes
    update!(
      backup_codes: new_codes,
      two_factor_backup_codes_generated_at: Time.current
    )
    new_codes
  end

  private

  def normalize_email
    self.email = email&.downcase&.strip
  end

  def assign_default_role
    return unless roles.empty?
    # Skip default role if permissions were explicitly set (even if empty)
    return if @permissions_explicitly_set

    # First user in account gets owner role
    if account && account.users.count == 1  # This user is the only one (just created)
      owner_role = Role.find_by(name: "owner")
      roles << owner_role if owner_role
    else
      # Assign member role by default
      member_role = Role.find_by(name: "member")
      roles << member_role if member_role
    end
  end



  def clear_reset_token_on_password_change
    update_columns(reset_token_digest: nil, reset_token_expires_at: nil) if reset_token_digest.present?
  end

  def set_password_changed_at
    self.password_changed_at = Time.current
  end

  def generate_backup_codes
    Array.new(10) { SecureRandom.hex(4).upcase }
  end

  # Permission-cache invalidation is STRUCTURAL, not a deletion: every input the
  # cached set is derived from is in #permission_names_cache_key, so any change
  # that could widen or narrow the set changes the key. The superseded entry is
  # unreachable from that moment and expires on its own TTL. There is nothing
  # here that can fail, so there is no rescue downgrading a failed authorization-
  # cache invalidation to a warning.
  #
  # WHAT THIS USED TO DO, AND WHY IT IS GONE (IMP-95e4904258c8). It called
  # Rails.cache.delete_matched("user:<id>:permission_names:*") under a
  # `rescue StandardError`, and what that did depended entirely on the store:
  #   - on the store production resolves to when CACHE_STORE is unset
  #     (:solid_cache_store, config/environments/production.rb:50 — the
  #     environment file loads AFTER the :redis_cache_store assignment in
  #     config/application.rb:87, so it wins), delete_matched is not implemented
  #     and raises NotImplementedError. That is a ScriptError, NOT a
  #     StandardError, so the rescue could not catch it: the invalidation had
  #     never once run, and the exception propagated into whatever changed the
  #     role. Loud, but in the wrong place.
  #   - on the store the hub actually deploys with (CACHE_STORE=memory_store,
  #     set in the powernode-hub-backend module manifest) it returns normally,
  #     but MemoryStore is PER-PROCESS: it clears only the calling process's
  #     copy. That is the whole cache today only because the hub leaves
  #     WEB_CONCURRENCY unset and puma therefore runs single-process
  #     (config/puma.rb:24); a second worker or an out-of-band `rails runner`
  #     keeps its own stale entry.
  # (The pattern was a WILDCARD over every entry for the user, so on those two
  # stores it did reach the pre-change entry — it ran after the change, but it
  # was not addressing only the new key. It was a real invalidation there; it
  # was simply not one on the default store, and not one across processes.)
  def clear_permission_cache
    true
  end
end

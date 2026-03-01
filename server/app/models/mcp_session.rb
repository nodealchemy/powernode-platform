# frozen_string_literal: true

class McpSession < ApplicationRecord
  # Associations
  belongs_to :user
  belongs_to :account
  belongs_to :oauth_application, class_name: "Doorkeeper::Application", foreign_key: "oauth_application_id", optional: true
  belongs_to :ai_agent, class_name: "Ai::Agent", foreign_key: "ai_agent_id", optional: true

  # Constants
  STATUSES = %w[active expired revoked].freeze
  DEFAULT_TTL = 24.hours
  RECONNECT_GRACE_PERIOD = 10.minutes

  # Validations
  validates :session_token, presence: true, uniqueness: true
  validates :status, presence: true, inclusion: { in: STATUSES }

  # Scopes
  scope :active, -> { where(status: "active").where("expires_at > ?", Time.current) }
  scope :expired, -> { where(status: "expired").or(where("expires_at <= ?", Time.current)) }
  scope :revoked, -> { where(status: "revoked") }
  scope :for_account, ->(account_id) { where(account_id: account_id) }
  scope :for_user, ->(user_id) { where(user_id: user_id) }
  scope :stale, ->(duration = 1.hour) { where("last_activity_at < ?", duration.ago) }

  # Callbacks
  before_validation :set_defaults, on: :create
  after_update :deactivate_agent_on_end, if: -> { saved_change_to_status? && !active? }

  # Instance methods
  def revoke!
    update!(status: "revoked", revoked_at: Time.current)
  end

  def touch_activity!
    now = Time.current
    updates = { last_activity_at: now }
    # Extend TTL on activity — prevents sessions from expiring while actively in use
    updates[:expires_at] = DEFAULT_TTL.from_now if expires_at.present? && expires_at < 1.hour.from_now
    update_columns(updates)
  end

  def expired?
    status == "expired" || (expires_at.present? && expires_at <= Time.current)
  end

  def active?
    status == "active" && !expired?
  end

  def revoked?
    status == "revoked"
  end

  # A session is reactivatable if it was recently revoked (within grace period)
  # and hasn't exceeded its original TTL. This handles server restarts where the
  # SSE connection drops and revoke! fires, but the client reconnects shortly after.
  def reactivatable?
    revoked? &&
      revoked_at.present? &&
      revoked_at > RECONNECT_GRACE_PERIOD.ago &&
      expires_at.present? &&
      expires_at > Time.current
  end

  # Reactivate a recently-revoked session (e.g., after a server restart).
  # The deactivate_agent_on_end callback is skipped during the grace period,
  # so the agent and its workspace team memberships remain intact.
  def reactivate!
    return false unless reactivatable?

    update!(status: "active", expires_at: [expires_at, DEFAULT_TTL.from_now].max)
    touch_activity!

    Rails.logger.info "[McpSession] Reactivated session #{id} (revoked #{((Time.current - revoked_at)).round}s ago)"
    true
  end

  # Links this session to an MCP client agent identity
  def link_agent!(agent)
    update!(ai_agent_id: agent.id, display_name: agent.name)
  end

  # Expire stale previous sessions for the same user/account, keeping this one
  # and any other sessions with recent activity (i.e., other active CLI instances).
  # A session with activity in the last 5 minutes is presumed live (its SSE daemon
  # calls touch_activity! regularly) and is left alone.
  def expire_previous_sessions!
    scope = McpSession.where(account_id: account_id, user_id: user_id, status: "active")
      .where.not(id: id)
    scope = scope.where(oauth_application_id: oauth_application_id) if oauth_application_id.present?
    scope.where("last_activity_at < ?", 5.minutes.ago)
      .find_each { |s| s.update!(status: "expired") }
  end

  # Bulk cleanup: delete expired sessions older than the given age
  def self.cleanup_expired!(older_than: 48.hours)
    where(status: %w[expired revoked])
      .where("expires_at < ?", older_than.ago)
      .delete_all
  end

  private

  def deactivate_agent_on_end
    return unless ai_agent_id.present?
    # Don't archive if agent is linked to another active session
    return if McpSession.active.where(ai_agent_id: ai_agent_id).where.not(id: id).exists?
    # Don't archive during the reconnect grace period — the client may reconnect
    # shortly (e.g., after a server restart). Deactivation will run via the daily
    # cleanup job if the session stays revoked past the grace period.
    return if revoked? && reactivatable?

    Ai::McpClientIdentityService.deactivate_agent(self)
  end

  def set_defaults
    self.session_token ||= SecureRandom.uuid
    self.expires_at ||= DEFAULT_TTL.from_now
    self.last_activity_at ||= Time.current
    self.status ||= "active"
  end
end

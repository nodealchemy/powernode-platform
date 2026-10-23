# frozen_string_literal: true

class McpSession < ApplicationRecord
  # Associations
  # Optional: instance principals (dev-cell / node-instance mTLS clients,
  # resolved via Mcp::Principal.for_instance_cn) have no User — they record
  # principal_kind + principal_subject_id instead. (BUG-Q)
  belongs_to :user, optional: true
  belongs_to :account
  belongs_to :oauth_application, class_name: "Doorkeeper::Application", foreign_key: "oauth_application_id", optional: true
  belongs_to :ai_agent, class_name: "Ai::Agent", foreign_key: "ai_agent_id", optional: true

  # Constants
  STATUSES = %w[active expired revoked].freeze
  DEFAULT_TTL = 24.hours
  RECONNECT_GRACE_PERIOD = 10.minutes
  # A session with no JSON-RPC activity for this long is idle: it no longer
  # counts as live and is swept to "expired". A connected SSE stream touches
  # its session every ~5 minutes, so only abandoned sessions go idle. Clients
  # that initialize per call and never DELETE would otherwise stay active for
  # the whole 24h TTL. Override in minutes via IDLE_TIMEOUT_SETTING.
  DEFAULT_IDLE_TIMEOUT = 60.minutes
  IDLE_TIMEOUT_SETTING = "mcp_session_idle_timeout_minutes"

  # Validations
  validates :session_token, presence: true, uniqueness: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  # Every session belongs to a principal — a User (OAuth/CLI) or an instance
  # (mTLS node cert). Guards against a userless, subjectless session. (BUG-Q)
  validate :must_have_a_principal

  def must_have_a_principal
    return if user_id.present? || principal_subject_id.present?

    errors.add(:base, "must belong to a user or an instance principal")
  end

  # Scopes
  scope :active, -> { where(status: "active").where("expires_at > ?", Time.current) }
  scope :expired, -> { where(status: "expired").or(where("expires_at <= ?", Time.current)) }
  scope :revoked, -> { where(status: "revoked") }
  scope :for_account, ->(account_id) { where(account_id: account_id) }
  scope :for_user, ->(user_id) { where(user_id: user_id) }
  scope :stale, ->(duration = 1.hour) { where("last_activity_at < ?", duration.ago) }
  scope :idle, -> { where(status: "active").where("last_activity_at < ?", idle_timeout.ago) }
  # Complement of idle among active sessions (a row with no recorded activity is not idle).
  scope :live, -> { active.where("last_activity_at IS NULL OR last_activity_at >= ?", idle_timeout.ago) }
  scope :in_grace_period, -> {
    where(status: "revoked")
      .where("revoked_at > ?", RECONNECT_GRACE_PERIOD.ago)
      .where("expires_at > ?", Time.current)
  }

  # Callbacks
  before_validation :set_defaults, on: :create
  after_update :deactivate_agent_on_end, if: -> { saved_change_to_status? && !active? }
  # The end of a session ends every promotion grant bound to it. "expired" is
  # final; a revoke inside the reconnect grace is not (the grants are paused,
  # since only a live session spends them), so the binding sweep revokes those
  # once the grace has run out (Ai::PromotionGrants::BindingSweep).
  after_update :end_bound_promotion_grants, if: -> { saved_change_to_status? && status == "expired" }

  def self.idle_timeout
    minutes = SiteSetting.get(IDLE_TIMEOUT_SETTING).to_i
    minutes.positive? ? minutes.minutes : DEFAULT_IDLE_TIMEOUT
  end

  # Marks idle active sessions in `scope` expired; returns the count.
  # update_all skips deactivate_agent_on_end, which only logs: MCP client
  # agents persist across sessions anyway.
  def self.expire_idle!(scope = all)
    ids = scope.idle.pluck(:id)
    return 0 if ids.empty?

    count = where(id: ids).idle.update_all(status: "expired", updated_at: Time.current)
    # update_all runs no callbacks, so the grants these sessions carried are
    # ended here, each with its audit row.
    ::Ai::PromotionGrants::Ledger.revoke_bound!(kind: ::Ai::PromotionGrant::BINDING_MCP_SESSION, ids: ids,
                                                reason: ::Ai::PromotionGrants::Ledger::SESSION_ENDED)
    count
  end

  # Instance methods
  # Only an active session can be revoked: revoking an idle-swept (expired)
  # one would make it reactivatable? and bring it back from the dead.
  def revoke!
    return false unless status == "active"

    update!(status: "revoked", revoked_at: Time.current)
  end

  def touch_activity!
    now = Time.current
    updates = { last_activity_at: now }
    # Sliding-window renewal: every request advances expires_at to
    # now + DEFAULT_TTL. Previously the renewal only triggered when
    # the session was within 1 hour of expiring — meaning an operator
    # who used the session heavily for ~22h, then went idle for 3h,
    # came back to a dead session even though they'd been actively
    # using it. Sliding window matches the intuitive "session stays
    # alive as long as you're using it" contract.
    #
    # Guarded by expires_at.present? so legacy rows without a TTL
    # don't get a fresh one assigned mid-flight.
    if expires_at.present?
      updates[:expires_at] = DEFAULT_TTL.from_now
    end
    update_columns(updates)
  end

  def expired?
    status == "expired" || (expires_at.present? && expires_at <= Time.current)
  end

  def active?
    status == "active" && !expired?
  end

  # The instance form of the `live` scope: active, within its TTL, and not
  # idle past McpSession.idle_timeout (a row with no recorded activity is not
  # idle). A promotion grant bound to this session is spent only while this
  # holds (Ai::PromotionGrants::Binding).
  def live?
    active? && (last_activity_at.nil? || last_activity_at >= self.class.idle_timeout.ago)
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

  # Bulk cleanup: delete expired sessions older than the given age,
  # then archive orphaned MCP client agents (no remaining live sessions).
  def self.cleanup_expired!(older_than: 48.hours)
    deleted = where(status: %w[expired revoked])
      .where("expires_at < ?", older_than.ago)
      .delete_all

    cleanup_orphaned_agents! if deleted > 0

    deleted
  end

  # Archives MCP client agents that have no remaining sessions (active or
  # grace-period) and drops them from workspace teams. Never destroys: an
  # agent is the client's one persistent identity, and destroying it would
  # cascade its executions, memories and skills just because the client went
  # idle. Ai::McpClientIdentityService#find_existing_agent reactivates it on
  # the next connect. Agents in non-workspace teams (manually configured) are
  # left untouched. Returns the number archived.
  def self.cleanup_orphaned_agents!
    agents_with_sessions = McpSession
      .where(status: "active").or(McpSession.in_grace_period)
      .where.not(ai_agent_id: nil)
      .select(:ai_agent_id)

    orphaned = Ai::Agent.where(agent_type: "mcp_client", status: "active")
      .where.not(id: agents_with_sessions)

    archived = 0
    orphaned.find_each do |agent|
      manual_teams = Ai::AgentTeamMember.joins(:team)
        .where(ai_agent_id: agent.id)
        .where.not(ai_agent_teams: { team_type: "workspace" })
      next if manual_teams.exists?

      Ai::McpClientIdentityService.archive_agent!(agent)
      archived += 1
    end
    archived
  end

  private

  def end_bound_promotion_grants
    ::Ai::PromotionGrants::Ledger.revoke_bound!(kind: ::Ai::PromotionGrant::BINDING_MCP_SESSION, ids: [ id ],
                                                reason: ::Ai::PromotionGrants::Ledger::SESSION_ENDED)
  end

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

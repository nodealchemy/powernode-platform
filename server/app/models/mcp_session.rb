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
    update_columns(last_activity_at: Time.current)
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

  # Links this session to an MCP client agent identity
  def link_agent!(agent)
    update!(ai_agent_id: agent.id, display_name: agent.name)
  end

  private

  def deactivate_agent_on_end
    Ai::McpClientIdentityService.deactivate_agent(self)
  end

  def set_defaults
    self.session_token ||= SecureRandom.uuid
    self.expires_at ||= DEFAULT_TTL.from_now
    self.last_activity_at ||= Time.current
    self.status ||= "active"
  end
end

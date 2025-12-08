# frozen_string_literal: true

# Tracks user consent decisions for GDPR compliance
class UserConsent < ApplicationRecord
  # Associations
  belongs_to :user
  belongs_to :account

  # Validations
  validates :consent_type, presence: true, inclusion: {
    in: %w[marketing analytics cookies data_sharing third_party communications newsletter promotional]
  }
  validates :collection_method, presence: true, inclusion: {
    in: %w[explicit implicit opt_out]
  }

  # Scopes
  scope :active, -> { where(granted: true).where('expires_at IS NULL OR expires_at > ?', Time.current) }
  scope :withdrawn, -> { where(granted: false).or(where.not(withdrawn_at: nil)) }
  scope :by_type, ->(type) { where(consent_type: type) }
  scope :granted, -> { where(granted: true) }
  scope :expired, -> { where('expires_at < ?', Time.current) }

  # Callbacks
  before_create :set_granted_at
  after_create :log_consent_granted
  after_update :log_consent_change

  # Class methods
  def self.current_consent(user, consent_type)
    where(user: user, consent_type: consent_type)
      .active
      .order(created_at: :desc)
      .first
  end

  def self.has_consent?(user, consent_type)
    current_consent(user, consent_type).present?
  end

  def self.grant_consent(user:, consent_type:, version: nil, consent_text: nil, ip_address: nil, user_agent: nil, metadata: {})
    # Withdraw any existing consent first
    withdraw_consent(user: user, consent_type: consent_type, ip_address: ip_address)

    create!(
      user: user,
      account: user.account,
      consent_type: consent_type,
      granted: true,
      version: version || "1.0",
      consent_text: consent_text,
      collection_method: 'explicit',
      ip_address: ip_address,
      user_agent: user_agent,
      metadata: metadata
    )
  end

  def self.withdraw_consent(user:, consent_type:, ip_address: nil)
    active.where(user: user, consent_type: consent_type).find_each do |consent|
      consent.update!(
        granted: false,
        withdrawn_at: Time.current,
        metadata: consent.metadata.merge(withdrawal_ip: ip_address)
      )
    end
  end

  # Instance methods
  def active?
    granted? && (expires_at.nil? || expires_at > Time.current)
  end

  def expired?
    expires_at.present? && expires_at <= Time.current
  end

  def withdraw!(ip_address: nil)
    update!(
      granted: false,
      withdrawn_at: Time.current,
      metadata: metadata.merge(withdrawal_ip: ip_address)
    )
  end

  private

  def set_granted_at
    self.granted_at = Time.current if granted?
  end

  def log_consent_granted
    return unless granted?

    AuditLog.log_compliance_event(
      action: 'gdpr_request',
      resource: self,
      user: user,
      account: account,
      metadata: {
        event_type: 'consent_granted',
        consent_type: consent_type,
        version: version
      }
    )
  end

  def log_consent_change
    return unless saved_change_to_granted?

    event_type = granted? ? 'consent_granted' : 'consent_withdrawn'

    AuditLog.log_compliance_event(
      action: 'gdpr_request',
      resource: self,
      user: user,
      account: account,
      metadata: {
        event_type: event_type,
        consent_type: consent_type,
        version: version
      }
    )
  end
end

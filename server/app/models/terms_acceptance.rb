# frozen_string_literal: true

# Tracks user acceptance of legal documents (ToS, Privacy Policy, etc.)
class TermsAcceptance < ApplicationRecord
  # Associations
  belongs_to :user
  belongs_to :account

  # Validations
  validates :document_type, presence: true, inclusion: {
    in: %w[terms_of_service privacy_policy dpa cookie_policy acceptable_use]
  }
  validates :document_version, presence: true
  validates :accepted_at, presence: true
  validates :document_type, uniqueness: { scope: [ :user_id, :document_version ] }

  # Scopes
  scope :current, -> { where(superseded_at: nil) }
  scope :by_type, ->(type) { where(document_type: type) }
  scope :by_version, ->(version) { where(document_version: version) }
  scope :recent, -> { order(accepted_at: :desc) }

  # Callbacks
  before_create :supersede_previous_versions
  after_create :log_acceptance

  # Current document versions (should be managed externally in production)
  CURRENT_VERSIONS = {
    "terms_of_service" => "2.0",
    "privacy_policy" => "2.0",
    "dpa" => "1.0",
    "cookie_policy" => "1.0",
    "acceptable_use" => "1.0"
  }.freeze

  # Class methods
  def self.current_acceptance(user, document_type)
    where(user: user, document_type: document_type)
      .current
      .order(accepted_at: :desc)
      .first
  end

  def self.has_accepted?(user, document_type, version: nil)
    version ||= CURRENT_VERSIONS[document_type]
    return false unless version

    where(user: user, document_type: document_type, document_version: version).exists?
  end

  def self.needs_acceptance?(user)
    CURRENT_VERSIONS.any? do |doc_type, version|
      !has_accepted?(user, doc_type, version: version)
    end
  end

  def self.missing_acceptances(user)
    CURRENT_VERSIONS.reject do |doc_type, version|
      has_accepted?(user, doc_type, version: version)
    end.keys
  end

  def self.record_acceptance(user:, document_type:, version: nil, document_hash: nil, ip_address: nil, user_agent: nil)
    version ||= CURRENT_VERSIONS[document_type]

    create!(
      user: user,
      account: user.account,
      document_type: document_type,
      document_version: version,
      document_hash: document_hash,
      ip_address: ip_address,
      user_agent: user_agent,
      accepted_at: Time.current
    )
  end

  # Instance methods
  def current?
    superseded_at.nil? && document_version == CURRENT_VERSIONS[document_type]
  end

  def superseded?
    superseded_at.present?
  end

  def version_current?
    document_version == CURRENT_VERSIONS[document_type]
  end

  private

  def supersede_previous_versions
    self.class
      .where(user: user, document_type: document_type, superseded_at: nil)
      .where.not(id: id)
      .update_all(superseded_at: Time.current)
  end

  def log_acceptance
    AuditLog.log_compliance_event(
      action: "gdpr_request",
      resource: self,
      user: user,
      account: account,
      ip_address: ip_address,
      metadata: {
        event_type: "terms_accepted",
        document_type: document_type,
        document_version: document_version
      }
    )
  end
end

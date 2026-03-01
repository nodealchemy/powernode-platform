# frozen_string_literal: true

module Ai
  class AgentIdentity < ApplicationRecord
    self.table_name = "ai_agent_identities"

    # ==========================================
    # Constants
    # ==========================================
    STATUSES = %w[active rotated revoked].freeze
    ALGORITHMS = %w[ed25519].freeze

    # ==========================================
    # Associations
    # ==========================================
    belongs_to :account

    # ==========================================
    # Validations
    # ==========================================
    validates :agent_id, presence: true
    validates :public_key, presence: true
    validates :encrypted_private_key, presence: true
    validates :key_fingerprint, presence: true, uniqueness: true
    validates :algorithm, presence: true, inclusion: { in: ALGORITHMS }
    validates :status, presence: true, inclusion: { in: STATUSES }

    # ==========================================
    # Scopes
    # ==========================================
    scope :active, -> { where(status: "active") }
    scope :for_agent, ->(agent_id) { where(agent_id: agent_id) }
    scope :revoked, -> { where(status: "revoked") }
    scope :rotated, -> { where(status: "rotated") }
    scope :expiring_soon, ->(within = 7.days) { where("expires_at IS NOT NULL AND expires_at <= ?", within.from_now) }
    scope :not_expired, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }
    scope :by_fingerprint, ->(fingerprint) { where(key_fingerprint: fingerprint) }

    # ==========================================
    # Callbacks
    # ==========================================
    before_validation :generate_fingerprint, if: -> { public_key.present? && key_fingerprint.blank? }

    # ==========================================
    # Methods
    # ==========================================
    def active?
      status == "active"
    end

    def revoked?
      status == "revoked"
    end

    def rotated?
      status == "rotated"
    end

    def expired?
      expires_at.present? && expires_at <= Time.current
    end

    def within_overlap_window?
      rotation_overlap_until.present? && rotation_overlap_until > Time.current
    end

    def usable?
      (active? || (rotated? && within_overlap_window?)) && !expired?
    end

    private

    def generate_fingerprint
      self.key_fingerprint = Digest::SHA256.hexdigest(public_key)
    end
  end
end

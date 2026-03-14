# frozen_string_literal: true

module SupplyChain
  class VerificationLog < ApplicationRecord
    include Auditable

    self.table_name = "supply_chain_verification_logs"

    # ============================================
    # Constants
    # ============================================
    VERIFICATION_TYPES = %w[full signature rekor predicate chain].freeze
    RESULTS = %w[passed failed skipped].freeze

    # ============================================
    # Associations
    # ============================================
    belongs_to :attestation, class_name: "SupplyChain::Attestation"
    belongs_to :account
    belongs_to :verified_by, class_name: "User", optional: true

    # ============================================
    # Validations
    # ============================================
    validates :verification_type, presence: true, inclusion: { in: VERIFICATION_TYPES }
    validates :result, presence: true, inclusion: { in: RESULTS }
    validates :log_hash, presence: true, uniqueness: true

    # ============================================
    # Scopes
    # ============================================
    scope :by_type, ->(type) { where(verification_type: type) }
    scope :passed, -> { where(result: "passed") }
    scope :failed, -> { where(result: "failed") }
    scope :skipped, -> { where(result: "skipped") }
    scope :recent, -> { order(created_at: :desc) }
    scope :for_attestation, ->(attestation_id) { where(attestation_id: attestation_id) }

    # ============================================
    # Callbacks
    # ============================================
    before_validation :calculate_log_hash, on: :create
    before_save :sanitize_jsonb_fields

    # ============================================
    # Instance Methods
    # ============================================
    def passed?
      result == "passed"
    end

    def failed?
      result == "failed"
    end

    def skipped?
      result == "skipped"
    end

    def chain_valid?
      return true if previous_log_hash.nil?

      previous_log = VerificationLog
                       .where(attestation_id: attestation_id)
                       .where("created_at < ?", created_at)
                       .order(created_at: :desc)
                       .first

      previous_log&.log_hash == previous_log_hash
    end

    def verify_chain_integrity
      logs = attestation.verification_logs.order(created_at: :asc).to_a
      return true if logs.empty?

      logs.each_with_index do |log, index|
        if index == 0
          return false if log.previous_log_hash.present?
        else
          return false if log.previous_log_hash != logs[index - 1].log_hash
        end
      end

      true
    end

    def summary
      {
        id: id,
        attestation_id: attestation_id,
        verification_type: verification_type,
        result: result,
        result_message: result_message,
        log_hash: log_hash,
        chain_valid: chain_valid?,
        verified_by_id: verified_by_id,
        created_at: created_at
      }
    end

    private

    def calculate_log_hash
      return if log_hash.present?

      # Find the previous log for this attestation
      previous = VerificationLog
                   .where(attestation_id: attestation_id)
                   .order(created_at: :desc)
                   .first

      self.previous_log_hash = previous&.log_hash

      # Create tamper-evident hash
      data = {
        attestation_id: attestation_id,
        verification_type: verification_type,
        result: result,
        previous_hash: previous_log_hash,
        details: verification_details,
        timestamp: Time.current.to_i
      }

      self.log_hash = Digest::SHA256.hexdigest(data.to_json)
    end

    def sanitize_jsonb_fields
      self.verification_details ||= {}
      self.metadata ||= {}
    end
  end
end

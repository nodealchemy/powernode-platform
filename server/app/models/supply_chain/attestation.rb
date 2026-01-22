# frozen_string_literal: true

module SupplyChain
  class Attestation < ApplicationRecord
    include Auditable

    self.table_name = "supply_chain_attestations"

    # ============================================
    # Constants
    # ============================================
    ATTESTATION_TYPES = %w[slsa_provenance sbom vuln_scan custom].freeze
    SLSA_LEVELS = [0, 1, 2, 3].freeze
    VERIFICATION_STATUSES = %w[unverified verified failed expired].freeze
    SIGNATURE_FORMATS = %w[dsse jws pgp].freeze
    DIGEST_ALGORITHMS = %w[sha256 sha384 sha512].freeze

    # SLSA Predicate Types
    PREDICATE_TYPES = {
      slsa_provenance_v1: "https://slsa.dev/provenance/v1",
      slsa_provenance_v0_2: "https://slsa.dev/provenance/v0.2",
      sbom_cyclonedx: "https://cyclonedx.org/bom",
      sbom_spdx: "https://spdx.dev/Document",
      vuln_scan: "https://cosign.sigstore.dev/attestation/vuln/v1"
    }.freeze

    # ============================================
    # Associations
    # ============================================
    belongs_to :account
    belongs_to :signing_key, class_name: "SupplyChain::SigningKey", optional: true
    belongs_to :pipeline_run, class_name: "Devops::PipelineRun", optional: true
    belongs_to :sbom, class_name: "SupplyChain::Sbom", optional: true
    belongs_to :created_by, class_name: "User", optional: true

    has_one :build_provenance, class_name: "SupplyChain::BuildProvenance",
            foreign_key: :attestation_id, dependent: :destroy
    has_many :verification_logs, class_name: "SupplyChain::VerificationLog",
             foreign_key: :attestation_id, dependent: :destroy
    has_many :container_images, class_name: "SupplyChain::ContainerImage",
             foreign_key: :attestation_id, dependent: :nullify

    # ============================================
    # Validations
    # ============================================
    validates :attestation_id, presence: true, uniqueness: { scope: :account_id }
    validates :attestation_type, presence: true, inclusion: { in: ATTESTATION_TYPES }
    validates :slsa_level, inclusion: { in: SLSA_LEVELS }, allow_nil: true
    validates :subject_name, presence: true
    validates :subject_digest, presence: true
    validates :subject_digest_algorithm, presence: true, inclusion: { in: DIGEST_ALGORITHMS }
    validates :predicate_type, presence: true
    validates :verification_status, presence: true, inclusion: { in: VERIFICATION_STATUSES }

    # ============================================
    # Scopes
    # ============================================
    scope :by_type, ->(type) { where(attestation_type: type) }
    scope :slsa_provenance, -> { where(attestation_type: "slsa_provenance") }
    scope :sbom_attestations, -> { where(attestation_type: "sbom") }
    scope :verified, -> { where(verification_status: "verified") }
    scope :unverified, -> { where(verification_status: "unverified") }
    scope :failed, -> { where(verification_status: "failed") }
    scope :signed, -> { where.not(signature: nil) }
    scope :with_rekor, -> { where.not(rekor_log_id: nil) }
    scope :by_slsa_level, ->(level) { where(slsa_level: level) }
    scope :by_subject_digest, ->(digest) { where(subject_digest: digest) }
    scope :recent, -> { order(created_at: :desc) }

    # ============================================
    # Callbacks
    # ============================================
    before_validation :generate_attestation_id, on: :create
    before_validation :set_predicate_type
    before_save :sanitize_jsonb_fields

    # ============================================
    # Instance Methods
    # ============================================
    def slsa_provenance?
      attestation_type == "slsa_provenance"
    end

    def sbom_attestation?
      attestation_type == "sbom"
    end

    def vuln_scan?
      attestation_type == "vuln_scan"
    end

    def verified?
      verification_status == "verified"
    end

    def unverified?
      verification_status == "unverified"
    end

    def verification_failed?
      verification_status == "failed"
    end

    def signed?
      signature.present?
    end

    def logged_to_rekor?
      rekor_log_id.present?
    end

    def slsa_compliant?(required_level)
      return false if slsa_level.nil? || slsa_level < required_level
      return false unless signed?
      return false unless verified?

      true
    end

    def subject_uri
      "#{subject_name}@#{subject_digest_algorithm}:#{subject_digest}"
    end

    def sign!(key, signature_data)
      update!(
        signing_key: key,
        signature: signature_data,
        signature_algorithm: key.key_type
      )
    end

    def verify!
      result = perform_verification
      log_verification(result)

      update!(
        verification_status: result[:success] ? "verified" : "failed",
        verification_results: result,
        verified_at: Time.current
      )

      { verified: result[:success], details: result }
    end

    def record_to_rekor!(log_id, log_url)
      update!(
        rekor_log_id: log_id,
        rekor_log_url: log_url,
        rekor_logged_at: Time.current
      )
    end

    def create_provenance!(builder_id:, materials: [], **options)
      SupplyChain::BuildProvenance.create!(
        attestation: self,
        account: account,
        builder_id: builder_id,
        materials: materials,
        **options
      )
    end

    def in_toto_statement
      {
        "_type" => "https://in-toto.io/Statement/v1",
        "subject" => [
          {
            "name" => subject_name,
            "digest" => { subject_digest_algorithm => subject_digest }
          }
        ],
        "predicateType" => predicate_type,
        "predicate" => predicate
      }
    end

    def dsse_envelope
      return nil unless signed?

      payload = Base64.strict_encode64(in_toto_statement.to_json)

      {
        "payloadType" => "application/vnd.in-toto+json",
        "payload" => payload,
        "signatures" => [
          {
            "keyid" => signing_key&.key_id,
            "sig" => signature
          }
        ]
      }
    end

    def summary
      {
        id: id,
        attestation_id: attestation_id,
        attestation_type: attestation_type,
        slsa_level: slsa_level,
        subject_name: subject_name,
        subject_digest: subject_digest,
        predicate_type: predicate_type,
        signed: signed?,
        verified: verified?,
        logged_to_rekor: logged_to_rekor?,
        created_at: created_at
      }
    end

    private

    def generate_attestation_id
      return if attestation_id.present?

      prefix = "att"
      timestamp = Time.current.strftime("%Y%m%d%H%M%S")
      random = SecureRandom.hex(4)
      self.attestation_id = "#{prefix}-#{timestamp}-#{random}"
    end

    def set_predicate_type
      return if predicate_type.present?

      self.predicate_type = case attestation_type
                            when "slsa_provenance"
                              PREDICATE_TYPES[:slsa_provenance_v1]
                            when "sbom"
                              PREDICATE_TYPES[:sbom_cyclonedx]
                            when "vuln_scan"
                              PREDICATE_TYPES[:vuln_scan]
                            else
                              "https://custom.attestation/v1"
                            end
    end

    def sanitize_jsonb_fields
      self.predicate ||= {}
      self.verification_results ||= {}
      self.metadata ||= {}
    end

    def perform_verification
      results = {
        success: true,
        checks: [],
        errors: []
      }

      # Check signature
      if signed?
        sig_valid = verify_signature
        results[:checks] << { name: "signature", passed: sig_valid }
        unless sig_valid
          results[:success] = false
          results[:errors] << "Invalid signature"
        end
      else
        results[:checks] << { name: "signature", passed: false, skipped: true }
      end

      # Check Rekor log
      if logged_to_rekor?
        rekor_valid = verify_rekor_entry
        results[:checks] << { name: "rekor_log", passed: rekor_valid }
        unless rekor_valid
          results[:success] = false
          results[:errors] << "Rekor log verification failed"
        end
      end

      # Check predicate integrity
      predicate_valid = verify_predicate
      results[:checks] << { name: "predicate", passed: predicate_valid }
      unless predicate_valid
        results[:success] = false
        results[:errors] << "Invalid predicate structure"
      end

      results
    end

    def verify_signature
      return false unless signing_key.present? && signature.present?

      # Placeholder for actual signature verification
      # Would use the signing key to verify the signature
      true
    end

    def verify_rekor_entry
      return false unless rekor_log_id.present?

      # Placeholder for Rekor verification
      # Would call the Rekor API to verify the entry
      true
    end

    def verify_predicate
      return false if predicate.blank?

      case attestation_type
      when "slsa_provenance"
        verify_slsa_predicate
      when "sbom"
        verify_sbom_predicate
      else
        true
      end
    end

    def verify_slsa_predicate
      required_fields = %w[buildDefinition runDetails]
      required_fields.all? { |f| predicate.key?(f) }
    end

    def verify_sbom_predicate
      # Basic SBOM structure validation
      predicate.key?("components") || predicate.key?("packages")
    end

    def log_verification(result)
      previous_hash = verification_logs.order(created_at: :desc).first&.log_hash
      current_hash = Digest::SHA256.hexdigest("#{previous_hash}#{result.to_json}#{Time.current.to_i}")

      verification_logs.create!(
        account: account,
        verification_type: "full",
        result: result[:success] ? "passed" : "failed",
        result_message: result[:errors].join("; "),
        previous_log_hash: previous_hash,
        log_hash: current_hash,
        verification_details: result
      )
    end
  end
end

# frozen_string_literal: true

module SupplyChain
  class ContainerImage < ApplicationRecord
    include Auditable

    self.table_name = "supply_chain_container_images"

    # ============================================
    # Constants
    # ============================================
    STATUSES = %w[unverified verified quarantined approved rejected].freeze

    # ============================================
    # Associations
    # ============================================
    belongs_to :account
    belongs_to :attestation, class_name: "SupplyChain::Attestation", optional: true
    belongs_to :sbom, class_name: "SupplyChain::Sbom", optional: true
    belongs_to :base_image, class_name: "SupplyChain::ContainerImage", optional: true

    has_many :derived_images, class_name: "SupplyChain::ContainerImage",
             foreign_key: :base_image_id, dependent: :nullify
    has_many :vulnerability_scans, class_name: "SupplyChain::VulnerabilityScan",
             foreign_key: :container_image_id, dependent: :destroy

    # ============================================
    # Validations
    # ============================================
    validates :registry, presence: true
    validates :repository, presence: true
    validates :digest, presence: true, uniqueness: { scope: :account_id }
    validates :status, presence: true, inclusion: { in: STATUSES }

    # ============================================
    # Scopes
    # ============================================
    scope :by_status, ->(status) { where(status: status) }
    scope :unverified, -> { where(status: "unverified") }
    scope :verified, -> { where(status: "verified") }
    scope :quarantined, -> { where(status: "quarantined") }
    scope :approved, -> { where(status: "approved") }
    scope :rejected, -> { where(status: "rejected") }
    scope :signed, -> { where(is_signed: true) }
    scope :deployed, -> { where(is_deployed: true) }
    scope :by_registry, ->(registry) { where(registry: registry) }
    scope :by_repository, ->(repository) { where(repository: repository) }
    scope :with_critical_vulns, -> { where("critical_vuln_count > 0") }
    scope :with_high_vulns, -> { where("high_vuln_count > 0") }
    scope :clean, -> { where(critical_vuln_count: 0, high_vuln_count: 0) }
    scope :needs_scan, -> { where(last_scanned_at: nil).or(where("last_scanned_at < ?", 24.hours.ago)) }
    scope :recent, -> { order(created_at: :desc) }

    # ============================================
    # Callbacks
    # ============================================
    before_save :sanitize_jsonb_fields

    # ============================================
    # Instance Methods
    # ============================================
    def unverified?
      status == "unverified"
    end

    def verified?
      status == "verified"
    end

    def quarantined?
      status == "quarantined"
    end

    def approved?
      status == "approved"
    end

    def rejected?
      status == "rejected"
    end

    def signed?
      is_signed
    end

    def deployed?
      is_deployed
    end

    def has_critical_vulnerabilities?
      critical_vuln_count > 0
    end

    def has_high_vulnerabilities?
      high_vuln_count > 0
    end

    def total_vulnerability_count
      critical_vuln_count + high_vuln_count + medium_vuln_count + low_vuln_count
    end

    alias_method :total_vulnerabilities, :total_vulnerability_count

    def vulnerability_summary
      {
        critical: critical_vuln_count,
        high: high_vuln_count,
        medium: medium_vuln_count,
        low: low_vuln_count,
        total: total_vulnerability_count
      }
    end

    def exceeds_vulnerability_threshold?(max_critical: nil, max_high: nil, max_medium: nil, max_low: nil)
      return true if max_critical && critical_vuln_count > max_critical
      return true if max_high && high_vuln_count > max_high
      return true if max_medium && medium_vuln_count > max_medium
      return true if max_low && low_vuln_count > max_low

      false
    end

    def needs_scan?
      last_scanned_at.nil? || last_scanned_at < 24.hours.ago
    end

    def full_reference
      if tag.present?
        "#{registry}/#{repository}:#{tag}"
      else
        "#{registry}/#{repository}@#{digest}"
      end
    end

    def short_digest
      digest.split(":").last[0..11] if digest.present?
    end

    def verify!
      update!(status: "verified")
    end

    def quarantine!(reason = nil)
      update!(
        status: "quarantined",
        metadata: metadata.merge("quarantine_reason" => reason)
      )
    end

    def approve!
      update!(status: "approved")
    end

    def reject!(reason = nil)
      update!(
        status: "rejected",
        metadata: metadata.merge("rejection_reason" => reason)
      )
    end

    def mark_deployed!(contexts = [])
      update!(
        is_deployed: true,
        deployment_contexts: (deployment_contexts + contexts).uniq
      )
    end

    def mark_undeployed!
      update!(
        is_deployed: false,
        deployment_contexts: []
      )
    end

    def update_vulnerability_counts!(critical: 0, high: 0, medium: 0, low: 0)
      update!(
        critical_vuln_count: critical,
        high_vuln_count: high,
        medium_vuln_count: medium,
        low_vuln_count: low,
        last_scanned_at: Time.current
      )
    end

    def latest_scan
      vulnerability_scans.order(created_at: :desc).first
    end

    def layer_count
      layers&.length || 0
    end

    def formatted_size
      return nil unless size_bytes.present?

      if size_bytes >= 1_073_741_824
        "#{(size_bytes / 1_073_741_824.0).round(2)} GB"
      elsif size_bytes >= 1_048_576
        "#{(size_bytes / 1_048_576.0).round(2)} MB"
      else
        "#{(size_bytes / 1024.0).round(2)} KB"
      end
    end

    def summary
      {
        id: id,
        registry: registry,
        repository: repository,
        tag: tag,
        digest: digest,
        short_digest: short_digest,
        full_reference: full_reference,
        status: status,
        is_signed: is_signed,
        is_deployed: is_deployed,
        vulnerability_counts: {
          critical: critical_vuln_count,
          high: high_vuln_count,
          medium: medium_vuln_count,
          low: low_vuln_count,
          total: total_vulnerability_count
        },
        size_bytes: size_bytes,
        formatted_size: formatted_size,
        layer_count: layer_count,
        last_scanned_at: last_scanned_at,
        created_at: created_at
      }
    end

    private

    def sanitize_jsonb_fields
      self.layers ||= []
      self.deployment_contexts ||= []
      self.labels ||= {}
      self.metadata ||= {}
    end
  end
end

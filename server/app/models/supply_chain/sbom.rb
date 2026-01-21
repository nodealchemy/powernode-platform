# frozen_string_literal: true

module SupplyChain
  class Sbom < ApplicationRecord
    include Auditable

    self.table_name = "supply_chain_sboms"

    # ============================================
    # Constants
    # ============================================
    FORMATS = %w[spdx_2_3 cyclonedx_1_4 cyclonedx_1_5 cyclonedx_1_6].freeze
    STATUSES = %w[draft generating completed failed archived].freeze

    # ============================================
    # Associations
    # ============================================
    belongs_to :account
    belongs_to :repository, class_name: "Devops::Repository", optional: true
    belongs_to :pipeline_run, class_name: "Devops::PipelineRun", optional: true
    belongs_to :created_by, class_name: "User", optional: true

    has_many :components, class_name: "SupplyChain::SbomComponent",
             foreign_key: :sbom_id, dependent: :destroy
    has_many :vulnerabilities, class_name: "SupplyChain::SbomVulnerability",
             foreign_key: :sbom_id, dependent: :destroy
    has_many :attestations, class_name: "SupplyChain::Attestation",
             foreign_key: :sbom_id, dependent: :nullify
    has_many :remediation_plans, class_name: "SupplyChain::RemediationPlan",
             foreign_key: :sbom_id, dependent: :destroy
    has_many :license_violations, class_name: "SupplyChain::LicenseViolation",
             foreign_key: :sbom_id, dependent: :destroy
    has_many :reports, class_name: "SupplyChain::Report",
             foreign_key: :sbom_id, dependent: :nullify

    has_many :base_diffs, class_name: "SupplyChain::SbomDiff",
             foreign_key: :base_sbom_id, dependent: :destroy
    has_many :target_diffs, class_name: "SupplyChain::SbomDiff",
             foreign_key: :target_sbom_id, dependent: :destroy
    has_many :diffs, ->(sbom) { unscope(:where).where(base_sbom_id: sbom.id).or(where(target_sbom_id: sbom.id)) },
             class_name: "SupplyChain::SbomDiff"

    # ============================================
    # Validations
    # ============================================
    validates :sbom_id, presence: true, uniqueness: { scope: :account_id }
    validates :format, presence: true, inclusion: { in: FORMATS }
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :component_count, numericality: { greater_than_or_equal_to: 0 }
    validates :vulnerability_count, numericality: { greater_than_or_equal_to: 0 }
    validates :risk_score, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }

    # ============================================
    # Scopes
    # ============================================
    scope :by_status, ->(status) { where(status: status) }
    scope :completed, -> { where(status: "completed") }
    scope :draft, -> { where(status: "draft") }
    scope :failed, -> { where(status: "failed") }
    scope :recent, -> { order(created_at: :desc) }
    scope :by_repository, ->(repo_id) { where(repository_id: repo_id) }
    scope :by_format, ->(format) { where(format: format) }
    scope :ntia_compliant, -> { where(ntia_minimum_compliant: true) }
    scope :with_vulnerabilities, -> { where("vulnerability_count > 0") }
    scope :high_risk, -> { where("risk_score >= ?", 70) }

    # ============================================
    # Callbacks
    # ============================================
    before_validation :generate_sbom_id, on: :create
    before_save :sanitize_jsonb_fields
    after_save :update_counters, if: :saved_change_to_document?

    # ============================================
    # Instance Methods
    # ============================================
    def draft?
      status == "draft"
    end

    def generating?
      status == "generating"
    end

    def completed?
      status == "completed"
    end

    def failed?
      status == "failed"
    end

    def archived?
      status == "archived"
    end

    def cyclonedx?
      format.start_with?("cyclonedx")
    end

    def spdx?
      format.start_with?("spdx")
    end

    def signed?
      signature.present?
    end

    def start_generation!
      update!(status: "generating")
    end

    def complete_generation!(document_data, component_count: nil, vuln_count: nil)
      attrs = {
        status: "completed",
        document: document_data,
        document_hash: calculate_document_hash(document_data)
      }
      attrs[:component_count] = component_count if component_count
      attrs[:vulnerability_count] = vuln_count if vuln_count
      update!(attrs)
    end

    def fail_generation!(error_message = nil)
      update!(
        status: "failed",
        metadata: metadata.merge("error" => error_message)
      )
    end

    def archive!
      update!(status: "archived")
    end

    def sign!(signing_key, signature_data)
      update!(
        signature: signature_data,
        signature_algorithm: signing_key.key_type
      )
    end

    def verify_ntia_compliance
      # Check NTIA minimum elements
      required_fields = %w[
        supplier_name
        component_name
        component_version
        unique_identifier
        dependency_relationship
        author_name
        timestamp
      ]

      compliant = required_fields.all? { |field| ntia_field_present?(field) }
      update!(ntia_minimum_compliant: compliant)
      compliant
    end

    def diff_with(other_sbom)
      SupplyChain::SbomDiff.create!(
        account: account,
        base_sbom: self,
        target_sbom: other_sbom
      )
    end

    def export(format: nil)
      export_format = format || self.format
      case export_format
      when /cyclonedx/
        export_cyclonedx
      when /spdx/
        export_spdx
      else
        document
      end
    end

    def vulnerability_summary
      counts = vulnerabilities.group(:severity).count
      {
        critical: counts["critical"] || 0,
        high: counts["high"] || 0,
        medium: counts["medium"] || 0,
        low: counts["low"] || 0,
        total: vulnerability_count
      }
    end

    def summary
      {
        id: id,
        sbom_id: sbom_id,
        name: name,
        version: version,
        format: self.format,
        status: status,
        component_count: component_count,
        vulnerability_count: vulnerability_count,
        risk_score: risk_score,
        ntia_compliant: ntia_minimum_compliant,
        signed: signed?,
        created_at: created_at
      }
    end

    private

    def generate_sbom_id
      return if sbom_id.present?

      prefix = "sbom"
      timestamp = Time.current.strftime("%Y%m%d%H%M%S")
      random = SecureRandom.hex(4)
      self.sbom_id = "#{prefix}-#{timestamp}-#{random}"
    end

    def sanitize_jsonb_fields
      self.document ||= {}
      self.metadata ||= {}
    end

    def calculate_document_hash(doc)
      Digest::SHA256.hexdigest(doc.to_json)
    end

    def update_counters
      # Update component and vulnerability counts from document
      if document.present?
        count = document.dig("components")&.length || 0
        update_column(:component_count, count) if count != component_count
      end
    end

    def ntia_field_present?(field)
      case field
      when "supplier_name"
        document.dig("metadata", "supplier", "name").present?
      when "component_name"
        components.any? || document.dig("components")&.any?
      when "component_version"
        components.where.not(version: nil).any? || document.dig("components")&.any? { |c| c["version"].present? }
      when "unique_identifier"
        components.where.not(purl: nil).any? || document.dig("components")&.any? { |c| c["purl"].present? || c["bom-ref"].present? }
      when "dependency_relationship"
        document.dig("dependencies").present?
      when "author_name"
        document.dig("metadata", "authors")&.any? || created_by.present?
      when "timestamp"
        document.dig("metadata", "timestamp").present? || created_at.present?
      else
        false
      end
    end

    def export_cyclonedx
      document.merge(
        "bomFormat" => "CycloneDX",
        "specVersion" => format.split("_").last.tr("_", "."),
        "serialNumber" => "urn:uuid:#{sbom_id}",
        "version" => 1
      )
    end

    def export_spdx
      document.merge(
        "spdxVersion" => "SPDX-#{format.split("_").last.tr("_", ".")}",
        "SPDXID" => "SPDXRef-DOCUMENT",
        "name" => name || sbom_id,
        "documentNamespace" => "https://spdx.org/spdxdocs/#{sbom_id}"
      )
    end
  end
end

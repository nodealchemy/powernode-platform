# frozen_string_literal: true

module SupplyChain
  class SbomComponent < ApplicationRecord
    include Auditable

    self.table_name = "supply_chain_sbom_components"

    # ============================================
    # Constants
    # ============================================
    DEPENDENCY_TYPES = %w[direct transitive dev optional peer].freeze
    ECOSYSTEMS = %w[npm gem pip maven gradle go cargo nuget composer hex pub cocoapods swift other].freeze
    LICENSE_COMPLIANCE_STATUSES = %w[compliant non_compliant unknown review_required].freeze

    # ============================================
    # Associations
    # ============================================
    belongs_to :sbom, class_name: "SupplyChain::Sbom"
    belongs_to :account

    has_many :vulnerabilities, class_name: "SupplyChain::SbomVulnerability",
             foreign_key: :component_id, dependent: :destroy
    has_many :license_detections, class_name: "SupplyChain::LicenseDetection",
             foreign_key: :sbom_component_id, dependent: :destroy
    has_many :license_violations, class_name: "SupplyChain::LicenseViolation",
             foreign_key: :sbom_component_id, dependent: :destroy
    has_one :attribution, class_name: "SupplyChain::Attribution",
            foreign_key: :sbom_component_id, dependent: :destroy

    # ============================================
    # Validations
    # ============================================
    validates :purl, presence: true, uniqueness: { scope: :sbom_id }
    validates :name, presence: true
    validates :ecosystem, presence: true, inclusion: { in: ECOSYSTEMS }
    validates :dependency_type, presence: true, inclusion: { in: DEPENDENCY_TYPES }
    validates :depth, numericality: { greater_than_or_equal_to: 0 }
    validates :risk_score, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }

    # ============================================
    # Scopes
    # ============================================
    scope :by_ecosystem, ->(ecosystem) { where(ecosystem: ecosystem) }
    scope :direct, -> { where(dependency_type: "direct") }
    scope :transitive, -> { where(dependency_type: "transitive") }
    scope :dev_dependencies, -> { where(dependency_type: "dev") }
    scope :vulnerable, -> { where(has_known_vulnerabilities: true) }
    scope :outdated, -> { where(is_outdated: true) }
    scope :high_risk, -> { where("risk_score >= ?", 70) }
    scope :by_license, ->(spdx_id) { where(license_spdx_id: spdx_id) }
    scope :unlicensed, -> { where(license_spdx_id: nil) }
    scope :ordered_by_risk, -> { order(risk_score: :desc) }
    scope :ordered_by_depth, -> { order(depth: :asc) }

    # ============================================
    # Callbacks
    # ============================================
    before_validation :parse_purl
    before_save :sanitize_jsonb_fields
    after_save :update_sbom_counters, if: :saved_change_to_has_known_vulnerabilities?

    # ============================================
    # Instance Methods
    # ============================================
    def direct?
      dependency_type == "direct"
    end

    def transitive?
      dependency_type == "transitive"
    end

    def dev?
      dependency_type == "dev"
    end

    def vulnerable?
      has_known_vulnerabilities
    end

    def outdated?
      is_outdated
    end

    def license_compliant?
      license_compliance_status == "compliant"
    end

    def license
      return nil unless license_spdx_id.present?

      @license ||= SupplyChain::License.find_by_spdx(license_spdx_id)
    end

    def needs_license_review?
      license_compliance_status == "review_required" || license_compliance_status == "unknown"
    end

    def full_name
      namespace.present? ? "#{namespace}/#{name}" : name
    end

    def versioned_name
      "#{full_name}@#{version || 'unknown'}"
    end

    def critical_vulnerabilities
      vulnerabilities.where(severity: "critical")
    end

    def high_vulnerabilities
      vulnerabilities.where(severity: "high")
    end

    def calculate_risk_score
      base_score = 0

      # Vulnerability factor (0-50 points)
      vuln_score = vulnerabilities.sum do |v|
        case v.severity
        when "critical" then 20
        when "high" then 10
        when "medium" then 5
        when "low" then 2
        else 0
        end
      end
      base_score += [vuln_score, 50].min

      # License risk factor (0-20 points)
      case license_compliance_status
      when "non_compliant" then base_score += 20
      when "unknown" then base_score += 10
      when "review_required" then base_score += 5
      end

      # Outdated factor (0-15 points)
      base_score += 15 if is_outdated

      # Transitive dependency factor (0-15 points)
      base_score += [depth * 3, 15].min if transitive?

      self.risk_score = [base_score, 100].min
    end

    def check_for_updates
      # This would be implemented by calling package registry APIs
      # Placeholder for version checking logic
      false
    end

    def summary
      {
        id: id,
        purl: purl,
        name: full_name,
        version: version,
        ecosystem: ecosystem,
        dependency_type: dependency_type,
        depth: depth,
        license: license_spdx_id,
        license_compliant: license_compliant?,
        vulnerable: vulnerable?,
        vulnerability_count: vulnerabilities.count,
        risk_score: risk_score
      }
    end

    def to_cyclonedx
      {
        "type" => component_type_for_cyclonedx,
        "bom-ref" => purl,
        "name" => name,
        "version" => version,
        "purl" => purl,
        "licenses" => license_spdx_id ? [{ "license" => { "id" => license_spdx_id } }] : [],
        "properties" => [
          { "name" => "dependency:type", "value" => dependency_type },
          { "name" => "dependency:depth", "value" => depth.to_s }
        ]
      }
    end

    def to_spdx
      {
        "SPDXID" => "SPDXRef-#{Digest::SHA256.hexdigest(purl)[0..15]}",
        "name" => name,
        "versionInfo" => version,
        "downloadLocation" => "NOASSERTION",
        "licenseConcluded" => license_spdx_id || "NOASSERTION",
        "licenseDeclared" => license_spdx_id || "NOASSERTION",
        "copyrightText" => "NOASSERTION",
        "externalRefs" => [
          {
            "referenceCategory" => "PACKAGE-MANAGER",
            "referenceType" => "purl",
            "referenceLocator" => purl
          }
        ]
      }
    end

    private

    def sanitize_jsonb_fields
      self.metadata ||= {}
      self.properties ||= {}
    end

    def parse_purl
      return unless purl.present? && purl_changed?

      # Parse Package URL (purl) format: pkg:type/namespace/name@version
      match = purl.match(%r{^pkg:([^/]+)/(?:([^/]+)/)?([^@]+)(?:@(.+))?$})
      return unless match

      detected_type, detected_namespace, detected_name, detected_version = match.captures

      self.ecosystem = map_purl_type_to_ecosystem(detected_type) if ecosystem.blank?
      self.namespace = detected_namespace if namespace.blank?
      self.name = detected_name if name.blank? || name == detected_name
      self.version = detected_version if version.blank? && detected_version.present?
    end

    def map_purl_type_to_ecosystem(purl_type)
      mapping = {
        "npm" => "npm",
        "gem" => "gem",
        "pypi" => "pip",
        "maven" => "maven",
        "gradle" => "gradle",
        "golang" => "go",
        "cargo" => "cargo",
        "nuget" => "nuget",
        "composer" => "composer",
        "hex" => "hex",
        "pub" => "pub",
        "cocoapods" => "cocoapods",
        "swift" => "swift"
      }
      mapping[purl_type] || "other"
    end

    def component_type_for_cyclonedx
      case ecosystem
      when "npm", "gem", "pip", "maven", "gradle", "cargo", "nuget", "composer", "hex", "pub"
        "library"
      when "go"
        "library"
      when "cocoapods", "swift"
        "framework"
      else
        "library"
      end
    end

    def update_sbom_counters
      sbom.update_column(:vulnerability_count, sbom.vulnerabilities.count)
    end
  end
end

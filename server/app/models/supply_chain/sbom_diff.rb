# frozen_string_literal: true

module SupplyChain
  class SbomDiff < ApplicationRecord
    include Auditable

    self.table_name = "supply_chain_sbom_diffs"

    # ============================================
    # Associations
    # ============================================
    belongs_to :account
    belongs_to :base_sbom, class_name: "SupplyChain::Sbom"
    belongs_to :target_sbom, class_name: "SupplyChain::Sbom"

    # ============================================
    # Validations
    # ============================================
    validates :base_sbom_id, uniqueness: { scope: :target_sbom_id }
    validate :sboms_belong_to_same_account

    # ============================================
    # Scopes
    # ============================================
    scope :recent, -> { order(created_at: :desc) }
    scope :with_changes, -> { where("added_count > 0 OR removed_count > 0 OR updated_count > 0") }
    scope :with_new_vulnerabilities, -> { where("new_vulnerabilities IS NOT NULL AND jsonb_array_length(new_vulnerabilities) > 0") }
    scope :risk_increased, -> { where("risk_delta > 0") }
    scope :risk_decreased, -> { where("risk_delta < 0") }

    # ============================================
    # Callbacks
    # ============================================
    before_validation :set_account_from_base_sbom
    before_save :sanitize_jsonb_fields
    after_create :compute_diff

    # ============================================
    # JSONB Accessors (handle proper type conversions after reload)
    # ============================================
    %i[added_components removed_components updated_components new_vulnerabilities resolved_vulnerabilities].each do |attr|
      define_method(attr) do
        value = read_attribute(attr)
        value.is_a?(Array) ? value : []
      end
    end

    def metadata
      value = read_attribute(:metadata)
      value.is_a?(Hash) ? value : {}
    end

    # ============================================
    # Instance Methods
    # ============================================
    def has_changes?
      added_count > 0 || removed_count > 0 || updated_count > 0
    end

    def has_new_vulnerabilities?
      new_vulnerabilities.present? && new_vulnerabilities.any?
    end

    def has_resolved_vulnerabilities?
      resolved_vulnerabilities.present? && resolved_vulnerabilities.any?
    end

    def risk_increased?
      risk_delta.present? && risk_delta > 0
    end

    def risk_decreased?
      risk_delta.present? && risk_delta < 0
    end

    def total_changes
      added_count + removed_count + updated_count
    end

    def compute_diff
      return if @skip_compute_diff

      base_components = build_component_map(base_sbom)
      target_components = build_component_map(target_sbom)

      added = []
      removed = []
      updated = []

      # Find added and updated components
      target_components.each do |key, target_comp|
        if base_components[key].nil?
          added << component_summary(target_comp)
        elsif base_components[key][:version] != target_comp[:version]
          updated << {
            purl: target_comp[:purl],
            name: target_comp[:name],
            old_version: base_components[key][:version],
            new_version: target_comp[:version],
            ecosystem: target_comp[:ecosystem]
          }
        end
      end

      # Find removed components
      base_components.each do |key, base_comp|
        if target_components[key].nil?
          removed << component_summary(base_comp)
        end
      end

      # Find vulnerability changes
      base_vulns = base_sbom.vulnerabilities.pluck(:vulnerability_id).to_set
      target_vulns = target_sbom.vulnerabilities.pluck(:vulnerability_id).to_set

      new_vulns = (target_vulns - base_vulns).map do |vuln_id|
        vuln = target_sbom.vulnerabilities.find_by(vulnerability_id: vuln_id)
        vulnerability_summary(vuln) if vuln
      end.compact

      resolved_vulns = (base_vulns - target_vulns).map do |vuln_id|
        vuln = base_sbom.vulnerabilities.find_by(vulnerability_id: vuln_id)
        vulnerability_summary(vuln) if vuln
      end.compact

      # Calculate risk delta
      delta = target_sbom.risk_score.to_f - base_sbom.risk_score.to_f

      update!(
        added_components: added,
        removed_components: removed,
        updated_components: updated,
        new_vulnerabilities: new_vulns,
        resolved_vulnerabilities: resolved_vulns,
        added_count: added.length,
        removed_count: removed.length,
        updated_count: updated.length,
        risk_delta: delta.round(2)
      )
    end

    def summary
      {
        id: id,
        base_sbom_id: base_sbom_id,
        target_sbom_id: target_sbom_id,
        added_count: added_count,
        removed_count: removed_count,
        updated_count: updated_count,
        new_vulnerability_count: new_vulnerabilities&.length || 0,
        resolved_vulnerability_count: resolved_vulnerabilities&.length || 0,
        risk_delta: risk_delta,
        has_changes: has_changes?,
        created_at: created_at
      }
    end

    def detailed_report
      {
        summary: summary,
        added_components: added_components,
        removed_components: removed_components,
        updated_components: updated_components,
        new_vulnerabilities: new_vulnerabilities,
        resolved_vulnerabilities: resolved_vulnerabilities
      }
    end

    private

    def sboms_belong_to_same_account
      return if base_sbom.nil? || target_sbom.nil?

      if base_sbom.account_id != target_sbom.account_id
        errors.add(:base, "SBOMs must belong to the same account")
      end
    end

    def set_account_from_base_sbom
      self.account ||= base_sbom&.account
    end

    def sanitize_jsonb_fields
      self.added_components ||= []
      self.removed_components ||= []
      self.updated_components ||= []
      self.new_vulnerabilities ||= []
      self.resolved_vulnerabilities ||= []
      self.metadata ||= {}
    end

    def build_component_map(sbom)
      sbom.components.each_with_object({}) do |comp, map|
        # Use version-less key for comparison to detect updates
        key = component_comparison_key(comp)
        map[key] = {
          purl: comp.purl,
          name: comp.full_name,
          version: comp.version,
          ecosystem: comp.ecosystem,
          license: comp.license_spdx_id,
          risk_score: comp.risk_score
        }
      end
    end

    # Returns a version-less key for component comparison
    # Uses ecosystem/namespace/name to uniquely identify a component across versions
    def component_comparison_key(comp)
      [comp.ecosystem, comp.namespace, comp.name].compact.join("/")
    end

    def component_summary(comp)
      {
        purl: comp[:purl],
        name: comp[:name],
        version: comp[:version],
        ecosystem: comp[:ecosystem],
        license: comp[:license]
      }
    end

    def vulnerability_summary(vuln)
      return nil unless vuln

      {
        vulnerability_id: vuln.vulnerability_id,
        severity: vuln.severity,
        cvss_score: vuln.cvss_score,
        component_purl: vuln.component.purl,
        component_name: vuln.component.full_name,
        has_fix: vuln.has_fix?,
        fixed_version: vuln.fixed_version
      }
    end
  end
end

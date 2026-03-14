# frozen_string_literal: true

module SupplyChain
  class RiskCalculationService
    class CalculationError < StandardError; end

    # Risk weights for different factors
    VULNERABILITY_WEIGHTS = {
      critical: 25,
      high: 15,
      medium: 5,
      low: 1
    }.freeze

    LICENSE_RISK_WEIGHTS = {
      strong_copyleft: 20,
      weak_copyleft: 10,
      unknown: 15,
      non_compliant: 25
    }.freeze

    DEPENDENCY_RISK_WEIGHTS = {
      outdated: 10,
      unmaintained: 15,
      deep_transitive: 5
    }.freeze

    attr_reader :sbom

    def initialize(sbom:)
      @sbom = sbom
      @logger = Rails.logger
    end

    def calculate!
      scores = {
        vulnerability_score: calculate_vulnerability_score,
        license_score: calculate_license_score,
        dependency_score: calculate_dependency_score,
        supply_chain_score: calculate_supply_chain_score
      }

      # Weighted average
      overall_score = (
        (scores[:vulnerability_score] * 0.4) +
        (scores[:license_score] * 0.2) +
        (scores[:dependency_score] * 0.2) +
        (scores[:supply_chain_score] * 0.2)
      ).round(2)

      sbom.update!(
        risk_score: overall_score,
        metadata: sbom.metadata.merge(
          "risk_breakdown" => scores,
          "risk_calculated_at" => Time.current.iso8601
        )
      )

      # Update component risk scores
      update_component_risk_scores

      overall_score
    end

    def calculate_contextual_vulnerability_scores
      sbom.vulnerabilities.find_each do |vuln|
        contextual_score = calculate_contextual_score(vuln)
        context_factors = build_context_factors(vuln)

        vuln.update!(
          contextual_score: contextual_score,
          context_factors: context_factors
        )
      end
    end

    private

    def calculate_vulnerability_score
      return 0 if sbom.vulnerabilities.empty?

      max_score = 100
      penalty = 0

      # Count vulnerabilities by severity
      critical_count = sbom.vulnerabilities.where(severity: "critical").count
      high_count = sbom.vulnerabilities.where(severity: "high").count
      medium_count = sbom.vulnerabilities.where(severity: "medium").count
      low_count = sbom.vulnerabilities.where(severity: "low").count

      penalty += critical_count * VULNERABILITY_WEIGHTS[:critical]
      penalty += high_count * VULNERABILITY_WEIGHTS[:high]
      penalty += medium_count * VULNERABILITY_WEIGHTS[:medium]
      penalty += low_count * VULNERABILITY_WEIGHTS[:low]

      # Additional penalty for unfixed critical vulnerabilities
      unfixed_critical = sbom.vulnerabilities
                             .where(severity: "critical", remediation_status: "open")
                             .where(fixed_version: nil)
                             .count
      penalty += unfixed_critical * 10

      [ penalty, max_score ].min
    end

    def calculate_license_score
      return 0 if sbom.components.empty?

      max_score = 100
      penalty = 0

      # Check license compliance
      sbom.components.find_each do |component|
        license = SupplyChain::License.find_by_spdx(component.license_spdx_id)

        if license.nil? && component.license_spdx_id.blank?
          penalty += LICENSE_RISK_WEIGHTS[:unknown]
        elsif license&.strong_copyleft?
          penalty += LICENSE_RISK_WEIGHTS[:strong_copyleft]
        elsif license&.weak_copyleft?
          penalty += LICENSE_RISK_WEIGHTS[:weak_copyleft]
        end
      end

      # Check for license violations
      violation_count = sbom.license_violations.where(status: "open").count
      penalty += violation_count * LICENSE_RISK_WEIGHTS[:non_compliant]

      [ penalty, max_score ].min
    end

    def calculate_dependency_score
      return 0 if sbom.components.empty?

      max_score = 100
      penalty = 0

      total_components = sbom.components.count
      outdated_count = sbom.components.where(is_outdated: true).count
      deep_transitive = sbom.components.where("depth > ?", 3).count

      # Outdated dependencies
      if total_components > 0
        outdated_ratio = outdated_count.to_f / total_components
        penalty += (outdated_ratio * DEPENDENCY_RISK_WEIGHTS[:outdated] * 10).round
      end

      # Deep transitive dependencies (harder to audit)
      if total_components > 0
        deep_ratio = deep_transitive.to_f / total_components
        penalty += (deep_ratio * DEPENDENCY_RISK_WEIGHTS[:deep_transitive] * 5).round
      end

      # Too many dependencies
      if total_components > 500
        penalty += 10
      elsif total_components > 200
        penalty += 5
      end

      [ penalty, max_score ].min
    end

    def calculate_supply_chain_score
      score = 0

      # Check if SBOM is signed
      score += 15 unless sbom.signed?

      # Check for attestation
      score += 15 if sbom.attestations.empty?

      # Check for complete NTIA compliance
      score += 10 unless sbom.ntia_minimum_compliant

      # Check direct dependency count
      direct_deps = sbom.components.where(dependency_type: "direct").count
      score += 10 if direct_deps > 100

      [ score, 100 ].min
    end

    def update_component_risk_scores
      sbom.components.find_each do |component|
        component.calculate_risk_score
        component.save! if component.risk_score_changed?
      end
    end

    def calculate_contextual_score(vuln)
      base_score = vuln.cvss_score || severity_to_score(vuln.severity)
      adjustment = 0

      # Exploitability factors (increase score)
      adjustment += 1.5 if exploit_in_wild?(vuln)
      adjustment += 1.0 if poc_available?(vuln)

      # Reachability factors (decrease score)
      adjustment -= 1.0 unless code_path_reachable?(vuln)
      adjustment -= 0.5 if behind_authentication?(vuln)

      # Dependency depth (transitive deps are harder to exploit)
      adjustment -= 0.3 * vuln.component.depth.to_i

      # Age factor
      if vuln.published_at.present? && vuln.published_at > 30.days.ago
        adjustment += 0.5
      end

      [ [ base_score + adjustment, 0 ].max, 10 ].min.round(2)
    end

    def build_context_factors(vuln)
      {
        exploit_in_wild: exploit_in_wild?(vuln),
        poc_available: poc_available?(vuln),
        code_reachable: code_path_reachable?(vuln),
        behind_auth: behind_authentication?(vuln),
        dependency_depth: vuln.component.depth,
        is_direct_dependency: vuln.component.direct?,
        has_fix_available: vuln.fixed_version.present?,
        age_days: vuln.published_at.present? ? (Date.current - vuln.published_at.to_date).to_i : nil
      }
    end

    def severity_to_score(severity)
      case severity
      when "critical" then 9.0
      when "high" then 7.0
      when "medium" then 5.0
      when "low" then 3.0
      else 0.0
      end
    end

    def exploit_in_wild?(vuln)
      # Check if vulnerability has known exploits in the wild
      # This would integrate with threat intelligence feeds
      vuln.metadata&.dig("exploit_in_wild") == true
    end

    def poc_available?(vuln)
      # Check if proof of concept exists
      vuln.metadata&.dig("poc_available") == true ||
        vuln.references&.any? { |r| r.to_s.include?("exploit") || r.to_s.include?("poc") }
    end

    def code_path_reachable?(vuln)
      # Check if the vulnerable code path is reachable
      # This would require static analysis
      # Default to true (assume reachable) to be conservative
      vuln.metadata&.dig("code_reachable") != false
    end

    def behind_authentication?(vuln)
      # Check if the vulnerable component is behind authentication
      vuln.metadata&.dig("behind_auth") == true
    end
  end
end

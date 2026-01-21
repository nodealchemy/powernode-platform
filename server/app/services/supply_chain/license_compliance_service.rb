# frozen_string_literal: true

module SupplyChain
  class LicenseComplianceService
    class ComplianceError < StandardError; end

    attr_reader :account, :sbom, :options

    def initialize(account:, sbom: nil, options: {})
      @account = account
      @sbom = sbom
      @options = options.with_indifferent_access
      @logger = Rails.logger
    end

    def evaluate!
      return { compliant: true, violations: [] } unless sbom.present?

      policy = get_policy
      return { compliant: true, violations: [], policy: nil } unless policy.present?

      violations = []

      sbom.components.find_each do |component|
        result = policy.evaluate_component(component)

        unless result[:compliant]
          violations << create_violation(component, policy, result)
        end

        # Update component compliance status
        update_component_compliance_status(component, result)
      end

      {
        compliant: violations.empty?,
        violations: violations,
        policy: policy.summary,
        violation_count: violations.length
      }
    end

    def evaluate_component(component, policy: nil)
      policy ||= get_policy
      return { compliant: true } unless policy.present?

      result = policy.evaluate_component(component)
      update_component_compliance_status(component, result)

      result
    end

    def check_gpl_contamination
      return { contaminated: false, sources: [] } unless sbom.present?

      gpl_components = []

      sbom.components.find_each do |component|
        license = SupplyChain::License.find_by_spdx(component.license_spdx_id)
        next unless license&.strong_copyleft?

        gpl_components << {
          component: component.versioned_name,
          purl: component.purl,
          license: license.spdx_id,
          dependency_type: component.dependency_type,
          depth: component.depth
        }
      end

      {
        contaminated: gpl_components.any?,
        sources: gpl_components,
        contamination_count: gpl_components.length
      }
    end

    def generate_notice_file
      return nil unless sbom.present?

      # Ensure attributions exist for all components
      SupplyChain::Attribution.generate_for_sbom(sbom)

      attributions = sbom.components.includes(:attribution).map(&:attribution).compact
      SupplyChain::Attribution.generate_notice_file(attributions)
    end

    def detect_licenses
      return [] unless sbom.present?

      detections = []

      sbom.components.find_each do |component|
        detection_results = detect_license_for_component(component)
        detections.concat(detection_results)
      end

      detections
    end

    private

    def get_policy
      policy_id = options[:policy_id]

      if policy_id.present?
        account.supply_chain_license_policies.find_by(id: policy_id)
      else
        SupplyChain::LicensePolicy.default_for_account(account)
      end
    end

    def create_violation(component, policy, evaluation_result)
      violation_type = determine_violation_type(evaluation_result[:violations])
      severity = determine_severity(violation_type, component)

      violation = SupplyChain::LicenseViolation.create!(
        account: account,
        sbom: sbom,
        sbom_component: component,
        license_policy: policy,
        license: SupplyChain::License.find_by_spdx(component.license_spdx_id),
        violation_type: violation_type,
        severity: severity,
        status: "open",
        description: evaluation_result[:violations].map { |v| v[:message] }.join("; ")
      )

      violation.summary
    end

    def determine_violation_type(violations)
      types = violations.map { |v| v[:type] }

      if types.include?("denied")
        "denied"
      elsif types.include?("copyleft") || types.include?("strong_copyleft")
        "copyleft"
      elsif types.include?("incompatible")
        "incompatible"
      elsif types.include?("unknown")
        "unknown"
      else
        "denied"
      end
    end

    def determine_severity(violation_type, component)
      base_severity = case violation_type
                      when "denied" then "high"
                      when "copyleft" then "high"
                      when "incompatible" then "medium"
                      when "unknown" then "medium"
                      else "low"
                      end

      # Increase severity for direct dependencies
      if component.direct? && base_severity != "critical"
        case base_severity
        when "high" then "critical"
        when "medium" then "high"
        when "low" then "medium"
        else base_severity
        end
      else
        base_severity
      end
    end

    def update_component_compliance_status(component, result)
      status = if result[:compliant]
                 "compliant"
               elsif result[:violations]&.any? { |v| v[:type] == "unknown" }
                 "unknown"
               else
                 "non_compliant"
               end

      component.update!(license_compliance_status: status) if component.license_compliance_status != status
    end

    def detect_license_for_component(component)
      detections = []

      # Check if we already have detections
      return detections if component.license_detections.any?

      # Detection from component metadata (manifest)
      if component.license_spdx_id.present?
        detections << create_detection(
          component,
          license_id: component.license_spdx_id,
          license_name: component.license_name,
          source: "manifest",
          confidence: 0.9
        )
      end

      # AI-based detection could be added here
      # detections.concat(detect_with_ai(component))

      detections
    end

    def create_detection(component, license_id:, license_name:, source:, confidence:, **attrs)
      license = SupplyChain::License.find_by_spdx(license_id)

      SupplyChain::LicenseDetection.create!(
        account: account,
        sbom_component: component,
        license: license,
        detected_license_id: license_id,
        detected_license_name: license_name || license&.name,
        detection_source: source,
        confidence_score: confidence,
        is_primary: attrs[:is_primary] || true,
        requires_review: confidence < 0.8
      )
    end
  end
end

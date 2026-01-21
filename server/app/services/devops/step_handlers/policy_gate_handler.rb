# frozen_string_literal: true

module Devops
  module StepHandlers
    class PolicyGateHandler
      class HandlerError < StandardError; end

      attr_reader :step_execution, :step, :pipeline_run, :context

      def initialize(step_execution:, context: {})
        @step_execution = step_execution
        @step = step_execution.pipeline_step
        @pipeline_run = step_execution.pipeline_run
        @context = context.with_indifferent_access
        @logger = Rails.logger
      end

      def execute
        @logger.info "[PolicyGateHandler] Evaluating policies for step #{step.id}"

        config = step.configuration || {}
        account = pipeline_run.account

        begin
          results = []
          all_passed = true

          # Evaluate vulnerability policies
          if config["check_vulnerabilities"] != false
            vuln_result = evaluate_vulnerability_policy(account, config)
            results << vuln_result
            all_passed = false unless vuln_result[:passed]
          end

          # Evaluate license policies
          if config["check_licenses"] != false
            license_result = evaluate_license_policy(account, config)
            results << license_result
            all_passed = false unless license_result[:passed]
          end

          # Evaluate container image policies
          if config["check_container_images"]
            container_result = evaluate_container_policy(account, config)
            results << container_result
            all_passed = false unless container_result[:passed]
          end

          # Evaluate attestation requirements
          if config["require_attestation"]
            attestation_result = evaluate_attestation_requirement(account, config)
            results << attestation_result
            all_passed = false unless attestation_result[:passed]
          end

          # Custom policy checks
          if config["custom_policies"].present?
            custom_result = evaluate_custom_policies(account, config)
            results << custom_result
            all_passed = false unless custom_result[:passed]
          end

          {
            success: all_passed || config["enforcement_level"] != "block",
            outputs: {
              all_policies_passed: all_passed,
              policy_results: results,
              enforcement_level: config["enforcement_level"] || "warn",
              blocked: !all_passed && config["enforcement_level"] == "block"
            },
            error: all_passed ? nil : "Policy gate failed: #{failed_policies_summary(results)}"
          }
        rescue StandardError => e
          @logger.error "[PolicyGateHandler] Policy evaluation failed: #{e.message}"
          {
            success: config["enforcement_level"] != "block",
            error: e.message
          }
        end
      end

      private

      def evaluate_vulnerability_policy(account, config)
        sbom = get_sbom(account, config)

        unless sbom.present?
          return {
            policy_type: "vulnerability",
            passed: true,
            skipped: true,
            reason: "No SBOM available"
          }
        end

        violations = []

        # Check vulnerability thresholds
        critical_count = sbom.vulnerabilities.where(severity: "critical").count
        high_count = sbom.vulnerabilities.where(severity: "high").count

        max_critical = config.dig("vulnerability_policy", "max_critical") || 0
        max_high = config.dig("vulnerability_policy", "max_high") || 5

        if critical_count > max_critical
          violations << "Critical vulnerabilities (#{critical_count}) exceed threshold (#{max_critical})"
        end

        if high_count > max_high
          violations << "High vulnerabilities (#{high_count}) exceed threshold (#{max_high})"
        end

        # Check for unfixed critical vulnerabilities
        if config.dig("vulnerability_policy", "block_unfixed_critical")
          unfixed = sbom.vulnerabilities.where(severity: "critical", remediation_status: "open").where(fixed_version: nil).count
          if unfixed > 0
            violations << "#{unfixed} unfixed critical vulnerabilities"
          end
        end

        {
          policy_type: "vulnerability",
          passed: violations.empty?,
          violations: violations,
          details: {
            critical_count: critical_count,
            high_count: high_count,
            max_critical: max_critical,
            max_high: max_high
          }
        }
      end

      def evaluate_license_policy(account, config)
        sbom = get_sbom(account, config)

        unless sbom.present?
          return {
            policy_type: "license",
            passed: true,
            skipped: true,
            reason: "No SBOM available"
          }
        end

        policy_id = config.dig("license_policy", "policy_id")
        result = SupplyChain::LicenseComplianceService.new(
          account: account,
          sbom: sbom,
          options: { policy_id: policy_id }
        ).evaluate!

        {
          policy_type: "license",
          passed: result[:compliant],
          violations: result[:violations]&.map { |v| v[:description] } || [],
          details: {
            violation_count: result[:violation_count] || 0,
            policy_name: result.dig(:policy, :name)
          }
        }
      end

      def evaluate_container_policy(account, config)
        image = get_container_image(account, config)

        unless image.present?
          return {
            policy_type: "container_image",
            passed: true,
            skipped: true,
            reason: "No container image available"
          }
        end

        result = SupplyChain::ContainerScanService.new(
          account: account,
          image: image
        ).evaluate_policies

        {
          policy_type: "container_image",
          passed: result[:passed],
          violations: result[:policy_results]
                        .reject { |r| r[:passed] || r[:skipped] }
                        .flat_map { |r| r[:violations]&.map { |v| v[:message] } || [] },
          details: {
            image_status: image.status,
            policies_evaluated: result[:policy_results].length
          }
        }
      end

      def evaluate_attestation_requirement(account, config)
        sbom = get_sbom(account, config)
        violations = []

        # Check if attestation exists
        attestation = if sbom.present?
                        sbom.attestations.first
                      else
                        # Try to find attestation from context
                        context[:attestation_id].present? ? SupplyChain::Attestation.find_by(id: context[:attestation_id]) : nil
                      end

        unless attestation.present?
          violations << "No attestation found"
          return {
            policy_type: "attestation",
            passed: false,
            violations: violations
          }
        end

        # Check SLSA level requirement
        min_slsa_level = config.dig("attestation_policy", "min_slsa_level") || 1
        if attestation.slsa_level < min_slsa_level
          violations << "SLSA level (#{attestation.slsa_level}) below minimum (#{min_slsa_level})"
        end

        # Check signature requirement
        if config.dig("attestation_policy", "require_signature") && !attestation.signed?
          violations << "Attestation is not signed"
        end

        # Check Rekor requirement
        if config.dig("attestation_policy", "require_rekor") && !attestation.logged_to_rekor?
          violations << "Attestation not logged to Rekor"
        end

        # Check verification status
        if config.dig("attestation_policy", "require_verified") && !attestation.verified?
          violations << "Attestation not verified"
        end

        {
          policy_type: "attestation",
          passed: violations.empty?,
          violations: violations,
          details: {
            attestation_id: attestation.id,
            slsa_level: attestation.slsa_level,
            signed: attestation.signed?,
            verified: attestation.verified?,
            rekor_logged: attestation.logged_to_rekor?
          }
        }
      end

      def evaluate_custom_policies(account, config)
        violations = []
        custom_policies = config["custom_policies"] || []

        custom_policies.each do |policy|
          case policy["type"]
          when "dependency_count"
            sbom = get_sbom(account, config)
            if sbom && sbom.component_count > (policy["max_count"] || 500)
              violations << "Dependency count (#{sbom.component_count}) exceeds maximum (#{policy['max_count']})"
            end
          when "risk_score"
            sbom = get_sbom(account, config)
            if sbom && sbom.risk_score > (policy["max_score"] || 50)
              violations << "Risk score (#{sbom.risk_score}) exceeds maximum (#{policy['max_score']})"
            end
          when "outdated_dependencies"
            sbom = get_sbom(account, config)
            if sbom
              outdated_ratio = sbom.components.where(is_outdated: true).count.to_f / [sbom.component_count, 1].max
              if outdated_ratio > (policy["max_ratio"] || 0.3)
                violations << "Outdated dependency ratio (#{(outdated_ratio * 100).round(1)}%) exceeds maximum (#{(policy['max_ratio'] * 100).round(1)}%)"
              end
            end
          end
        end

        {
          policy_type: "custom",
          passed: violations.empty?,
          violations: violations
        }
      end

      def get_sbom(account, config)
        @sbom ||= begin
          if context[:sbom_id].present?
            SupplyChain::Sbom.find_by(id: context[:sbom_id], account_id: account.id)
          elsif config["sbom_id"].present?
            SupplyChain::Sbom.find_by(id: config["sbom_id"], account_id: account.id)
          elsif pipeline_run.repository.present?
            SupplyChain::Sbom.where(account_id: account.id, repository_id: pipeline_run.repository.id)
                            .order(created_at: :desc)
                            .first
          end
        end
      end

      def get_container_image(account, config)
        if context[:container_image_id].present?
          SupplyChain::ContainerImage.find_by(id: context[:container_image_id], account_id: account.id)
        elsif config["image_reference"].present?
          SupplyChain::ContainerImage.where(account_id: account.id)
                                     .where("registry || '/' || repository || ':' || tag = ?", config["image_reference"])
                                     .first
        end
      end

      def failed_policies_summary(results)
        results.reject { |r| r[:passed] || r[:skipped] }
               .map { |r| r[:policy_type] }
               .join(", ")
      end
    end
  end
end

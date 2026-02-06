# frozen_string_literal: true

module Devops
  module StepHandlers
    class PolicyGateHandler < Base
      BUILT_IN_POLICIES = %w[
        vulnerability_threshold
        license_compliance
        image_signing_required
        sbom_required
        branch_protection
        approval_required
      ].freeze

      def execute(config:, context:, previous_outputs: {})
        logs = []
        logs << log_info("Starting policy gate evaluation")

        policies = config["policies"] || []
        raise StandardError, "No policies configured for policy gate" if policies.empty?

        fail_mode = config["fail_mode"] || "any"
        results = []

        policies.each do |policy|
          policy_type = policy["type"]
          logs << log_info("Evaluating policy", type: policy_type)

          result = evaluate_policy(policy: policy, context: context, previous_outputs: previous_outputs)
          results << result

          logs << if result[:passed]
                    log_info("Policy passed", type: policy_type)
                  else
                    log_warn("Policy failed", type: policy_type, reason: result[:reason])
                  end
        end

        passed = case fail_mode
                 when "any"
                   results.all? { |r| r[:passed] }
                 when "all"
                   results.any? { |r| r[:passed] }
                 else
                   results.all? { |r| r[:passed] }
                 end

        failed_policies = results.reject { |r| r[:passed] }

        unless passed
          logs << log_error("Policy gate failed", failed_count: failed_policies.size)
          raise StandardError, "Policy gate failed: #{failed_policies.map { |p| p[:policy] }.join(', ')}"
        end

        logs << log_info("All policies passed")

        {
          outputs: {
            passed: passed,
            total_policies: results.size,
            passed_count: results.count { |r| r[:passed] },
            failed_count: failed_policies.size,
            results: results,
            evaluated_at: Time.current.iso8601
          },
          logs: logs.join("\n")
        }
      end

      private

      def evaluate_policy(policy:, context:, previous_outputs:)
        policy_type = policy["type"]

        case policy_type
        when "vulnerability_threshold"
          evaluate_vulnerability_threshold(policy, previous_outputs)
        when "license_compliance"
          evaluate_license_compliance(policy, previous_outputs)
        when "image_signing_required"
          evaluate_signing_required(policy, previous_outputs)
        when "sbom_required"
          evaluate_sbom_required(policy, previous_outputs)
        when "branch_protection"
          evaluate_branch_protection(policy, context)
        when "approval_required"
          evaluate_approval_required(policy, context)
        when "custom"
          evaluate_custom_policy(policy, context, previous_outputs)
        else
          { passed: false, policy: policy_type, reason: "Unknown policy type: #{policy_type}" }
        end
      end

      def evaluate_vulnerability_threshold(policy, previous_outputs)
        scan_results = previous_outputs.dig("vulnerability_scan", :by_severity) ||
                       previous_outputs.dig("vulnerability_scan", "by_severity")

        unless scan_results
          return { passed: false, policy: "vulnerability_threshold", reason: "No vulnerability scan results available" }
        end

        max_critical = policy["max_critical"] || 0
        max_high = policy["max_high"] || 5

        critical_count = scan_results[:critical] || scan_results["critical"] || 0
        high_count = scan_results[:high] || scan_results["high"] || 0

        if critical_count > max_critical
          { passed: false, policy: "vulnerability_threshold", reason: "#{critical_count} critical vulnerabilities (max: #{max_critical})" }
        elsif high_count > max_high
          { passed: false, policy: "vulnerability_threshold", reason: "#{high_count} high vulnerabilities (max: #{max_high})" }
        else
          { passed: true, policy: "vulnerability_threshold" }
        end
      end

      def evaluate_license_compliance(policy, previous_outputs)
        sbom_path = previous_outputs.dig("sbom_generate", :sbom_path)

        unless sbom_path && File.exist?(sbom_path)
          return { passed: false, policy: "license_compliance", reason: "No SBOM available for license check" }
        end

        blocked_licenses = policy["blocked_licenses"] || %w[GPL-3.0 AGPL-3.0]

        begin
          sbom = JSON.parse(File.read(sbom_path))
          components = sbom["components"] || sbom["packages"] || []

          violations = components.select do |c|
            license = c.dig("licenses", 0, "license", "id") ||
                      c.dig("licenseConcluded") ||
                      c["license"]
            blocked_licenses.any? { |bl| license.to_s.include?(bl) }
          end

          if violations.any?
            { passed: false, policy: "license_compliance", reason: "#{violations.size} components with blocked licenses" }
          else
            { passed: true, policy: "license_compliance" }
          end
        rescue JSON::ParserError, Errno::ENOENT => e
          { passed: false, policy: "license_compliance", reason: "Failed to parse SBOM: #{e.message}" }
        end
      end

      def evaluate_signing_required(policy, previous_outputs)
        signed = previous_outputs.dig("sign_artifact", :signature_path).present?

        if signed
          { passed: true, policy: "image_signing_required" }
        else
          { passed: false, policy: "image_signing_required", reason: "Artifact has not been signed" }
        end
      end

      def evaluate_sbom_required(policy, previous_outputs)
        has_sbom = previous_outputs.dig("sbom_generate", :sbom_path).present?

        if has_sbom
          { passed: true, policy: "sbom_required" }
        else
          { passed: false, policy: "sbom_required", reason: "No SBOM has been generated" }
        end
      end

      def evaluate_branch_protection(policy, context)
        allowed_branches = policy["allowed_branches"] || %w[main master release/*]
        branch = context.dig(:trigger_context, :branch) || context.dig(:trigger_context, "branch")

        return { passed: false, policy: "branch_protection", reason: "No branch information available" } unless branch

        matched = allowed_branches.any? do |pattern|
          if pattern.include?("*")
            File.fnmatch(pattern, branch)
          else
            branch == pattern
          end
        end

        if matched
          { passed: true, policy: "branch_protection" }
        else
          { passed: false, policy: "branch_protection", reason: "Branch '#{branch}' not in allowed list" }
        end
      end

      def evaluate_approval_required(policy, context)
        approved = context.dig(:approval, :approved) || context.dig(:trigger_context, :approved)

        if approved
          { passed: true, policy: "approval_required" }
        else
          { passed: false, policy: "approval_required", reason: "Manual approval has not been granted" }
        end
      end

      def evaluate_custom_policy(policy, context, previous_outputs)
        command = policy["command"]
        return { passed: false, policy: "custom", reason: "No command specified for custom policy" } unless command

        workspace = previous_outputs.dig("checkout", :workspace) || Dir.pwd
        interpolated_command = interpolate(command, context.merge(previous_outputs))

        result = execute_shell_command(interpolated_command, working_directory: workspace, timeout: policy["timeout"]&.to_i || 120)

        if result[:success]
          { passed: true, policy: "custom" }
        else
          { passed: false, policy: "custom", reason: result[:error] || "Custom policy command failed" }
        end
      end
    end
  end
end

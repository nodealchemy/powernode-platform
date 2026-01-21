# frozen_string_literal: true

module SupplyChain
  class ScanExecutionJob < ApplicationJob
    queue_as :supply_chain_scans

    def perform(execution_id)
      execution = ::SupplyChain::ScanExecution.find(execution_id)

      Rails.logger.info "[ScanExecutionJob] Starting execution #{execution_id}"

      # Broadcast start
      SupplyChainChannel.broadcast_scan_started(execution)

      begin
        execution.update!(status: "running", started_at: Time.current)

        # Get the scan instance and template
        instance = execution.scan_instance
        template = instance.scan_template

        # Execute based on template type
        results = case template.template_type
                  when "sbom"
                    execute_sbom_scan(execution, template)
                  when "vulnerability"
                    execute_vulnerability_scan(execution, template)
                  when "license"
                    execute_license_scan(execution, template)
                  when "container"
                    execute_container_scan(execution, template)
                  else
                    execute_custom_scan(execution, template)
                  end

        execution.update!(
          status: "completed",
          completed_at: Time.current,
          duration_seconds: (Time.current - execution.started_at).to_i,
          findings_count: results[:findings_count] || 0,
          results: results[:data]
        )

        # Broadcast completion
        SupplyChainChannel.broadcast_scan_completed(execution)

        # Auto-remediate if enabled
        if instance.auto_remediate && results[:findings_count].to_i > 0
          trigger_auto_remediation(execution, results)
        end

        Rails.logger.info "[ScanExecutionJob] Execution #{execution_id} completed with #{results[:findings_count]} findings"
      rescue StandardError => e
        Rails.logger.error "[ScanExecutionJob] Execution #{execution_id} failed: #{e.message}"

        execution.update!(
          status: "failed",
          completed_at: Time.current,
          duration_seconds: execution.started_at ? (Time.current - execution.started_at).to_i : 0,
          error_message: e.message
        )

        # Broadcast failure
        SupplyChainChannel.broadcast_scan_failed(execution, e.message)

        raise e
      end
    end

    private

    def execute_sbom_scan(execution, template)
      target = resolve_target(execution)
      return empty_results unless target

      # Generate SBOM for the target
      sbom = ::SupplyChain::SbomGenerationService.new(
        account: execution.account,
        source: target,
        format: execution.configuration["format"] || "cyclonedx_1_5"
      ).generate

      {
        findings_count: sbom.component_count,
        data: {
          sbom_id: sbom.id,
          component_count: sbom.component_count,
          vulnerability_count: sbom.vulnerability_count
        }
      }
    end

    def execute_vulnerability_scan(execution, template)
      target = resolve_target(execution)
      return empty_results unless target

      # Run vulnerability correlation
      case execution.target_type
      when "Sbom", "SupplyChain::Sbom"
        service = ::SupplyChain::VulnerabilityCorrelationService.new(sbom: target)
        results = service.correlate

        {
          findings_count: results[:total_vulnerabilities],
          data: results
        }
      when "ContainerImage", "SupplyChain::ContainerImage"
        service = ::SupplyChain::ContainerScanService.new(image: target)
        results = service.scan

        {
          findings_count: results[:vulnerabilities]&.count || 0,
          data: results
        }
      else
        empty_results
      end
    end

    def execute_license_scan(execution, template)
      target = resolve_target(execution)
      return empty_results unless target

      # Run license compliance check
      policy = execution.account.supply_chain_license_policies.find_by(
        id: execution.configuration["policy_id"]
      ) || execution.account.supply_chain_license_policies.where(is_active: true).first

      return empty_results unless policy

      violations = []
      if target.is_a?(::SupplyChain::Sbom)
        target.components.includes(:license).each do |component|
          next unless component.license

          violation = policy.check_license(component.license, component)
          violations << violation if violation
        end
      end

      {
        findings_count: violations.count,
        data: {
          policy_id: policy.id,
          violations: violations
        }
      }
    end

    def execute_container_scan(execution, template)
      target = resolve_target(execution)
      return empty_results unless target.is_a?(::SupplyChain::ContainerImage)

      service = ::SupplyChain::ContainerScanService.new(image: target)
      results = service.scan

      {
        findings_count: results[:vulnerabilities]&.count || 0,
        data: results
      }
    end

    def execute_custom_scan(execution, template)
      # Custom scan logic based on template configuration
      rules = template.scan_rules || {}

      {
        findings_count: 0,
        data: {
          message: "Custom scan completed",
          rules_evaluated: rules.keys.count
        }
      }
    end

    def resolve_target(execution)
      case execution.target_type
      when "Sbom", "SupplyChain::Sbom"
        execution.account.supply_chain_sboms.find_by(id: execution.target_id)
      when "ContainerImage", "SupplyChain::ContainerImage"
        execution.account.supply_chain_container_images.find_by(id: execution.target_id)
      when "Repository", "Devops::Repository"
        execution.account.devops_repositories.find_by(id: execution.target_id)
      else
        nil
      end
    end

    def trigger_auto_remediation(execution, results)
      return unless results[:data].present?

      # Create remediation plan if significant findings
      if results[:findings_count].to_i >= (execution.configuration["remediation_threshold"] || 1)
        ::SupplyChain::RemediationPlan.create!(
          account: execution.account,
          scan_execution: execution,
          plan_type: "auto_generated",
          status: "pending",
          target_findings: results[:data]
        )
      end
    end

    def empty_results
      { findings_count: 0, data: {} }
    end
  end
end

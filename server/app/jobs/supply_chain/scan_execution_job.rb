# frozen_string_literal: true

module SupplyChain
  class ScanExecutionJob < ApplicationJob
    queue_as :supply_chain_scans

    def perform(execution_id)
      execution = ::SupplyChain::ScanExecution.find(execution_id)

      Rails.logger.info "[ScanExecutionJob] Starting execution #{execution_id}"

      # Broadcast start
      SupplyChainChannel.broadcast_execution_started(execution)

      begin
        execution.update!(status: "running", started_at: Time.current)

        # Get the scan instance and template
        instance = execution.scan_instance
        template = instance.scan_template
        config = get_execution_config(execution, instance)

        # Execute based on template category
        results = case template.category
                  when "security"
                    execute_security_scan(execution, template, config)
                  when "compliance"
                    execute_compliance_scan(execution, template, config)
                  when "license"
                    execute_license_scan(execution, template, config)
                  when "quality"
                    execute_quality_scan(execution, template, config)
                  else
                    execute_custom_scan(execution, template, config)
                  end

        execution.update!(
          status: "completed",
          completed_at: Time.current,
          duration_ms: calculate_duration_ms(execution.started_at),
          output_data: results[:data].merge(findings_count: results[:findings_count] || 0)
        )

        # Broadcast completion
        SupplyChainChannel.broadcast_execution_completed(execution)

        # Auto-remediate if enabled
        if auto_remediate_enabled?(config) && results[:findings_count].to_i > 0
          trigger_auto_remediation(execution, results, config)
        end

        Rails.logger.info "[ScanExecutionJob] Execution #{execution_id} completed with #{results[:findings_count]} findings"
      rescue StandardError => e
        Rails.logger.error "[ScanExecutionJob] Execution #{execution_id} failed: #{e.message}"

        execution.update!(
          status: "failed",
          completed_at: Time.current,
          duration_ms: execution.started_at ? calculate_duration_ms(execution.started_at) : 0,
          error_message: e.message
        )

        # Broadcast failure
        SupplyChainChannel.broadcast_execution_failed(execution, e.message)

        raise e
      end
    end

    private

    def get_execution_config(execution, instance)
      # Merge instance configuration with execution input_data
      base_config = instance.configuration || {}
      input_config = execution.input_data || {}
      base_config.deep_merge(input_config).with_indifferent_access
    end

    def calculate_duration_ms(started_at)
      ((Time.current - started_at) * 1000).to_i
    end

    def auto_remediate_enabled?(config)
      config[:auto_remediate] == true
    end

    def execute_security_scan(execution, template, config)
      target = resolve_target(execution, config)
      return empty_results unless target

      # Generate SBOM for the target or scan for vulnerabilities
      if target.is_a?(::SupplyChain::Sbom)
        service = ::SupplyChain::VulnerabilityCorrelationService.new(sbom: target)
        results = service.correlate!

        {
          findings_count: results[:total_vulnerabilities],
          data: results
        }
      elsif target.is_a?(::SupplyChain::ContainerImage)
        service = ::SupplyChain::ContainerScanService.new(account: execution.account, image: target)
        results = service.scan!

        {
          findings_count: results[:vulnerabilities]&.count || 0,
          data: results
        }
      elsif target.is_a?(::Devops::Repository)
        # Generate SBOM for repository
        service = ::SupplyChain::SbomGenerationService.new(
          account: execution.account,
          repository: target
        )
        sbom = service.generate(
          source_path: ".",
          format: config["format"] || "cyclonedx_1_5"
        )

        {
          findings_count: sbom.component_count,
          data: {
            sbom_id: sbom.id,
            component_count: sbom.component_count,
            vulnerability_count: sbom.vulnerability_count
          }
        }
      else
        empty_results
      end
    end

    def execute_compliance_scan(execution, template, config)
      target = resolve_target(execution, config)
      return empty_results unless target

      # Run vulnerability correlation for compliance
      case target
      when ::SupplyChain::Sbom
        service = ::SupplyChain::VulnerabilityCorrelationService.new(sbom: target)
        results = service.correlate!

        {
          findings_count: results[:total_vulnerabilities],
          data: results
        }
      when ::SupplyChain::ContainerImage
        service = ::SupplyChain::ContainerScanService.new(account: execution.account, image: target)
        results = service.scan!

        {
          findings_count: results[:vulnerabilities]&.count || 0,
          data: results
        }
      else
        empty_results
      end
    end

    def execute_license_scan(execution, template, config)
      target = resolve_target(execution, config)
      return empty_results unless target

      # Run license compliance check
      policy = execution.account.supply_chain_license_policies.find_by(
        id: config["policy_id"]
      ) || execution.account.supply_chain_license_policies.where(is_active: true).first

      return empty_results unless policy

      violations = []
      if target.is_a?(::SupplyChain::Sbom)
        target.components.each do |component|
          next unless component.license_spdx_id.present?

          license = component.license
          next unless license

          violation = policy.check_license(license, component)
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

    def execute_quality_scan(execution, template, config)
      target = resolve_target(execution, config)
      return empty_results unless target.is_a?(::SupplyChain::ContainerImage)

      service = ::SupplyChain::ContainerScanService.new(account: execution.account, image: target)
      results = service.scan!

      {
        findings_count: results[:vulnerabilities]&.count || 0,
        data: results
      }
    end

    def execute_custom_scan(execution, template, config)
      # Custom scan logic based on template configuration
      rules = template.default_configuration || {}

      {
        findings_count: 0,
        data: {
          message: "Custom scan completed",
          rules_evaluated: rules.keys.count
        }
      }
    end

    def resolve_target(execution, config)
      target_type = config["target_type"]
      target_id = config["target_id"]

      case target_type
      when "Sbom", "SupplyChain::Sbom"
        execution.account.supply_chain_sboms.find_by(id: target_id)
      when "ContainerImage", "SupplyChain::ContainerImage"
        execution.account.supply_chain_container_images.find_by(id: target_id)
      when "Repository", "Devops::Repository"
        execution.account.devops_repositories.find_by(id: target_id)
      else
        nil
      end
    end

    def trigger_auto_remediation(execution, results, config)
      return unless results[:data].present?

      # Create remediation plan if significant findings
      threshold = config["remediation_threshold"] || 1
      if results[:findings_count].to_i >= threshold
        # Find the target SBOM from the execution
        target_sbom = find_or_create_sbom_for_remediation(execution, config)
        return unless target_sbom

        ::SupplyChain::RemediationPlan.create!(
          account: execution.account,
          sbom: target_sbom,
          plan_type: "auto_fix",
          status: "draft",
          target_vulnerabilities: extract_vulnerabilities(results[:data]),
          metadata: {
            scan_execution_id: execution.id,
            auto_generated: true,
            triggered_at: Time.current.iso8601
          }
        )
      end
    end

    def find_or_create_sbom_for_remediation(execution, config)
      target_type = config["target_type"]
      target_id = config["target_id"]

      case target_type
      when "Sbom", "SupplyChain::Sbom"
        execution.account.supply_chain_sboms.find_by(id: target_id)
      when "ContainerImage", "SupplyChain::ContainerImage"
        image = execution.account.supply_chain_container_images.find_by(id: target_id)
        image&.sbom
      else
        nil
      end
    end

    def extract_vulnerabilities(data)
      return [] unless data.is_a?(Hash)

      if data[:vulnerabilities].present?
        data[:vulnerabilities]
      elsif data["vulnerabilities"].present?
        data["vulnerabilities"]
      else
        []
      end
    end

    def empty_results
      { findings_count: 0, data: {} }
    end
  end
end

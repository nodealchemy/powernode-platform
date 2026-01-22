# frozen_string_literal: true

module SupplyChain
  class ReportGenerationJob < ApplicationJob
    queue_as :supply_chain_reports

    def perform(report_id)
      report = ::SupplyChain::Report.find(report_id)

      Rails.logger.info "[ReportGenerationJob] Starting generation for report #{report_id}"

      # Broadcast start
      SupplyChainChannel.broadcast_report_generation_started(report)

      begin
        report.update!(status: "generating", generated_at: Time.current)

        case report.report_type
        when "sbom_export"
          generate_sbom_report(report)
        when "attribution"
          generate_attribution_report(report)
        when "compliance"
          generate_compliance_report(report)
        when "vulnerability"
          generate_vulnerability_report(report)
        when "vendor_risk"
          generate_vendor_risk_report(report)
        else
          raise "Unknown report type: #{report.report_type}"
        end

        report.update!(status: "completed")

        # Broadcast completion
        SupplyChainChannel.broadcast_report_generation_completed(report)

        Rails.logger.info "[ReportGenerationJob] Report #{report_id} generated successfully"
      rescue StandardError => e
        Rails.logger.error "[ReportGenerationJob] Report #{report_id} failed: #{e.message}"

        report.update!(
          status: "failed",
          metadata: (report.metadata || {}).merge(error_message: e.message)
        )

        # Broadcast failure
        SupplyChainChannel.broadcast_report_generation_failed(report, e.message)

        raise e
      end
    end

    private

    def generate_sbom_report(report)
      params = report.parameters.with_indifferent_access
      sbom = report.account.supply_chain_sboms.find(params[:sbom_id])

      export_format = params[:export_format] || "json"
      content = sbom.export(format: export_format.to_sym)

      save_report_content(report, content, "sbom.#{export_format}", content_type_for(export_format))
    end

    def generate_attribution_report(report)
      params = report.parameters.with_indifferent_access
      sbom_ids = params[:sbom_ids] || []

      sboms = report.account.supply_chain_sboms.where(id: sbom_ids)

      # Generate attribution content
      content = generate_attribution_content(sboms, params[:include_license_text] != false)

      save_report_content(report, content, "NOTICE.txt", "text/plain")
    end

    def generate_compliance_report(report)
      params = report.parameters.with_indifferent_access

      content = {
        report_date: Time.current.iso8601,
        framework: params[:framework] || "ntia",
        account_id: report.account.id,
        sbom_compliance: generate_sbom_compliance_data(report.account, params),
        attestation_compliance: generate_attestation_compliance_data(report.account),
        license_compliance: generate_license_compliance_data(report.account),
        vendor_compliance: generate_vendor_compliance_data(report.account)
      }

      format = report.format || "json"
      save_report_content(report, format_content(content, format), "compliance_report.#{format}", content_type_for(format))
    end

    def generate_vulnerability_report(report)
      params = report.parameters.with_indifferent_access

      vulnerabilities = []

      # Gather SBOM vulnerabilities
      if params[:sbom_ids].present?
        sboms = report.account.supply_chain_sboms.where(id: params[:sbom_ids])
        sboms.each do |sbom|
          sbom.vulnerabilities.each do |vuln|
            vulnerabilities << format_vulnerability(vuln, sbom)
          end
        end
      end

      # Gather container vulnerabilities
      if params[:container_image_ids].present?
        images = report.account.supply_chain_container_images.where(id: params[:container_image_ids])
        images.each do |image|
          latest_scan = image.vulnerability_scans.order(created_at: :desc).first
          next unless latest_scan

          (latest_scan.vulnerabilities || []).each do |vuln_data|
            vulnerabilities << format_container_vulnerability(vuln_data, image)
          end
        end
      end

      # Filter by severity if specified
      if params[:severity_filter].present?
        vulnerabilities = vulnerabilities.select { |v| v[:severity] == params[:severity_filter] }
      end

      # Sort by severity
      severity_order = { "critical" => 0, "high" => 1, "medium" => 2, "low" => 3 }
      vulnerabilities.sort_by! { |v| severity_order[v[:severity]] || 4 }

      content = {
        report_date: Time.current.iso8601,
        total_vulnerabilities: vulnerabilities.count,
        by_severity: vulnerabilities.group_by { |v| v[:severity] }.transform_values(&:count),
        vulnerabilities: vulnerabilities
      }

      format = report.format || "json"
      save_report_content(report, format_content(content, format), "vulnerability_report.#{format}", content_type_for(format))
    end

    def generate_vendor_risk_report(report)
      params = report.parameters.with_indifferent_access

      vendors = if params[:vendor_ids].present?
                  report.account.supply_chain_vendors.where(id: params[:vendor_ids])
                else
                  report.account.supply_chain_vendors.where(status: "active")
                end

      vendor_data = vendors.map do |vendor|
        data = {
          id: vendor.id,
          name: vendor.name,
          vendor_type: vendor.vendor_type,
          risk_tier: vendor.risk_tier,
          risk_score: vendor.risk_score,
          status: vendor.status,
          certifications: vendor.certifications,
          data_handling: {
            pii: vendor.handles_pii,
            phi: vendor.handles_phi,
            pci: vendor.handles_pci
          }
        }

        if params[:include_assessments]
          latest_assessment = vendor.risk_assessments.completed.order(completed_at: :desc).first
          if latest_assessment
            data[:latest_assessment] = {
              id: latest_assessment.id,
              date: latest_assessment.assessment_date,
              security_score: latest_assessment.security_score,
              compliance_score: latest_assessment.compliance_score,
              operational_score: latest_assessment.operational_score,
              summary: latest_assessment.summary
            }
          end
        end

        data
      end

      content = {
        report_date: Time.current.iso8601,
        total_vendors: vendor_data.count,
        by_risk_tier: vendor_data.group_by { |v| v[:risk_tier] }.transform_values(&:count),
        vendors: vendor_data
      }

      format = report.format || "json"
      save_report_content(report, format_content(content, format), "vendor_risk_report.#{format}", content_type_for(format))
    end

    def generate_attribution_content(sboms, include_license_text)
      lines = []
      lines << "=" * 80
      lines << "THIRD-PARTY SOFTWARE NOTICES AND INFORMATION"
      lines << "Generated: #{Time.current.strftime('%Y-%m-%d %H:%M:%S UTC')}"
      lines << "=" * 80
      lines << ""

      sboms.each do |sbom|
        sbom.components.each do |component|
          next unless component.license_spdx_id.present?

          lines << "-" * 80
          lines << "#{component.name} (#{component.version})"
          lines << "License: #{component.license.name} (#{component.license.spdx_id})"
          lines << "URL: #{component.purl}"
          lines << ""

          if include_license_text && component.license.license_text.present?
            lines << component.license.license_text
            lines << ""
          end
        end
      end

      lines.join("\n")
    end

    def generate_sbom_compliance_data(account, params)
      sboms = account.supply_chain_sboms

      if params[:sbom_ids].present?
        sboms = sboms.where(id: params[:sbom_ids])
      end

      {
        total: sboms.count,
        ntia_compliant: sboms.where(ntia_minimum_compliant: true).count,
        compliance_rate: sboms.any? ? (sboms.where(ntia_minimum_compliant: true).count.to_f / sboms.count * 100).round(1) : 100
      }
    end

    def generate_attestation_compliance_data(account)
      attestations = account.supply_chain_attestations

      {
        total: attestations.count,
        signed: attestations.where.not(signature: nil).count,
        verified: attestations.where(verification_status: "verified").count,
        by_slsa_level: attestations.group(:slsa_level).count
      }
    end

    def generate_license_compliance_data(account)
      {
        active_policies: account.supply_chain_license_policies.where(is_active: true).count,
        open_violations: account.supply_chain_license_violations.where(status: "open").count,
        violations_by_type: account.supply_chain_license_violations.where(status: "open").group(:violation_type).count
      }
    end

    def generate_vendor_compliance_data(account)
      vendors = account.supply_chain_vendors.where(status: "active")

      {
        total_active: vendors.count,
        with_current_assessment: vendors.reject(&:needs_assessment?).count,
        pii_with_dpa: vendors.where(handles_pii: true, has_dpa: true).count,
        pii_without_dpa: vendors.where(handles_pii: true, has_dpa: false).count,
        phi_with_baa: vendors.where(handles_phi: true, has_baa: true).count,
        phi_without_baa: vendors.where(handles_phi: true, has_baa: false).count
      }
    end

    def format_vulnerability(vuln, sbom)
      {
        vulnerability_id: vuln.vulnerability_id,
        severity: vuln.severity,
        cvss_score: vuln.cvss_score,
        component: vuln.component&.name,
        version: vuln.component&.version,
        fixed_version: vuln.fixed_version,
        remediation_status: vuln.remediation_status,
        source: "sbom",
        source_id: sbom.id,
        source_name: sbom.name
      }
    end

    def format_container_vulnerability(vuln_data, image)
      {
        vulnerability_id: vuln_data["vulnerability_id"] || vuln_data["id"],
        severity: vuln_data["severity"],
        cvss_score: vuln_data["cvss_score"],
        component: vuln_data["package_name"],
        version: vuln_data["installed_version"],
        fixed_version: vuln_data["fixed_version"],
        source: "container",
        source_id: image.id,
        source_name: image.full_reference
      }
    end

    def format_content(content, format)
      case format
      when "json"
        JSON.pretty_generate(content)
      when "csv"
        # Simplified CSV for flat data
        content.to_json
      else
        JSON.pretty_generate(content)
      end
    end

    def save_report_content(report, content, filename, content_type)
      # In a real implementation, this would save to cloud storage
      # For now, store in the report record

      # Convert Hash content to JSON string if needed
      content_string = content.is_a?(Hash) ? content.to_json : content.to_s

      report.update!(
        file_path: "/reports/#{report.id}/#{filename}",
        file_size_bytes: content_string.bytesize,
        metadata: (report.metadata || {}).merge(
          content_type: content_type,
          filename: filename,
          content_preview: content_string[0..1000]
        )
      )
    end

    def content_type_for(format)
      case format.to_s
      when "json" then "application/json"
      when "xml" then "application/xml"
      when "csv" then "text/csv"
      when "pdf" then "application/pdf"
      when "txt" then "text/plain"
      else "application/octet-stream"
      end
    end
  end
end

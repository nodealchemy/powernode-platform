# frozen_string_literal: true

class SupplyChainChannel < ApplicationCable::Channel
  def subscribed
    account_id = params[:account_id]

    if current_user && authorized_for_account?(account_id)
      stream_from "supply_chain_#{account_id}"
      Rails.logger.info "User #{current_user.id} subscribed to Supply Chain updates for account #{account_id}"

      transmit({
        type: "subscribed",
        message: "Connected to Supply Chain updates",
        account_id: account_id,
        timestamp: Time.current.iso8601
      })
    else
      Rails.logger.warn "Unauthorized Supply Chain subscription attempt by user #{current_user&.id}"
      reject
    end
  end

  def unsubscribed
    Rails.logger.info "User #{current_user&.id} unsubscribed from Supply Chain updates"
  end

  class << self
    # SBOM Events
    def broadcast_sbom_created(sbom)
      data = {
        type: "sbom_created",
        sbom: serialize_sbom(sbom),
        timestamp: Time.current.iso8601
      }

      broadcast_to_account(sbom.account, data)
    end

    def broadcast_sbom_updated(sbom)
      data = {
        type: "sbom_updated",
        sbom: serialize_sbom(sbom),
        timestamp: Time.current.iso8601
      }

      broadcast_to_account(sbom.account, data)
    end

    def broadcast_vulnerability_correlation_completed(sbom, vulnerability_count)
      data = {
        type: "vulnerability_correlation_completed",
        sbom_id: sbom.id,
        vulnerability_count: vulnerability_count,
        timestamp: Time.current.iso8601
      }

      broadcast_to_account(sbom.account, data)
    end

    # Attestation Events
    def broadcast_attestation_created(attestation)
      data = {
        type: "attestation_created",
        attestation: serialize_attestation(attestation),
        timestamp: Time.current.iso8601
      }

      broadcast_to_account(attestation.account, data)
    end

    def broadcast_attestation_signed(attestation)
      data = {
        type: "attestation_signed",
        attestation_id: attestation.id,
        signing_key_id: attestation.signing_key_id,
        timestamp: Time.current.iso8601
      }

      broadcast_to_account(attestation.account, data)
    end

    def broadcast_attestation_verified(attestation, result)
      data = {
        type: "attestation_verified",
        attestation_id: attestation.id,
        verified: result[:verified],
        timestamp: Time.current.iso8601
      }

      broadcast_to_account(attestation.account, data)
    end

    # Container Scan Events
    def broadcast_scan_started(image)
      data = {
        type: "container_scan_started",
        container_image_id: image.id,
        image_reference: image.full_reference,
        timestamp: Time.current.iso8601
      }

      broadcast_to_account(image.account, data)
    end

    def broadcast_scan_completed(scan)
      image = scan.container_image
      data = {
        type: "container_scan_completed",
        scan_id: scan.id,
        container_image_id: image.id,
        vulnerability_counts: {
          critical: scan.critical_count,
          high: scan.high_count,
          medium: scan.medium_count,
          low: scan.low_count,
          total: scan.total_vulnerabilities
        },
        timestamp: Time.current.iso8601
      }

      broadcast_to_account(image.account, data)
    end

    # Policy Events
    def broadcast_policy_violation(account, violation_details)
      data = {
        type: "policy_violation",
        violation: violation_details,
        timestamp: Time.current.iso8601
      }

      broadcast_to_account(account, data)
    end

    def broadcast_policy_evaluation_completed(account, results)
      data = {
        type: "policy_evaluation_completed",
        passed: results[:passed],
        policy_count: results[:policy_results]&.length || 0,
        timestamp: Time.current.iso8601
      }

      broadcast_to_account(account, data)
    end

    # CVE Alert Events
    def broadcast_cve_alert(account, cve_details)
      data = {
        type: "cve_alert",
        cve: cve_details,
        timestamp: Time.current.iso8601
      }

      broadcast_to_account(account, data)
    end

    def broadcast_critical_vulnerability_found(vulnerability)
      sbom = vulnerability.sbom
      data = {
        type: "critical_vulnerability_found",
        vulnerability: {
          id: vulnerability.vulnerability_id,
          severity: vulnerability.severity,
          cvss_score: vulnerability.cvss_score,
          component_name: vulnerability.component&.name,
          component_version: vulnerability.component&.version
        },
        sbom_id: sbom.id,
        timestamp: Time.current.iso8601
      }

      broadcast_to_account(sbom.account, data)
    end

    # Vendor Events
    def broadcast_vendor_assessment_completed(assessment)
      vendor = assessment.vendor
      data = {
        type: "vendor_assessment_completed",
        assessment_id: assessment.id,
        vendor_id: vendor.id,
        vendor_name: vendor.name,
        scores: {
          security: assessment.security_score,
          compliance: assessment.compliance_score,
          operational: assessment.operational_score
        },
        timestamp: Time.current.iso8601
      }

      broadcast_to_account(vendor.account, data)
    end

    def broadcast_vendor_monitoring_event(event)
      vendor = event.vendor
      data = {
        type: "vendor_monitoring_event",
        event_id: event.id,
        vendor_id: vendor.id,
        vendor_name: vendor.name,
        event_type: event.event_type,
        severity: event.severity,
        title: event.title,
        timestamp: Time.current.iso8601
      }

      broadcast_to_account(vendor.account, data)
    end

    # Report Events
    def broadcast_report_generation_started(report)
      data = {
        type: "report_generation_started",
        report_id: report.id,
        report_type: report.report_type,
        name: report.name,
        timestamp: Time.current.iso8601
      }

      broadcast_to_account(report.account, data)
    end

    def broadcast_report_generation_completed(report)
      data = {
        type: "report_generation_completed",
        report_id: report.id,
        report_type: report.report_type,
        name: report.name,
        status: report.status,
        file_size: report.file_size,
        timestamp: Time.current.iso8601
      }

      broadcast_to_account(report.account, data)
    end

    def broadcast_report_generation_failed(report, error_message)
      data = {
        type: "report_generation_failed",
        report_id: report.id,
        report_type: report.report_type,
        name: report.name,
        error_message: error_message,
        timestamp: Time.current.iso8601
      }

      broadcast_to_account(report.account, data)
    end

    # License Events
    def broadcast_license_violation_detected(violation)
      data = {
        type: "license_violation_detected",
        violation_id: violation.id,
        violation_type: violation.violation_type,
        severity: violation.severity,
        component_name: violation.component&.name,
        license_id: violation.license_id,
        timestamp: Time.current.iso8601
      }

      broadcast_to_account(violation.account, data)
    end

    private

    def broadcast_to_account(account, data)
      ActionCable.server.broadcast("supply_chain_#{account.id}", data)
    end

    def serialize_sbom(sbom)
      {
        id: sbom.id,
        sbom_id: sbom.sbom_id,
        name: sbom.name,
        version: sbom.version,
        format: sbom.format,
        component_count: sbom.component_count,
        vulnerability_count: sbom.vulnerability_count,
        risk_score: sbom.risk_score,
        ntia_minimum_compliant: sbom.ntia_minimum_compliant,
        status: sbom.status
      }
    end

    def serialize_attestation(attestation)
      {
        id: attestation.id,
        attestation_id: attestation.attestation_id,
        attestation_type: attestation.attestation_type,
        slsa_level: attestation.slsa_level,
        subject_name: attestation.subject_name,
        signed: attestation.signed?,
        verified: attestation.verified?
      }
    end
  end
end

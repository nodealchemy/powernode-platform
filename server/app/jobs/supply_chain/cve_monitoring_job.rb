# frozen_string_literal: true

module SupplyChain
  class CveMonitoringJob < ApplicationJob
    queue_as :supply_chain_monitoring

    def perform(account_id = nil)
      if account_id.present?
        # Monitor specific account
        account = Account.find(account_id)
        monitor_account(account)
      else
        # Monitor all accounts with active monitors
        ::SupplyChain::CveMonitor.active.find_each do |monitor|
          monitor_for_cve_monitor(monitor)
        end
      end
    end

    private

    def monitor_account(account)
      Rails.logger.info "[CveMonitoringJob] Monitoring CVEs for account #{account.id}"

      # Get all active SBOMs and container images
      sboms = account.supply_chain_sboms.where(status: "active")
      images = account.supply_chain_container_images.where(is_deployed: true)

      # Check for new CVEs affecting components
      new_cves = check_for_new_cves(sboms)

      new_cves.each do |cve|
        SupplyChainChannel.broadcast_cve_alert(account, cve)
      end

      Rails.logger.info "[CveMonitoringJob] Found #{new_cves.count} new CVEs for account #{account.id}"
    end

    def monitor_for_cve_monitor(monitor)
      Rails.logger.info "[CveMonitoringJob] Running CVE monitor #{monitor.id}"

      case monitor.scope_type
      when "account_wide"
        check_account_wide(monitor)
      when "repository"
        check_repository_scope(monitor)
      when "image"
        check_image_scope(monitor)
      end

      monitor.update!(last_check_at: Time.current)
    rescue StandardError => e
      Rails.logger.error "[CveMonitoringJob] Monitor #{monitor.id} failed: #{e.message}"
    end

    def check_for_new_cves(sboms)
      new_cves = []

      sboms.each do |sbom|
        # Re-correlate vulnerabilities
        correlation_service = ::SupplyChain::VulnerabilityCorrelationService.new(sbom: sbom)

        # Check for new vulnerabilities since last scan
        last_scan = sbom.vulnerabilities.maximum(:created_at) || sbom.created_at

        # This would integrate with real CVE databases
        # For now, simulate checking
        new_vulns = sbom.vulnerabilities.where("created_at > ?", 1.day.ago)

        new_vulns.each do |vuln|
          new_cves << {
            vulnerability_id: vuln.vulnerability_id,
            severity: vuln.severity,
            cvss_score: vuln.cvss_score,
            affected_component: vuln.component&.name,
            affected_version: vuln.component&.version,
            sbom_id: sbom.id,
            sbom_name: sbom.name
          }
        end
      end

      new_cves
    end

    def check_account_wide(monitor)
      account = monitor.account

      sboms = account.supply_chain_sboms
      images = account.supply_chain_container_images

      alerts = []

      # Check SBOM vulnerabilities
      sboms.each do |sbom|
        critical_vulns = sbom.vulnerabilities.where(severity: "critical")
        high_vulns = sbom.vulnerabilities.where(severity: "high")

        if critical_vulns.any? && monitor.min_severity.in?(%w[critical high medium low])
          alerts << create_alert(monitor, sbom, critical_vulns.first, "critical")
        end

        if high_vulns.any? && monitor.min_severity.in?(%w[high medium low])
          alerts << create_alert(monitor, sbom, high_vulns.first, "high")
        end
      end

      # Notify for alerts
      alerts.compact.each do |alert|
        SupplyChainChannel.broadcast_cve_alert(account, alert)
      end
    end

    def check_repository_scope(monitor)
      # Repository-scoped monitoring
      return unless monitor.scope_id.present?

      sboms = monitor.account.supply_chain_sboms.where(repository_id: monitor.scope_id)
      check_sboms_for_monitor(monitor, sboms)
    end

    def check_image_scope(monitor)
      # Image-scoped monitoring
      return unless monitor.scope_id.present?

      image = monitor.account.supply_chain_container_images.find_by(id: monitor.scope_id)
      return unless image

      latest_scan = image.vulnerability_scans.order(created_at: :desc).first
      return unless latest_scan

      if latest_scan.critical_count > 0 && monitor.min_severity.in?(%w[critical high medium low])
        alert = {
          type: "container_vulnerability",
          severity: "critical",
          image_id: image.id,
          image_reference: image.full_reference,
          vulnerability_count: latest_scan.critical_count
        }
        SupplyChainChannel.broadcast_cve_alert(monitor.account, alert)
      end
    end

    def check_sboms_for_monitor(monitor, sboms)
      sboms.each do |sbom|
        vulns = sbom.vulnerabilities.where("severity IN (?)", severities_for_min(monitor.min_severity))

        vulns.where("created_at > ?", monitor.last_check_at || 1.day.ago).each do |vuln|
          alert = create_alert(monitor, sbom, vuln, vuln.severity)
          SupplyChainChannel.broadcast_cve_alert(monitor.account, alert) if alert
        end
      end
    end

    def create_alert(monitor, sbom, vuln, severity)
      {
        monitor_id: monitor.id,
        vulnerability_id: vuln.vulnerability_id,
        severity: severity,
        cvss_score: vuln.cvss_score,
        sbom_id: sbom.id,
        sbom_name: sbom.name,
        component: vuln.component&.name,
        version: vuln.component&.version,
        fixed_version: vuln.fixed_version
      }
    end

    def severities_for_min(min_severity)
      case min_severity
      when "critical" then %w[critical]
      when "high" then %w[critical high]
      when "medium" then %w[critical high medium]
      else %w[critical high medium low]
      end
    end
  end
end

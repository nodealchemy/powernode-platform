# frozen_string_literal: true

module SupplyChain
  class VendorMonitoringJob < ApplicationJob
    queue_as :supply_chain_monitoring

    def perform(account_id = nil)
      if account_id.present?
        account = Account.find(account_id)
        monitor_account_vendors(account)
      else
        # Monitor all accounts
        Account.joins(:supply_chain_vendors)
               .where(supply_chain_vendors: { status: "active" })
               .distinct
               .find_each do |account|
          monitor_account_vendors(account)
        end
      end
    end

    private

    def monitor_account_vendors(account)
      Rails.logger.info "[VendorMonitoringJob] Monitoring vendors for account #{account.id}"

      vendors = account.supply_chain_vendors.where(status: "active")

      vendors.each do |vendor|
        monitor_vendor(vendor)
      rescue StandardError => e
        Rails.logger.error "[VendorMonitoringJob] Failed to monitor vendor #{vendor.id}: #{e.message}"
      end
    end

    def monitor_vendor(vendor)
      events = ::SupplyChain::VendorRiskService.new(
        account: vendor.account,
        vendor: vendor
      ).monitor_vendor!

      # Broadcast any new events
      events.each do |event|
        SupplyChainChannel.broadcast_vendor_monitoring_event(event)
      end

      # Check for additional monitoring conditions
      check_assessment_due(vendor)
      check_contract_expiry(vendor)
      check_certification_expiry(vendor)
    end

    def check_assessment_due(vendor)
      return unless vendor.needs_assessment?

      # Check if we already have a recent notification
      recent_event = vendor.monitoring_events
                           .where(event_type: "compliance_update")
                           .where("created_at > ?", 7.days.ago)
                           .exists?

      return if recent_event

      event = ::SupplyChain::VendorMonitoringEvent.create!(
        vendor: vendor,
        account: vendor.account,
        event_type: "compliance_update",
        severity: "medium",
        source: "automated",
        title: "Risk assessment overdue",
        description: "Vendor #{vendor.name} requires a new risk assessment",
        recommended_actions: [
          {
            id: SecureRandom.uuid,
            action: "Schedule and complete vendor risk assessment",
            priority: "high",
            status: "pending",
            added_at: Time.current.iso8601
          }
        ]
      )

      SupplyChainChannel.broadcast_vendor_monitoring_event(event)
    end

    def check_contract_expiry(vendor)
      return unless vendor.contract_end_date.present?

      days_until_expiry = (vendor.contract_end_date.to_date - Date.current).to_i
      return unless days_until_expiry.between?(0, 60)

      # Check for recent notification
      recent_event = vendor.monitoring_events
                           .where(event_type: "contract_renewal")
                           .where("created_at > ?", 14.days.ago)
                           .exists?

      return if recent_event

      severity = days_until_expiry <= 14 ? "high" : (days_until_expiry <= 30 ? "medium" : "low")

      event = ::SupplyChain::VendorMonitoringEvent.create!(
        vendor: vendor,
        account: vendor.account,
        event_type: "contract_renewal",
        severity: severity,
        source: "automated",
        title: "Contract expiring soon",
        description: "Vendor #{vendor.name} contract expires in #{days_until_expiry} days (#{vendor.contract_end_date})",
        metadata: {
          contract_end_date: vendor.contract_end_date.iso8601,
          days_until_expiry: days_until_expiry
        },
        recommended_actions: [
          {
            id: SecureRandom.uuid,
            action: "Review and renew vendor contract",
            priority: severity,
            status: "pending",
            added_at: Time.current.iso8601
          }
        ]
      )

      SupplyChainChannel.broadcast_vendor_monitoring_event(event)
    end

    def check_certification_expiry(vendor)
      return unless vendor.certifications.present?

      vendor.certifications.each do |cert|
        next unless cert["expires_at"].present?

        expires_at = Time.parse(cert["expires_at"])
        days_until_expiry = ((expires_at - Time.current) / 1.day).to_i
        next unless days_until_expiry.between?(0, 30)

        # Check for recent notification
        recent_event = vendor.monitoring_events
                             .where(event_type: "certification_expiry")
                             .where("metadata->>'certification_name' = ?", cert["name"])
                             .where("created_at > ?", 14.days.ago)
                             .exists?

        next if recent_event

        severity = days_until_expiry <= 7 ? "high" : "medium"

        event = ::SupplyChain::VendorMonitoringEvent.create!(
          vendor: vendor,
          account: vendor.account,
          event_type: "certification_expiry",
          severity: severity,
          source: "automated",
          title: "Certification expiring: #{cert['name']}",
          description: "Vendor #{vendor.name}'s #{cert['name']} certification expires in #{days_until_expiry} days",
          metadata: {
            certification_name: cert["name"],
            expires_at: expires_at.iso8601,
            days_until_expiry: days_until_expiry
          },
          recommended_actions: [
            {
              id: SecureRandom.uuid,
              action: "Request updated certification from vendor",
              priority: severity,
              status: "pending",
              added_at: Time.current.iso8601
            }
          ]
        )

        SupplyChainChannel.broadcast_vendor_monitoring_event(event)
      end
    end
  end
end

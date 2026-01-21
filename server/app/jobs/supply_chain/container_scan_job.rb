# frozen_string_literal: true

module SupplyChain
  class ContainerScanJob < ApplicationJob
    queue_as :supply_chain_default

    def perform(container_image_id, options = {})
      image = ::SupplyChain::ContainerImage.find(container_image_id)
      account = image.account

      Rails.logger.info "[ContainerScanJob] Starting scan for container image #{container_image_id}"

      # Broadcast scan started
      SupplyChainChannel.broadcast_scan_started(image)

      # Perform scan
      scan = ::SupplyChain::ContainerScanService.new(
        account: account,
        image: image,
        options: options.with_indifferent_access
      ).scan!

      # Broadcast completion
      SupplyChainChannel.broadcast_scan_completed(scan)

      # Evaluate policies if requested
      if options[:evaluate_policies] != false
        result = ::SupplyChain::ContainerScanService.new(
          account: account,
          image: image
        ).evaluate_policies

        SupplyChainChannel.broadcast_policy_evaluation_completed(account, result)

        # Broadcast any violations
        result[:policy_results]&.each do |policy_result|
          next if policy_result[:passed] || policy_result[:skipped]

          SupplyChainChannel.broadcast_policy_violation(account, {
            policy_id: policy_result[:policy_id],
            policy_name: policy_result[:policy_name],
            violations: policy_result[:violations]
          })
        end
      end

      Rails.logger.info "[ContainerScanJob] Scan completed for container image #{container_image_id}"
    rescue StandardError => e
      Rails.logger.error "[ContainerScanJob] Failed: #{e.message}"
      raise e
    end
  end
end

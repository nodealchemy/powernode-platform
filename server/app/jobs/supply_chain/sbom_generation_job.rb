# frozen_string_literal: true

module SupplyChain
  class SbomGenerationJob < ApplicationJob
    queue_as :supply_chain_default

    def perform(account_id, repository_id, options = {})
      account = Account.find(account_id)
      repository = repository_id.present? ? account.devops_repositories.find(repository_id) : nil

      Rails.logger.info "[SbomGenerationJob] Starting SBOM generation for account #{account_id}"

      sbom = ::SupplyChain::SbomGenerationService.new(
        account: account,
        repository: repository,
        options: options.with_indifferent_access
      ).generate(
        source_path: options[:source_path],
        ecosystems: options[:ecosystems],
        format: options[:format] || "cyclonedx_1_5"
      )

      # Broadcast completion
      SupplyChainChannel.broadcast_sbom_created(sbom)

      # Auto-correlate vulnerabilities if enabled
      if options[:scan_vulnerabilities] != false
        ::SupplyChain::VulnerabilityScanJob.perform_later(sbom.id)
      end

      Rails.logger.info "[SbomGenerationJob] SBOM generation completed: #{sbom.id}"
    rescue StandardError => e
      Rails.logger.error "[SbomGenerationJob] Failed: #{e.message}"
      raise e
    end
  end
end

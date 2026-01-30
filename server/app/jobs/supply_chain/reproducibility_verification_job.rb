# frozen_string_literal: true

module SupplyChain
  class ReproducibilityVerificationJob < ApplicationJob
    queue_as :default

    def perform(provenance_id, user_id)
      provenance = ::SupplyChain::BuildProvenance.find(provenance_id)
      # Verification implementation would go here
      provenance.verify_reproducibility!
    rescue ActiveRecord::RecordNotFound => e
      Rails.logger.error("ReproducibilityVerificationJob: Provenance #{provenance_id} not found")
    rescue StandardError => e
      Rails.logger.error("ReproducibilityVerificationJob failed: #{e.message}")
    end
  end
end

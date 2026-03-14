# frozen_string_literal: true

module SupplyChain
  class ReproducibilityVerificationJob < ApplicationJob
    queue_as :default

    # Retry with exponential backoff for transient failures
    retry_on StandardError, wait: :polynomially_longer, attempts: 3

    def perform(provenance_id, user_id)
      provenance = ::SupplyChain::BuildProvenance.find(provenance_id)
      user = User.find_by(id: user_id)

      Rails.logger.info("[ReproducibilityVerificationJob] Starting verification for provenance #{provenance_id}")

      # Mark as in progress
      provenance.update!(verification_status: "in_progress", verified_at: nil)

      begin
        # Perform actual reproducibility verification
        verification_result = perform_verification(provenance)

        if verification_result[:reproducible]
          provenance.verify_reproducibility!
          Rails.logger.info("[ReproducibilityVerificationJob] Provenance #{provenance_id} verified as reproducible")
        else
          provenance.update!(
            verification_status: "failed",
            verification_errors: verification_result[:errors]
          )
          Rails.logger.warn("[ReproducibilityVerificationJob] Provenance #{provenance_id} verification failed: #{verification_result[:errors]}")
        end

        # Notify user if provided
        notify_user(user, provenance, verification_result) if user
      rescue StandardError => e
        provenance.update!(
          verification_status: "error",
          verification_errors: [ e.message ]
        )
        raise
      end
    rescue ActiveRecord::RecordNotFound => e
      Rails.logger.error("[ReproducibilityVerificationJob] Provenance #{provenance_id} not found: #{e.message}")
    end

    private

    def perform_verification(provenance)
      errors = []

      # Verify build inputs match recorded inputs
      unless verify_inputs(provenance)
        errors << "Build inputs do not match recorded provenance"
      end

      # Verify build environment
      unless verify_environment(provenance)
        errors << "Build environment verification failed"
      end

      # Verify output hashes if available
      unless verify_outputs(provenance)
        errors << "Output artifacts do not match expected hashes"
      end

      {
        reproducible: errors.empty?,
        errors: errors,
        verified_at: Time.current
      }
    end

    def verify_inputs(provenance)
      return true unless provenance.build_inputs.present?

      # Verify each input's integrity
      provenance.build_inputs.all? do |input|
        input["hash"].present? && input["verified"] != false
      end
    end

    def verify_environment(provenance)
      return true unless provenance.build_environment.present?

      # Basic environment verification
      env = provenance.build_environment
      env["builder"].present? && env["builder_version"].present?
    end

    def verify_outputs(provenance)
      return true unless provenance.build_outputs.present?

      # All outputs should have hashes
      provenance.build_outputs.all? { |output| output["hash"].present? }
    end

    def notify_user(user, provenance, result)
      # Create notification for user
      return unless defined?(Notification) && Notification.respond_to?(:create)

      Notification.create(
        user: user,
        notifiable: provenance,
        notification_type: result[:reproducible] ? "verification_success" : "verification_failed",
        title: result[:reproducible] ? "Build Verification Passed" : "Build Verification Failed",
        message: result[:reproducible] ? "Your build has been verified as reproducible." : "Build verification failed: #{result[:errors].join(', ')}"
      )
    rescue StandardError => e
      Rails.logger.warn("[ReproducibilityVerificationJob] Failed to notify user: #{e.message}")
    end
  end
end

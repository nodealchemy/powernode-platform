# frozen_string_literal: true

module Integrations
  class CredentialRotationJob < BaseJob
    sidekiq_options queue: 'integrations',
                    retry: 2,
                    dead: true

    # Rotate credentials for integration instances
    # Can rotate a single credential or check all for rotation needs
    def execute(credential_id = nil, options = {})
      if credential_id
        rotate_single_credential(credential_id, options)
      else
        check_and_rotate_expiring_credentials(options)
      end
    end

    private

    def rotate_single_credential(credential_id, options = {})
      log_info("Rotating credential", credential_id: credential_id)

      # Call the backend rotation endpoint
      response = api_client.post("/api/v1/integrations/credentials/#{credential_id}/rotate")

      if response[:success]
        log_info("Credential rotated successfully", credential_id: credential_id)
        increment_counter("credential_rotation_success")

        # Test instances using this credential
        if options[:test_after_rotation]
          test_instances_using_credential(credential_id)
        end

        { success: true, credential_id: credential_id }
      else
        log_error("Failed to rotate credential",
                  credential_id: credential_id,
                  error: response[:error])
        increment_counter("credential_rotation_failure")

        { success: false, credential_id: credential_id, error: response[:error] }
      end
    rescue StandardError => e
      log_error("Credential rotation error", exception: e, credential_id: credential_id)
      increment_counter("credential_rotation_error")

      { success: false, credential_id: credential_id, error: e.message }
    end

    def check_and_rotate_expiring_credentials(options = {})
      log_info("Checking for credentials requiring rotation")

      days_before_expiry = options[:days_before_expiry] || 7
      rotated = 0
      failed = 0
      skipped = 0

      # Fetch all credentials
      page = 1

      loop do
        response = api_client.get("/api/v1/integrations/credentials", {
          page: page,
          per_page: 50
        })

        break unless response[:success]

        credentials = response[:data][:credentials] || []
        break if credentials.empty?

        credentials.each do |credential|
          if needs_rotation?(credential, days_before_expiry)
            result = rotate_single_credential(credential[:id], options)

            if result[:success]
              rotated += 1
            else
              failed += 1
            end
          else
            skipped += 1
          end
        end

        # Check for more pages
        pagination = response[:data][:pagination]
        break if page >= (pagination[:total_pages] || 1)

        page += 1
      end

      log_info("Credential rotation check completed",
               rotated: rotated,
               failed: failed,
               skipped: skipped)

      track_cleanup_metrics(
        credentials_rotated: rotated,
        credentials_rotation_failed: failed,
        credentials_skipped: skipped
      )

      { rotated: rotated, failed: failed, skipped: skipped }
    end

    def needs_rotation?(credential, days_before_expiry)
      # Check if credential has an expiry date
      expires_at = credential[:expires_at]
      return false unless expires_at

      expiry_time = Time.parse(expires_at)
      days_until_expiry = (expiry_time - Time.current) / 1.day

      days_until_expiry <= days_before_expiry
    rescue StandardError
      false
    end

    def test_instances_using_credential(credential_id)
      log_info("Testing instances using rotated credential", credential_id: credential_id)

      # Fetch instances using this credential
      response = api_client.get("/api/v1/integrations/instances", {
        credential_id: credential_id,
        status: "active"
      })

      return unless response[:success]

      instances = response[:data][:instances] || []

      instances.each do |instance|
        test_result = api_client.post("/api/v1/integrations/instances/#{instance[:id]}/test")

        if test_result[:success] && test_result[:data][:result][:success]
          log_info("Instance test passed after rotation",
                   instance_id: instance[:id],
                   credential_id: credential_id)
        else
          log_warn("Instance test failed after rotation",
                   instance_id: instance[:id],
                   credential_id: credential_id,
                   error: test_result[:data]&.dig(:result, :error))
        end
      end
    rescue StandardError => e
      log_error("Failed to test instances after rotation", exception: e, credential_id: credential_id)
    end
  end
end

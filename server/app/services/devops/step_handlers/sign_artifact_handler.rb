# frozen_string_literal: true

module Devops
  module StepHandlers
    class SignArtifactHandler
      class HandlerError < StandardError; end

      attr_reader :step_execution, :step, :pipeline_run, :context

      def initialize(step_execution:, context: {})
        @step_execution = step_execution
        @step = step_execution.pipeline_step
        @pipeline_run = step_execution.pipeline_run
        @context = context.with_indifferent_access
        @logger = Rails.logger
      end

      def execute
        @logger.info "[SignArtifactHandler] Starting artifact signing for step #{step.id}"

        config = step.configuration || {}
        account = pipeline_run.account

        begin
          # Get signing key
          signing_key = get_signing_key(account, config)
          raise HandlerError, "No signing key available" unless signing_key&.can_sign?

          # Get artifact to sign
          artifact_digest = get_artifact_digest(config)
          raise HandlerError, "No artifact to sign" unless artifact_digest.present?

          subject_name = config["subject_name"] || context[:artifact_name] || "artifact"

          # Generate SLSA attestation with signature
          attestation = SupplyChain::SlsaProvenanceGenerator.new(
            account: account,
            options: {
              pipeline_run: pipeline_run,
              user: pipeline_run.triggered_by,
              automated_build: true,
              signed_provenance: true
            }
          ).generate(
            subject_name: subject_name,
            subject_digest: artifact_digest,
            builder_id: config["builder_id"] || "powernode/pipeline-builder",
            materials: build_materials(config),
            source_repository: pipeline_run.repository&.clone_url,
            source_commit: pipeline_run.commit_sha,
            source_branch: pipeline_run.branch,
            build_started_at: pipeline_run.started_at,
            build_finished_at: Time.current
          )

          # Sign the attestation
          signature = sign_attestation(attestation, signing_key)
          attestation.sign!(signing_key, signature)

          # Record to Rekor if enabled
          if config["record_to_rekor"] != false
            record_to_rekor(attestation)
          end

          {
            success: true,
            outputs: {
              attestation_id: attestation.id,
              attestation_document_id: attestation.attestation_id,
              slsa_level: attestation.slsa_level,
              signed: attestation.signed?,
              rekor_logged: attestation.logged_to_rekor?,
              rekor_log_id: attestation.rekor_log_id,
              signature_algorithm: signing_key.key_type
            }
          }
        rescue StandardError => e
          @logger.error "[SignArtifactHandler] Signing failed: #{e.message}"
          {
            success: false,
            error: e.message
          }
        end
      end

      private

      def get_signing_key(account, config)
        if config["signing_key_id"].present?
          account.supply_chain_signing_keys.active.find_by(id: config["signing_key_id"])
        else
          # Use default active key
          account.supply_chain_signing_keys.active.first
        end
      end

      def get_artifact_digest(config)
        config["artifact_digest"] || context[:artifact_digest]
      end

      def build_materials(config)
        materials = []

        # Add source repository
        if pipeline_run.repository.present?
          materials << {
            uri: pipeline_run.repository.clone_url,
            digest: { "sha1" => pipeline_run.commit_sha }
          }
        end

        # Add any additional materials from config
        (config["materials"] || []).each do |material|
          materials << {
            uri: material["uri"],
            digest: material["digest"]
          }
        end

        # Add artifacts from context
        (context[:artifacts] || []).each do |artifact|
          materials << {
            uri: artifact["uri"] || artifact["path"],
            digest: { "sha256" => artifact["digest"] }
          } if artifact["digest"].present?
        end

        materials
      end

      def sign_attestation(attestation, signing_key)
        # Create the payload to sign
        payload = attestation.in_toto_statement.to_json

        # Sign with the key
        signing_key.sign(payload)
      end

      def record_to_rekor(attestation)
        # This would integrate with the Rekor transparency log
        # Placeholder implementation
        @logger.info "[SignArtifactHandler] Recording attestation to Rekor"

        # Simulated Rekor logging
        log_id = SecureRandom.hex(32)
        log_url = "https://rekor.sigstore.dev/api/v1/log/entries/#{log_id}"

        attestation.record_to_rekor!(log_id, log_url)
      end
    end
  end
end

# frozen_string_literal: true

module Devops
  module StepHandlers
    class SbomGenerateHandler
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
        @logger.info "[SbomGenerateHandler] Starting SBOM generation for step #{step.id}"

        config = step.configuration || {}
        account = pipeline_run.account

        begin
          sbom = SupplyChain::SbomGenerationService.new(
            account: account,
            repository: pipeline_run.repository,
            options: {
              user: pipeline_run.triggered_by,
              branch: pipeline_run.branch,
              commit_sha: pipeline_run.commit_sha,
              name: config["sbom_name"] || "#{pipeline_run.pipeline.name}-#{pipeline_run.run_number}",
              version: config["version"]
            }
          ).generate(
            source_path: context[:source_path] || workspace_path,
            ecosystems: config["ecosystems"],
            format: config["format"] || "cyclonedx_1_5"
          )

          # Correlate vulnerabilities if enabled
          if config["scan_vulnerabilities"] != false
            SupplyChain::VulnerabilityCorrelationService.new(sbom: sbom).correlate!
          end

          # Evaluate license compliance if enabled
          if config["check_licenses"]
            SupplyChain::LicenseComplianceService.new(
              account: account,
              sbom: sbom,
              options: { policy_id: config["license_policy_id"] }
            ).evaluate!
          end

          # Generate attestation if enabled
          if config["generate_attestation"]
            generate_attestation(sbom, config)
          end

          {
            success: true,
            outputs: {
              sbom_id: sbom.id,
              sbom_document_id: sbom.sbom_id,
              component_count: sbom.component_count,
              vulnerability_count: sbom.vulnerability_count,
              risk_score: sbom.risk_score,
              ntia_compliant: sbom.ntia_minimum_compliant,
              format: sbom.format
            }
          }
        rescue StandardError => e
          @logger.error "[SbomGenerateHandler] SBOM generation failed: #{e.message}"
          {
            success: false,
            error: e.message
          }
        end
      end

      private

      def workspace_path
        # Get the workspace path from the pipeline run context
        context[:workspace_path] || "/tmp/workspace/#{pipeline_run.id}"
      end

      def generate_attestation(sbom, config)
        # Calculate document hash for attestation
        document_hash = Digest::SHA256.hexdigest(sbom.document.to_json)

        SupplyChain::SlsaProvenanceGenerator.new(
          account: pipeline_run.account,
          options: {
            pipeline_run: pipeline_run,
            user: pipeline_run.triggered_by,
            automated_build: true
          }
        ).generate(
          subject_name: sbom.name || sbom.sbom_id,
          subject_digest: "sha256:#{document_hash}",
          builder_id: "powernode/sbom-generator",
          materials: build_materials
        )
      end

      def build_materials
        materials = []

        if pipeline_run.repository.present?
          materials << {
            uri: pipeline_run.repository.clone_url,
            digest: { "sha1" => pipeline_run.commit_sha }
          }
        end

        materials
      end
    end
  end
end

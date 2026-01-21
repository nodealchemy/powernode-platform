# frozen_string_literal: true

module SupplyChain
  class SlsaProvenanceGenerator
    class ProvenanceError < StandardError; end

    SLSA_PREDICATE_TYPE_V1 = "https://slsa.dev/provenance/v1"
    SLSA_PREDICATE_TYPE_V0_2 = "https://slsa.dev/provenance/v0.2"

    attr_reader :account, :options

    def initialize(account:, options: {})
      @account = account
      @options = options.with_indifferent_access
      @logger = Rails.logger
    end

    def generate(subject_name:, subject_digest:, builder_id:, materials: [], **build_info)
      attestation = create_attestation(subject_name, subject_digest)

      provenance = create_build_provenance(
        attestation,
        builder_id: builder_id,
        materials: materials,
        **build_info
      )

      # Set the predicate on the attestation
      attestation.update!(predicate: provenance.to_slsa_predicate)

      attestation
    end

    def generate_for_pipeline_run(pipeline_run, artifact_digest:)
      subject_name = "#{pipeline_run.pipeline.name}:#{pipeline_run.run_number}"

      materials = build_materials_from_pipeline(pipeline_run)
      builder_id = determine_builder_id(pipeline_run)

      generate(
        subject_name: subject_name,
        subject_digest: artifact_digest,
        builder_id: builder_id,
        materials: materials,
        source_repository: pipeline_run.repository&.clone_url,
        source_commit: pipeline_run.commit_sha,
        source_branch: pipeline_run.branch,
        build_started_at: pipeline_run.started_at,
        build_finished_at: pipeline_run.completed_at,
        pipeline_run: pipeline_run
      )
    end

    def generate_for_container_image(image, build_context: {})
      generate(
        subject_name: image.full_reference,
        subject_digest: image.digest,
        builder_id: build_context[:builder_id] || "docker",
        materials: build_context[:materials] || [],
        source_repository: build_context[:source_repository],
        source_commit: build_context[:source_commit],
        build_started_at: build_context[:build_started_at],
        build_finished_at: build_context[:build_finished_at]
      )
    end

    private

    def create_attestation(subject_name, subject_digest)
      algorithm, digest = parse_digest(subject_digest)

      SupplyChain::Attestation.create!(
        account: account,
        attestation_type: "slsa_provenance",
        slsa_level: determine_slsa_level,
        subject_name: subject_name,
        subject_digest: digest,
        subject_digest_algorithm: algorithm,
        predicate_type: SLSA_PREDICATE_TYPE_V1,
        verification_status: "unverified",
        created_by: options[:user],
        pipeline_run: options[:pipeline_run]
      )
    end

    def create_build_provenance(attestation, builder_id:, materials:, **build_info)
      SupplyChain::BuildProvenance.create!(
        attestation: attestation,
        account: account,
        builder_id: builder_id,
        builder_version: build_info[:builder_version],
        materials: normalize_materials(materials),
        invocation: build_invocation(build_info),
        build_config: build_info[:build_config] || {},
        environment: build_info[:environment] || {},
        source_repository: build_info[:source_repository],
        source_commit: build_info[:source_commit],
        source_branch: build_info[:source_branch],
        build_started_at: build_info[:build_started_at],
        build_finished_at: build_info[:build_finished_at],
        reproducible: build_info[:reproducible] || false
      )
    end

    def parse_digest(digest_string)
      if digest_string.include?(":")
        parts = digest_string.split(":", 2)
        [parts[0], parts[1]]
      else
        ["sha256", digest_string]
      end
    end

    def determine_slsa_level
      # Determine SLSA level based on available build information
      level = 1

      # Level 2: Build service generates provenance
      level = 2 if options[:automated_build]

      # Level 3: Hardened build platform with non-falsifiable provenance
      level = 3 if options[:hardened_build] && options[:signed_provenance]

      level
    end

    def normalize_materials(materials)
      materials.map do |material|
        {
          "uri" => material[:uri] || material["uri"],
          "digest" => normalize_digest(material[:digest] || material["digest"])
        }
      end
    end

    def normalize_digest(digest)
      return {} unless digest.present?

      if digest.is_a?(String)
        algorithm, value = parse_digest(digest)
        { algorithm => value }
      else
        digest
      end
    end

    def build_invocation(build_info)
      {
        "configSource" => {
          "uri" => build_info[:source_repository],
          "digest" => { "sha1" => build_info[:source_commit] },
          "entryPoint" => build_info[:entry_point] || "Dockerfile"
        },
        "parameters" => build_info[:parameters] || {},
        "environment" => build_info[:environment] || {}
      }
    end

    def build_materials_from_pipeline(pipeline_run)
      materials = []

      # Add source repository as material
      if pipeline_run.repository.present?
        materials << {
          uri: pipeline_run.repository.clone_url,
          digest: { "sha1" => pipeline_run.commit_sha }
        }
      end

      # Add any artifacts from previous steps
      pipeline_run.step_executions.completed.each do |step|
        if step.outputs.present? && step.outputs["artifacts"].present?
          step.outputs["artifacts"].each do |artifact|
            materials << {
              uri: artifact["url"] || artifact["path"],
              digest: { "sha256" => artifact["digest"] }
            } if artifact["digest"].present?
          end
        end
      end

      materials
    end

    def determine_builder_id(pipeline_run)
      # Use the pipeline's builder configuration or default
      builder = pipeline_run.pipeline.metadata&.dig("builder") || {}

      if builder["id"].present?
        builder["id"]
      elsif pipeline_run.pipeline.is_system?
        "powernode/system-builder"
      else
        "powernode/user-builder/#{account.id}"
      end
    end
  end
end

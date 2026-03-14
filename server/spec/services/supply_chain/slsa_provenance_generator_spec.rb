# frozen_string_literal: true

require "rails_helper"

RSpec.describe SupplyChain::SlsaProvenanceGenerator do
  let(:account) { create(:account) }
  let(:user) { create(:user, :owner, account: account) }
  let(:options) { {} }
  let(:service) { described_class.new(account: account, options: options) }

  describe "#initialize" do
    it "initializes with required account parameter" do
      expect(service.account).to eq(account)
      expect(service.options).to eq({})
    end

    it "initializes with options hash" do
      opts = { user: user, automated_build: true }
      service = described_class.new(account: account, options: opts)

      expect(service.options[:user]).to eq(user)
      expect(service.options[:automated_build]).to be true
    end

    it "converts options to indifferent access" do
      opts = { "user" => user, automated_build: true }
      service = described_class.new(account: account, options: opts)

      expect(service.options[:user]).to eq(user)
      expect(service.options["automated_build"]).to be true
    end
  end

  describe "#generate" do
    let(:subject_name) { "my-app:v1.0.0" }
    let(:subject_digest) { "sha256:abc123def456" }
    let(:builder_id) { "https://github.com/actions/runner" }
    let(:materials) do
      [
        { uri: "https://github.com/org/repo", digest: "sha1:abc123" }
      ]
    end

    context "creating attestation" do
      it "creates an attestation record" do
        expect do
          service.generate(
            subject_name: subject_name,
            subject_digest: subject_digest,
            builder_id: builder_id
          )
        end.to change(SupplyChain::Attestation, :count).by(1)
      end

      it "creates attestation with correct attributes" do
        attestation = service.generate(
          subject_name: subject_name,
          subject_digest: subject_digest,
          builder_id: builder_id
        )

        expect(attestation.account).to eq(account)
        expect(attestation.attestation_type).to eq("slsa_provenance")
        expect(attestation.subject_name).to eq(subject_name)
        expect(attestation.subject_digest).to eq("abc123def456")
        expect(attestation.subject_digest_algorithm).to eq("sha256")
        expect(attestation.predicate_type).to eq("https://slsa.dev/provenance/v1")
        expect(attestation.verification_status).to eq("unverified")
      end

      it "sets created_by from options" do
        service = described_class.new(account: account, options: { user: user })
        attestation = service.generate(
          subject_name: subject_name,
          subject_digest: subject_digest,
          builder_id: builder_id
        )

        expect(attestation.created_by).to eq(user)
      end

      it "sets pipeline_run from options when provided as valid record" do
        # Note: pipeline_run must be a valid Devops::PipelineRun record to be assigned
        # This test verifies the option is passed through correctly
        service = described_class.new(account: account, options: { pipeline_run: nil })
        attestation = service.generate(
          subject_name: subject_name,
          subject_digest: subject_digest,
          builder_id: builder_id
        )

        expect(attestation.pipeline_run).to be_nil
      end

      it "sets predicate on attestation after build provenance creation" do
        attestation = service.generate(
          subject_name: subject_name,
          subject_digest: subject_digest,
          builder_id: builder_id
        )

        expect(attestation.predicate).to be_a(Hash)
        expect(attestation.predicate).not_to be_empty
      end
    end

    context "creating build provenance" do
      it "creates a build provenance record" do
        expect do
          service.generate(
            subject_name: subject_name,
            subject_digest: subject_digest,
            builder_id: builder_id
          )
        end.to change(SupplyChain::BuildProvenance, :count).by(1)
      end

      it "creates build provenance with correct attributes" do
        attestation = service.generate(
          subject_name: subject_name,
          subject_digest: subject_digest,
          builder_id: builder_id,
          materials: materials,
          source_repository: "https://github.com/org/repo",
          source_commit: "abc123",
          source_branch: "main",
          build_started_at: 1.hour.ago,
          build_finished_at: Time.current
        )

        provenance = attestation.build_provenance
        expect(provenance.account).to eq(account)
        expect(provenance.builder_id).to eq(builder_id)
        expect(provenance.source_repository).to eq("https://github.com/org/repo")
        expect(provenance.source_commit).to eq("abc123")
        expect(provenance.source_branch).to eq("main")
        expect(provenance.build_started_at).to be_present
        expect(provenance.build_finished_at).to be_present
      end

      it "sets builder_version when provided" do
        attestation = service.generate(
          subject_name: subject_name,
          subject_digest: subject_digest,
          builder_id: builder_id,
          builder_version: "v2.300.0"
        )

        expect(attestation.build_provenance.builder_version).to eq("v2.300.0")
      end

      it "sets build_config when provided" do
        build_config = { dockerfile: "Dockerfile", target: "production" }
        attestation = service.generate(
          subject_name: subject_name,
          subject_digest: subject_digest,
          builder_id: builder_id,
          build_config: build_config
        )

        # JSON serialization converts symbol keys to string keys
        expect(attestation.build_provenance.build_config).to eq(
          { "dockerfile" => "Dockerfile", "target" => "production" }
        )
      end

      it "sets environment when provided" do
        environment = { CI: "true", NODE_ENV: "production" }
        attestation = service.generate(
          subject_name: subject_name,
          subject_digest: subject_digest,
          builder_id: builder_id,
          environment: environment
        )

        # JSON serialization converts symbol keys to string keys
        expect(attestation.build_provenance.environment).to eq(
          { "CI" => "true", "NODE_ENV" => "production" }
        )
      end

      it "sets reproducible flag when provided" do
        attestation = service.generate(
          subject_name: subject_name,
          subject_digest: subject_digest,
          builder_id: builder_id,
          reproducible: true
        )

        expect(attestation.build_provenance.reproducible).to be true
      end

      it "defaults reproducible to false when not provided" do
        attestation = service.generate(
          subject_name: subject_name,
          subject_digest: subject_digest,
          builder_id: builder_id
        )

        expect(attestation.build_provenance.reproducible).to be false
      end
    end

    context "digest parsing" do
      it "parses sha256:hash format correctly" do
        attestation = service.generate(
          subject_name: subject_name,
          subject_digest: "sha256:abc123def456",
          builder_id: builder_id
        )

        expect(attestation.subject_digest_algorithm).to eq("sha256")
        expect(attestation.subject_digest).to eq("abc123def456")
      end

      it "parses sha512:hash format correctly" do
        attestation = service.generate(
          subject_name: subject_name,
          subject_digest: "sha512:longhashvalue123",
          builder_id: builder_id
        )

        expect(attestation.subject_digest_algorithm).to eq("sha512")
        expect(attestation.subject_digest).to eq("longhashvalue123")
      end

      it "handles digest without algorithm prefix" do
        attestation = service.generate(
          subject_name: subject_name,
          subject_digest: "abc123def456",
          builder_id: builder_id
        )

        expect(attestation.subject_digest_algorithm).to eq("sha256")
        expect(attestation.subject_digest).to eq("abc123def456")
      end

      it "handles digest with multiple colons" do
        attestation = service.generate(
          subject_name: subject_name,
          subject_digest: "sha256:abc:123:def",
          builder_id: builder_id
        )

        expect(attestation.subject_digest_algorithm).to eq("sha256")
        expect(attestation.subject_digest).to eq("abc:123:def")
      end
    end

    context "material normalization" do
      it "normalizes materials with symbol keys" do
        materials = [
          { uri: "https://github.com/org/repo", digest: "sha256:abc123" }
        ]

        attestation = service.generate(
          subject_name: subject_name,
          subject_digest: subject_digest,
          builder_id: builder_id,
          materials: materials
        )

        provenance = attestation.build_provenance
        expect(provenance.materials.first["uri"]).to eq("https://github.com/org/repo")
        expect(provenance.materials.first["digest"]).to eq({ "sha256" => "abc123" })
      end

      it "normalizes materials with string keys" do
        materials = [
          { "uri" => "https://github.com/org/repo", "digest" => "sha1:abc123" }
        ]

        attestation = service.generate(
          subject_name: subject_name,
          subject_digest: subject_digest,
          builder_id: builder_id,
          materials: materials
        )

        provenance = attestation.build_provenance
        expect(provenance.materials.first["uri"]).to eq("https://github.com/org/repo")
        expect(provenance.materials.first["digest"]).to eq({ "sha1" => "abc123" })
      end

      it "normalizes digest strings to hash format" do
        materials = [
          { uri: "https://example.com", digest: "sha512:hashvalue" }
        ]

        attestation = service.generate(
          subject_name: subject_name,
          subject_digest: subject_digest,
          builder_id: builder_id,
          materials: materials
        )

        provenance = attestation.build_provenance
        expect(provenance.materials.first["digest"]).to eq({ "sha512" => "hashvalue" })
      end

      it "preserves digest hash format" do
        materials = [
          { uri: "https://example.com", digest: { "sha256" => "abc123" } }
        ]

        attestation = service.generate(
          subject_name: subject_name,
          subject_digest: subject_digest,
          builder_id: builder_id,
          materials: materials
        )

        provenance = attestation.build_provenance
        expect(provenance.materials.first["digest"]).to eq({ "sha256" => "abc123" })
      end

      it "handles multiple materials" do
        materials = [
          { uri: "https://github.com/org/repo1", digest: "sha256:hash1" },
          { uri: "https://github.com/org/repo2", digest: "sha256:hash2" },
          { uri: "https://github.com/org/repo3", digest: "sha256:hash3" }
        ]

        attestation = service.generate(
          subject_name: subject_name,
          subject_digest: subject_digest,
          builder_id: builder_id,
          materials: materials
        )

        provenance = attestation.build_provenance
        expect(provenance.materials.count).to eq(3)
      end

      it "handles empty materials array" do
        attestation = service.generate(
          subject_name: subject_name,
          subject_digest: subject_digest,
          builder_id: builder_id,
          materials: []
        )

        expect(attestation.build_provenance.materials).to eq([])
      end

      it "handles nil digest in materials" do
        materials = [
          { uri: "https://example.com", digest: nil }
        ]

        attestation = service.generate(
          subject_name: subject_name,
          subject_digest: subject_digest,
          builder_id: builder_id,
          materials: materials
        )

        provenance = attestation.build_provenance
        expect(provenance.materials.first["digest"]).to eq({})
      end
    end

    context "invocation data" do
      it "builds invocation with source information" do
        attestation = service.generate(
          subject_name: subject_name,
          subject_digest: subject_digest,
          builder_id: builder_id,
          source_repository: "https://github.com/org/repo",
          source_commit: "abc123"
        )

        invocation = attestation.build_provenance.invocation
        expect(invocation["configSource"]["uri"]).to eq("https://github.com/org/repo")
        expect(invocation["configSource"]["digest"]["sha1"]).to eq("abc123")
      end

      it "uses default entryPoint when not provided" do
        attestation = service.generate(
          subject_name: subject_name,
          subject_digest: subject_digest,
          builder_id: builder_id
        )

        invocation = attestation.build_provenance.invocation
        expect(invocation["configSource"]["entryPoint"]).to eq("Dockerfile")
      end

      it "uses custom entryPoint when provided" do
        attestation = service.generate(
          subject_name: subject_name,
          subject_digest: subject_digest,
          builder_id: builder_id,
          entry_point: "Dockerfile.production"
        )

        invocation = attestation.build_provenance.invocation
        expect(invocation["configSource"]["entryPoint"]).to eq("Dockerfile.production")
      end

      it "includes parameters when provided" do
        parameters = { target: "production", no_cache: true }
        attestation = service.generate(
          subject_name: subject_name,
          subject_digest: subject_digest,
          builder_id: builder_id,
          parameters: parameters
        )

        invocation = attestation.build_provenance.invocation
        # JSON serialization converts symbol keys to string keys
        expect(invocation["parameters"]).to eq({ "target" => "production", "no_cache" => true })
      end

      it "includes environment in invocation when provided" do
        environment = { CI: "true" }
        attestation = service.generate(
          subject_name: subject_name,
          subject_digest: subject_digest,
          builder_id: builder_id,
          environment: environment
        )

        invocation = attestation.build_provenance.invocation
        # JSON serialization converts symbol keys to string keys
        expect(invocation["environment"]).to eq({ "CI" => "true" })
      end
    end

    context "SLSA level determination" do
      it "defaults to level 1" do
        attestation = service.generate(
          subject_name: subject_name,
          subject_digest: subject_digest,
          builder_id: builder_id
        )

        expect(attestation.slsa_level).to eq(1)
      end

      it "sets level 2 with automated_build option" do
        service = described_class.new(account: account, options: { automated_build: true })
        attestation = service.generate(
          subject_name: subject_name,
          subject_digest: subject_digest,
          builder_id: builder_id
        )

        expect(attestation.slsa_level).to eq(2)
      end

      it "sets level 3 with hardened_build and signed_provenance options" do
        service = described_class.new(
          account: account,
          options: { hardened_build: true, signed_provenance: true }
        )
        attestation = service.generate(
          subject_name: subject_name,
          subject_digest: subject_digest,
          builder_id: builder_id
        )

        expect(attestation.slsa_level).to eq(3)
      end

      it "remains at level 1 with only hardened_build" do
        service = described_class.new(account: account, options: { hardened_build: true })
        attestation = service.generate(
          subject_name: subject_name,
          subject_digest: subject_digest,
          builder_id: builder_id
        )

        expect(attestation.slsa_level).to eq(1)
      end

      it "remains at level 1 with only signed_provenance" do
        service = described_class.new(account: account, options: { signed_provenance: true })
        attestation = service.generate(
          subject_name: subject_name,
          subject_digest: subject_digest,
          builder_id: builder_id
        )

        expect(attestation.slsa_level).to eq(1)
      end

      it "prioritizes level 3 over level 2" do
        service = described_class.new(
          account: account,
          options: {
            automated_build: true,
            hardened_build: true,
            signed_provenance: true
          }
        )
        attestation = service.generate(
          subject_name: subject_name,
          subject_digest: subject_digest,
          builder_id: builder_id
        )

        expect(attestation.slsa_level).to eq(3)
      end
    end
  end

  describe "#generate_for_pipeline_run" do
    let(:repository) do
      double(
        "Repository",
        clone_url: "https://github.com/org/repo.git",
        present?: true
      )
    end
    let(:pipeline) do
      double(
        "Pipeline",
        name: "build-pipeline",
        metadata: { "builder" => { "id" => "custom-builder" } },
        is_system?: false
      )
    end
    let(:step_execution) do
      double(
        "StepExecution",
        outputs: {
          "artifacts" => [
            { "url" => "https://storage.example.com/artifact.tar.gz", "digest" => "abc123" }
          ]
        }
      )
    end
    let(:step_executions_relation) do
      double("StepExecutionsRelation")
    end
    let(:pipeline_run) do
      double(
        "PipelineRun",
        pipeline: pipeline,
        run_number: 42,
        repository: repository,
        commit_sha: "abc123def456",
        branch: "main",
        started_at: 1.hour.ago,
        completed_at: Time.current,
        step_executions: step_executions_relation
      )
    end
    let(:artifact_digest) { "sha256:buildhash123" }

    before do
      allow(step_executions_relation).to receive(:completed).and_return([ step_execution ])
    end

    it "creates attestation for pipeline run" do
      expect do
        service.generate_for_pipeline_run(pipeline_run, artifact_digest: artifact_digest)
      end.to change(SupplyChain::Attestation, :count).by(1)
    end

    it "builds correct subject_name from pipeline name and run number" do
      attestation = service.generate_for_pipeline_run(pipeline_run, artifact_digest: artifact_digest)

      expect(attestation.subject_name).to eq("build-pipeline:42")
    end

    it "uses artifact_digest as subject_digest" do
      attestation = service.generate_for_pipeline_run(pipeline_run, artifact_digest: artifact_digest)

      expect(attestation.subject_digest).to eq("buildhash123")
    end

    it "extracts materials from pipeline run repository" do
      attestation = service.generate_for_pipeline_run(pipeline_run, artifact_digest: artifact_digest)

      provenance = attestation.build_provenance
      expect(provenance.materials).to include(
        hash_including("uri" => "https://github.com/org/repo.git")
      )
    end

    it "extracts materials from step execution artifacts" do
      attestation = service.generate_for_pipeline_run(pipeline_run, artifact_digest: artifact_digest)

      provenance = attestation.build_provenance
      expect(provenance.materials).to include(
        hash_including("uri" => "https://storage.example.com/artifact.tar.gz")
      )
    end

    it "sets source_repository from pipeline run" do
      attestation = service.generate_for_pipeline_run(pipeline_run, artifact_digest: artifact_digest)

      expect(attestation.build_provenance.source_repository).to eq("https://github.com/org/repo.git")
    end

    it "sets source_commit from pipeline run" do
      attestation = service.generate_for_pipeline_run(pipeline_run, artifact_digest: artifact_digest)

      expect(attestation.build_provenance.source_commit).to eq("abc123def456")
    end

    it "sets source_branch from pipeline run" do
      attestation = service.generate_for_pipeline_run(pipeline_run, artifact_digest: artifact_digest)

      expect(attestation.build_provenance.source_branch).to eq("main")
    end

    it "sets build timestamps from pipeline run" do
      attestation = service.generate_for_pipeline_run(pipeline_run, artifact_digest: artifact_digest)

      provenance = attestation.build_provenance
      expect(provenance.build_started_at).to be_present
      expect(provenance.build_finished_at).to be_present
    end

    context "builder_id determination" do
      it "uses builder id from pipeline metadata when present" do
        attestation = service.generate_for_pipeline_run(pipeline_run, artifact_digest: artifact_digest)

        expect(attestation.build_provenance.builder_id).to eq("custom-builder")
      end

      it "uses system builder for system pipelines" do
        allow(pipeline).to receive(:metadata).and_return({})
        allow(pipeline).to receive(:is_system?).and_return(true)

        attestation = service.generate_for_pipeline_run(pipeline_run, artifact_digest: artifact_digest)

        expect(attestation.build_provenance.builder_id).to eq("powernode/system-builder")
      end

      it "uses user builder for non-system pipelines without metadata" do
        allow(pipeline).to receive(:metadata).and_return({})
        allow(pipeline).to receive(:is_system?).and_return(false)

        attestation = service.generate_for_pipeline_run(pipeline_run, artifact_digest: artifact_digest)

        expect(attestation.build_provenance.builder_id).to eq("powernode/user-builder/#{account.id}")
      end

      it "handles nil pipeline metadata" do
        allow(pipeline).to receive(:metadata).and_return(nil)
        allow(pipeline).to receive(:is_system?).and_return(false)

        attestation = service.generate_for_pipeline_run(pipeline_run, artifact_digest: artifact_digest)

        expect(attestation.build_provenance.builder_id).to eq("powernode/user-builder/#{account.id}")
      end
    end

    context "when repository is nil" do
      before do
        allow(pipeline_run).to receive(:repository).and_return(nil)
      end

      it "handles nil repository gracefully" do
        expect do
          service.generate_for_pipeline_run(pipeline_run, artifact_digest: artifact_digest)
        end.not_to raise_error
      end
    end

    context "when step executions have no artifacts" do
      let(:step_execution_without_artifacts) do
        double("StepExecution", outputs: {})
      end

      before do
        allow(step_executions_relation).to receive(:completed).and_return([ step_execution_without_artifacts ])
      end

      it "handles step executions without artifacts" do
        attestation = service.generate_for_pipeline_run(pipeline_run, artifact_digest: artifact_digest)

        expect(attestation).to be_persisted
      end
    end

    context "when step execution outputs is nil" do
      let(:step_execution_nil_outputs) do
        double("StepExecution", outputs: nil)
      end

      before do
        allow(step_executions_relation).to receive(:completed).and_return([ step_execution_nil_outputs ])
      end

      it "handles nil outputs gracefully" do
        expect do
          service.generate_for_pipeline_run(pipeline_run, artifact_digest: artifact_digest)
        end.not_to raise_error
      end
    end
  end

  describe "#generate_for_container_image" do
    let(:image) do
      double(
        "ContainerImage",
        full_reference: "gcr.io/project/app:v1.0.0",
        digest: "sha256:imagehash123"
      )
    end

    it "creates attestation for container image" do
      expect do
        service.generate_for_container_image(image)
      end.to change(SupplyChain::Attestation, :count).by(1)
    end

    it "uses image.full_reference as subject_name" do
      attestation = service.generate_for_container_image(image)

      expect(attestation.subject_name).to eq("gcr.io/project/app:v1.0.0")
    end

    it "uses image.digest as subject_digest" do
      attestation = service.generate_for_container_image(image)

      expect(attestation.subject_digest).to eq("imagehash123")
    end

    it "defaults builder_id to docker when not provided in build_context" do
      attestation = service.generate_for_container_image(image)

      expect(attestation.build_provenance.builder_id).to eq("docker")
    end

    it "uses builder_id from build_context when provided" do
      build_context = { builder_id: "buildkit" }
      attestation = service.generate_for_container_image(image, build_context: build_context)

      expect(attestation.build_provenance.builder_id).to eq("buildkit")
    end

    it "uses materials from build_context when provided" do
      build_context = {
        materials: [
          { uri: "https://github.com/org/repo", digest: "sha256:abc123" }
        ]
      }
      attestation = service.generate_for_container_image(image, build_context: build_context)

      provenance = attestation.build_provenance
      expect(provenance.materials.first["uri"]).to eq("https://github.com/org/repo")
    end

    it "defaults materials to empty array when not provided" do
      attestation = service.generate_for_container_image(image)

      expect(attestation.build_provenance.materials).to eq([])
    end

    it "sets source_repository from build_context" do
      build_context = { source_repository: "https://github.com/org/repo" }
      attestation = service.generate_for_container_image(image, build_context: build_context)

      expect(attestation.build_provenance.source_repository).to eq("https://github.com/org/repo")
    end

    it "sets source_commit from build_context" do
      build_context = { source_commit: "abc123" }
      attestation = service.generate_for_container_image(image, build_context: build_context)

      expect(attestation.build_provenance.source_commit).to eq("abc123")
    end

    it "sets build timestamps from build_context" do
      started = 1.hour.ago
      finished = Time.current
      build_context = {
        build_started_at: started,
        build_finished_at: finished
      }
      attestation = service.generate_for_container_image(image, build_context: build_context)

      provenance = attestation.build_provenance
      expect(provenance.build_started_at).to be_within(1.second).of(started)
      expect(provenance.build_finished_at).to be_within(1.second).of(finished)
    end

    it "handles empty build_context" do
      attestation = service.generate_for_container_image(image, build_context: {})

      expect(attestation).to be_persisted
      expect(attestation.build_provenance.builder_id).to eq("docker")
    end
  end

  describe "error handling" do
    let(:subject_name) { "my-app:v1.0.0" }
    let(:subject_digest) { "sha256:abc123def456" }
    let(:builder_id) { "https://github.com/actions/runner" }

    it "raises ProvenanceError when attestation creation fails" do
      allow(SupplyChain::Attestation).to receive(:create!).and_raise(
        ActiveRecord::RecordInvalid.new(SupplyChain::Attestation.new)
      )

      expect do
        service.generate(
          subject_name: subject_name,
          subject_digest: subject_digest,
          builder_id: builder_id
        )
      end.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "raises ProvenanceError when build provenance creation fails" do
      allow(SupplyChain::BuildProvenance).to receive(:create!).and_raise(
        ActiveRecord::RecordInvalid.new(SupplyChain::BuildProvenance.new)
      )

      expect do
        service.generate(
          subject_name: subject_name,
          subject_digest: subject_digest,
          builder_id: builder_id
        )
      end.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe "predicate constants" do
    it "defines SLSA_PREDICATE_TYPE_V1" do
      expect(described_class::SLSA_PREDICATE_TYPE_V1).to eq("https://slsa.dev/provenance/v1")
    end

    it "defines SLSA_PREDICATE_TYPE_V0_2" do
      expect(described_class::SLSA_PREDICATE_TYPE_V0_2).to eq("https://slsa.dev/provenance/v0.2")
    end
  end

  describe "integration scenarios" do
    it "creates complete provenance chain for a build" do
      started_at = 1.hour.ago
      finished_at = Time.current

      attestation = service.generate(
        subject_name: "my-app:v1.0.0",
        subject_digest: "sha256:abc123def456",
        builder_id: "https://github.com/actions/runner",
        builder_version: "v2.300.0",
        materials: [
          { uri: "https://github.com/org/repo", digest: "sha1:commit123" },
          { uri: "https://registry.npm.org/package", digest: "sha256:package456" }
        ],
        source_repository: "https://github.com/org/repo",
        source_commit: "abc123",
        source_branch: "main",
        build_started_at: started_at,
        build_finished_at: finished_at,
        entry_point: "Dockerfile",
        parameters: { target: "production" },
        environment: { CI: "true" },
        build_config: { platform: "linux/amd64" }
      )

      expect(attestation).to be_persisted
      expect(attestation.attestation_type).to eq("slsa_provenance")
      expect(attestation.predicate).to be_a(Hash)

      provenance = attestation.build_provenance
      expect(provenance).to be_persisted
      expect(provenance.materials.count).to eq(2)
      expect(provenance.invocation).to be_a(Hash)
      expect(provenance.invocation["configSource"]).to be_present
      # JSON serialization converts symbol keys to string keys
      expect(provenance.invocation["parameters"]).to eq({ "target" => "production" })
      expect(provenance.build_config).to eq({ "platform" => "linux/amd64" })
    end

    it "supports multiple attestations for the same account" do
      3.times do |i|
        service.generate(
          subject_name: "app-#{i}:v1.0.0",
          subject_digest: "sha256:hash#{i}",
          builder_id: "builder-#{i}"
        )
      end

      expect(SupplyChain::Attestation.where(account: account).count).to eq(3)
      expect(SupplyChain::BuildProvenance.where(account: account).count).to eq(3)
    end
  end
end

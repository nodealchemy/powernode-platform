# frozen_string_literal: true

require "rails_helper"

RSpec.describe SupplyChain::BuildProvenance, type: :model do
  let(:account) { create(:account) }
  let(:attestation) { create(:supply_chain_attestation, account: account) }

  describe "associations" do
    it { is_expected.to belong_to(:attestation).class_name("SupplyChain::Attestation") }
    it { is_expected.to belong_to(:account) }
  end

  describe "validations" do
    subject { build(:supply_chain_build_provenance, attestation: attestation, account: account) }

    it { is_expected.to validate_presence_of(:builder_id) }

    it "validates uniqueness of attestation_id" do
      create(:supply_chain_build_provenance, attestation: attestation, account: account)
      duplicate = build(:supply_chain_build_provenance, attestation: attestation, account: account)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:attestation_id]).to include("has already been taken")
    end
  end

  describe "scopes" do
    let!(:github_provenance) { create(:supply_chain_build_provenance, attestation: attestation, account: account, builder_id: "https://github.com/actions") }
    let!(:gitlab_provenance) do
      another_attestation = create(:supply_chain_attestation, account: account)
      create(:supply_chain_build_provenance, attestation: another_attestation, account: account, builder_id: "https://gitlab.com/runner")
    end
    let!(:reproducible_provenance) do
      att = create(:supply_chain_attestation, account: account)
      create(:supply_chain_build_provenance, attestation: att, account: account, reproducible: true)
    end
    let!(:verified_reproducible) do
      att = create(:supply_chain_attestation, account: account)
      create(:supply_chain_build_provenance, attestation: att, account: account, reproducible: true, reproducibility_verified_at: Time.current)
    end
    let!(:repo_provenance) do
      att = create(:supply_chain_attestation, account: account)
      create(:supply_chain_build_provenance, attestation: att, account: account, source_repository: "https://github.com/org/repo")
    end
    let!(:commit_provenance) do
      att = create(:supply_chain_attestation, account: account)
      create(:supply_chain_build_provenance, attestation: att, account: account, source_commit: "abc123def456")
    end

    it "filters by builder" do
      expect(described_class.by_builder("https://github.com/actions")).to include(github_provenance)
      expect(described_class.by_builder("https://github.com/actions")).not_to include(gitlab_provenance)
    end

    it "filters reproducible builds" do
      expect(described_class.reproducible).to include(reproducible_provenance, verified_reproducible)
      expect(described_class.reproducible).not_to include(github_provenance)
    end

    it "filters verified reproducible builds" do
      expect(described_class.verified_reproducible).to include(verified_reproducible)
      expect(described_class.verified_reproducible).not_to include(reproducible_provenance)
    end

    it "filters by source repository" do
      expect(described_class.by_source_repo("https://github.com/org/repo")).to include(repo_provenance)
    end

    it "filters by source commit" do
      expect(described_class.by_source_commit("abc123def456")).to include(commit_provenance)
    end
  end

  describe "#reproducible?" do
    it "returns true when reproducible is true" do
      provenance = build(:supply_chain_build_provenance, reproducible: true)
      expect(provenance.reproducible?).to be true
    end

    it "returns false when reproducible is false" do
      provenance = build(:supply_chain_build_provenance, reproducible: false)
      expect(provenance.reproducible?).to be false
    end
  end

  describe "#verified_reproducible?" do
    it "returns true when reproducible and verified" do
      provenance = build(:supply_chain_build_provenance, reproducible: true, reproducibility_verified_at: Time.current)
      expect(provenance.verified_reproducible?).to be true
    end

    it "returns false when reproducible but not verified" do
      provenance = build(:supply_chain_build_provenance, reproducible: true, reproducibility_verified_at: nil)
      expect(provenance.verified_reproducible?).to be false
    end

    it "returns false when not reproducible" do
      provenance = build(:supply_chain_build_provenance, reproducible: false, reproducibility_verified_at: Time.current)
      expect(provenance.verified_reproducible?).to be false
    end
  end

  describe "#build_completed?" do
    it "returns true when build_finished_at is present" do
      provenance = build(:supply_chain_build_provenance, build_finished_at: Time.current)
      expect(provenance.build_completed?).to be true
    end

    it "returns false when build_finished_at is nil" do
      provenance = build(:supply_chain_build_provenance, build_finished_at: nil)
      expect(provenance.build_completed?).to be false
    end
  end

  describe "#build_in_progress?" do
    it "returns true when started but not finished" do
      provenance = build(:supply_chain_build_provenance, build_started_at: Time.current, build_finished_at: nil)
      expect(provenance.build_in_progress?).to be true
    end

    it "returns false when completed" do
      provenance = build(:supply_chain_build_provenance, build_started_at: 1.hour.ago, build_finished_at: Time.current)
      expect(provenance.build_in_progress?).to be false
    end

    it "returns false when not started" do
      provenance = build(:supply_chain_build_provenance, build_started_at: nil, build_finished_at: nil)
      expect(provenance.build_in_progress?).to be false
    end
  end

  describe "#formatted_duration" do
    it "returns nil when no duration" do
      provenance = build(:supply_chain_build_provenance, build_duration_ms: nil)
      expect(provenance.formatted_duration).to be_nil
    end

    it "formats seconds correctly" do
      provenance = build(:supply_chain_build_provenance, build_duration_ms: 45_000)
      expect(provenance.formatted_duration).to eq("45s")
    end

    it "formats minutes and seconds correctly" do
      provenance = build(:supply_chain_build_provenance, build_duration_ms: 125_000)
      expect(provenance.formatted_duration).to eq("2m 5s")
    end

    it "formats hours and minutes correctly" do
      provenance = build(:supply_chain_build_provenance, build_duration_ms: 3_725_000)
      expect(provenance.formatted_duration).to eq("1h 2m")
    end
  end

  describe "#material_count" do
    it "returns the number of materials" do
      provenance = build(:supply_chain_build_provenance, materials: [ { uri: "a" }, { uri: "b" } ])
      expect(provenance.material_count).to eq(2)
    end

    it "returns 0 when materials is nil" do
      provenance = build(:supply_chain_build_provenance, materials: nil)
      expect(provenance.material_count).to eq(0)
    end
  end

  describe "#add_material" do
    let(:provenance) { create(:supply_chain_build_provenance, attestation: attestation, account: account, materials: []) }

    it "adds a material to the list" do
      provenance.add_material(uri: "https://example.com/file.tar.gz", digest: { sha256: "abc123" })
      provenance.reload
      expect(provenance.material_count).to eq(1)
      # JSONB returns string keys after database round-trip
      expect(provenance.materials.first["uri"]).to eq("https://example.com/file.tar.gz")
    end

    it "preserves existing materials" do
      provenance.update!(materials: [ { "uri" => "existing" } ])
      provenance.add_material(uri: "new", digest: { sha256: "def456" })
      provenance.reload
      expect(provenance.material_count).to eq(2)
    end
  end

  describe "#find_material_by_uri" do
    let(:provenance) do
      build(:supply_chain_build_provenance, materials: [
              { "uri" => "https://github.com/org/repo", "digest" => "sha256:abc" },
              { "uri" => "https://registry.npmjs.org/package", "digest" => "sha256:def" }
            ])
    end

    it "finds material by exact URI" do
      material = provenance.find_material_by_uri("https://github.com/org/repo")
      expect(material).to be_present
      expect(material["digest"]).to eq("sha256:abc")
    end

    it "returns nil when not found" do
      expect(provenance.find_material_by_uri("https://not-found.com")).to be_nil
    end
  end

  describe "#source_material" do
    it "returns material matching source_repository" do
      provenance = build(:supply_chain_build_provenance,
                        source_repository: "https://github.com/org/repo",
                        materials: [ { "uri" => "https://github.com/org/repo" } ])
      expect(provenance.source_material).to be_present
    end

    it "falls back to git URI" do
      provenance = build(:supply_chain_build_provenance,
                        source_repository: nil,
                        materials: [ { "uri" => "git+https://github.com/org/repo" } ])
      expect(provenance.source_material).to be_present
    end
  end

  describe "#verify_reproducibility!" do
    let(:provenance) { create(:supply_chain_build_provenance, attestation: attestation, account: account, reproducibility_hash: "expected_hash") }

    it "sets reproducible to true when hashes match" do
      result = provenance.verify_reproducibility!("expected_hash")
      expect(result).to be true
      expect(provenance.reproducible).to be true
      expect(provenance.reproducibility_verified_at).to be_present
    end

    it "sets reproducible to false when hashes don't match" do
      result = provenance.verify_reproducibility!("wrong_hash")
      expect(result).to be false
      expect(provenance.reproducible).to be false
    end
  end

  describe "#to_slsa_predicate" do
    let(:provenance) do
      create(:supply_chain_build_provenance,
             attestation: attestation,
             account: account,
             builder_id: "https://github.com/actions/runner",
             builder_version: "v2.300.0",
             materials: [ { "uri" => "https://github.com/org/repo", "digest" => "sha256:abc" } ],
             invocation: { "parameters" => { "workflow" => "build" } },
             build_started_at: 1.hour.ago,
             build_finished_at: Time.current)
    end

    it "returns SLSA predicate format" do
      predicate = provenance.to_slsa_predicate

      expect(predicate).to include("buildDefinition", "runDetails")
      expect(predicate["buildDefinition"]).to include("buildType", "resolvedDependencies")
      expect(predicate["runDetails"]).to include("builder", "metadata")
      expect(predicate["runDetails"]["builder"]["id"]).to eq("https://github.com/actions/runner")
    end
  end

  describe "#summary" do
    let(:provenance) { create(:supply_chain_build_provenance, attestation: attestation, account: account) }

    it "returns expected keys" do
      summary = provenance.summary

      expect(summary).to include(
        :id,
        :attestation_id,
        :builder_id,
        :builder_version,
        :material_count,
        :source_repository,
        :source_commit,
        :source_branch,
        :reproducible,
        :verified_reproducible,
        :build_started_at,
        :build_finished_at,
        :build_duration_ms,
        :formatted_duration
      )
    end
  end

  describe "callbacks" do
    describe "calculate_duration" do
      it "calculates duration when build times are set" do
        provenance = create(:supply_chain_build_provenance,
                           attestation: attestation,
                           account: account,
                           build_started_at: Time.current - 2.hours,
                           build_finished_at: Time.current)

        expect(provenance.build_duration_ms).to be_within(1000).of(2 * 60 * 60 * 1000)
      end
    end
  end

  describe "JSONB sanitization" do
    it "initializes materials as empty array" do
      provenance = create(:supply_chain_build_provenance, attestation: attestation, account: account, materials: nil)
      expect(provenance.materials).to eq([])
    end

    it "initializes invocation as empty hash" do
      provenance = create(:supply_chain_build_provenance, attestation: attestation, account: account, invocation: nil)
      expect(provenance.invocation).to eq({})
    end

    it "initializes build_config as empty hash" do
      provenance = create(:supply_chain_build_provenance, attestation: attestation, account: account, build_config: nil)
      expect(provenance.build_config).to eq({})
    end

    it "initializes environment as empty hash" do
      provenance = create(:supply_chain_build_provenance, attestation: attestation, account: account, environment: nil)
      expect(provenance.environment).to eq({})
    end

    it "initializes metadata as empty hash" do
      provenance = create(:supply_chain_build_provenance, attestation: attestation, account: account, metadata: nil)
      expect(provenance.metadata).to eq({})
    end
  end
end

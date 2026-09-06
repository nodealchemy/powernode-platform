# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

RSpec.describe Ai::Guidance::GuidanceKnowledgeSeeder do
  let(:account) { create(:account) }
  let(:dir) { Dir.mktmpdir }
  after { FileUtils.remove_entry(dir) if File.exist?(dir) }

  before do
    # Embeddings are best-effort; stub the provider so seeding never makes a real call.
    allow(Ai::Memory::EmbeddingService).to receive(:new)
      .and_return(instance_double(Ai::Memory::EmbeddingService, generate: nil))
    File.write(File.join(dir, "backend-patterns.md"), "# Backend Patterns\n\nUse render_success.\n")
    File.write(File.join(dir, "frontend-patterns.md"), "# Frontend Patterns\n\nTheme classes only.\n")
    File.write(File.join(dir, "MANIFEST.md"), "# Manifest\n\nmeta — must be excluded.\n")
  end

  def seed(private_names: [])
    described_class.new(account: account, dir: dir, private_names: private_names).call
  end

  def entry_for(key)
    Ai::SharedKnowledge.where(account: account).where("provenance->>'guidance_key' = ?", key).first
  end

  it "ingests each conventions doc as account-scoped, tagged shared knowledge" do
    result = seed
    expect(result.created).to eq(2) # MANIFEST excluded
    expect(result.refused).to eq(0)

    entry = entry_for("guidance:backend-patterns")
    expect(entry.title).to eq("Backend Patterns")
    expect(entry.content_type).to eq("reference")
    expect(entry.access_level).to eq("account")
    expect(entry.tags).to include("guidance", "guidance-backend-patterns", "repository:powernode-platform")
    expect(entry.integrity_hash).to be_present
    expect(entry.provenance["source_path"]).to eq("docs/contributing/conventions/backend-patterns.md")
  end

  it "excludes meta docs like MANIFEST" do
    seed
    expect(entry_for("guidance:MANIFEST")).to be_nil
  end

  it "is idempotent — re-seeding unchanged docs creates nothing" do
    seed
    result = seed
    expect(result.created).to eq(0)
    expect(result.unchanged).to eq(2)
    expect(Ai::SharedKnowledge.where(account: account).count).to eq(2)
  end

  it "updates in place when a doc changes, preserving the entry" do
    seed
    original_id = entry_for("guidance:backend-patterns").id
    File.write(File.join(dir, "backend-patterns.md"), "# Backend Patterns\n\nUpdated guidance.\n")

    result = seed

    expect(result.updated).to eq(1)
    expect(result.unchanged).to eq(1)
    entry = entry_for("guidance:backend-patterns")
    expect(entry.id).to eq(original_id)
    expect(entry.content).to include("Updated guidance")
  end

  it "refuses a doc that names a private extension (gate #9), never globalizing it" do
    File.write(File.join(dir, "leaky.md"), "# Leaky\n\nUses Acme::Service from the extension.\n")

    result = seed(private_names: ["acme"])

    expect(result.refused).to eq(1)
    expect(entry_for("guidance:leaky")).to be_nil
  end

  describe ".for_deployment (gitignored docs/operations/local/ → deployment-<slug>)" do
    let(:local_dir) { Dir.mktmpdir }
    after { FileUtils.remove_entry(local_dir) if File.exist?(local_dir) }

    before do
      File.write(File.join(local_dir, "ops-hub.md"), "# Ops hub\n\nhub.example.invalid, VM 4242, hypervisor hv1.\n")
      # Names a private extension: legitimate in local operator notes (the source is
      # gitignored and the entry account-scoped), so gate #9 must NOT refuse it.
      File.write(File.join(local_dir, "audit-sinks.md"), "# Audit sinks\n\nAcme::AuditSink writes to the vault.\n")
    end

    def seed_deployment
      described_class.for_deployment(account: account, dir: local_dir, private_names: ["acme"]).call
    end

    it "tags entries deployment / deployment-<slug>, account-scoped, keyed deployment:<slug>" do
      result = seed_deployment
      expect(result.created).to eq(2)
      expect(result.refused).to eq(0)

      entry = entry_for("deployment:ops-hub")
      expect(entry.title).to eq("Ops hub")
      expect(entry.access_level).to eq("account")
      expect(entry.tags).to include("deployment", "deployment-ops-hub", "repository:powernode-platform")
      expect(entry.tags).not_to include("guidance")
      expect(entry.provenance["source_path"]).to eq("docs/operations/local/ops-hub.md")
      expect(Ai::SharedKnowledge.with_tag("deployment-ops-hub").where(account: account).count).to eq(1)
    end

    it "does not apply gate #9 to deployment-local docs" do
      seed_deployment
      expect(entry_for("deployment:audit-sinks")).to be_present
    end

    it "never collides with a guidance entry of the same slug" do
      File.write(File.join(dir, "ops-hub.md"), "# Ops hub (generic)\n\nHow any hub is run.\n")
      seed
      seed_deployment
      expect(entry_for("guidance:ops-hub").content).to include("generic")
      expect(entry_for("deployment:ops-hub").content).to include("hub.example.invalid")
    end

    it "is idempotent" do
      seed_deployment
      expect(seed_deployment.unchanged).to eq(2)
    end
  end

  describe "against the real docs/contributing/conventions directory" do
    it "seeds fable5-compliance.md as a recallable guidance-fable5-compliance entry" do
      result = described_class.new(account: account).call

      expect(result.refused).to eq(0)

      entry = entry_for("guidance:fable5-compliance")
      expect(entry).to be_present
      expect(entry.title).to eq("Fable 5 Compliance")
      expect(entry.tags).to include("guidance", "guidance-fable5-compliance")
      expect(entry.content_type).to eq("reference")
      expect(entry.content).to include("claude-fable-5")
      expect(entry.content).to include("fable_routing_enabled")
    end
  end
end

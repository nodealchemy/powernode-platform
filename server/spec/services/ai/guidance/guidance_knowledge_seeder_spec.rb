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
end

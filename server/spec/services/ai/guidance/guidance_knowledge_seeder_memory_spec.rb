# frozen_string_literal: true

require "rails_helper"

# .for_memory — the auto-memory variant of the guidance seeder (IMP-e2b3b5f641d9).
RSpec.describe Ai::Guidance::GuidanceKnowledgeSeeder, ".for_memory" do
  include_context "auto memory fixtures"

  let(:account) { create(:account) }
  let(:seeder) { described_class.for_memory(account: account, dir: memory_dir) }

  before do
    write_memory("alpha", name: "Alpha note", description: "The gist", type: "feedback",
                          body: "See [[beta]].", extra_front: "originSessionId: sess-1\n")
    write_memory("beta", type: "project")
  end

  # The per-note primitive is the only seeding path; the migrator gates who reaches it.
  def seed_all(seeder = self.seeder)
    Ai::Guidance::AutoMemoryFile.load_dir(memory_dir).files.map { |file| seeder.seed_memory_file(file) }
  end

  def entry_for(slug)
    Ai::SharedKnowledge.where(account: account).where("provenance->>'guidance_key' = ?", "memory:#{slug}").first
  end

  it "has no bulk #call: seeding without the migrator's triage is refused" do
    expect { seeder.call }.to raise_error(ArgumentError, /AutoMemoryMigrator/)
    expect(Ai::SharedKnowledge.where(account: account).count).to eq(0)
  end

  it "seeds each note account-scoped as a reference entry, never global" do
    expect(seed_all).to eq(%i[created created])

    entry = entry_for("alpha")
    expect(entry.access_level).to eq("account")
    expect(Ai::SharedKnowledge.where(account: account).pluck(:access_level).uniq).to eq(%w[account])
    expect(entry.content_type).to eq("reference")
  end

  it "titles the entry with the frontmatter name and leads the content with the description" do
    seed_all

    entry = entry_for("alpha")
    expect(entry.title).to eq("Alpha note")
    expect(entry.content.lines.first.strip).to eq("The gist")
  end

  it "tags memory, memory-<type> and memory-<slug>" do
    seed_all

    expect(entry_for("alpha").tags).to include("memory", "memory-feedback", "memory-alpha")
    expect(entry_for("alpha").tags).not_to include("guidance")
  end

  it "records the provenance" do
    seed_all

    expect(entry_for("alpha").provenance).to include(
      "guidance_key" => "memory:alpha", "slug" => "alpha", "memory_type" => "feedback",
      "origin_session_id" => "sess-1", "links" => [ "beta" ], "source_path" => "memory/alpha.md"
    )
  end

  it "does not refuse a note that structurally names a private extension (gate #9 off)" do
    write_memory("leaky", body: "Uses Quokkaworks::Service from the extension.")

    outcomes = seed_all

    expect(outcomes).not_to include(:refused)
    expect(entry_for("leaky")).to be_present
  end

  it "reuses the key-anchored upsert_guidance (no second upsert)" do
    allow(seeder).to receive(:upsert_guidance).and_call_original

    seed_all

    expect(seeder).to have_received(:upsert_guidance).with(hash_including(key: "memory:alpha", content_type: "reference")).once
    expect(seeder).to have_received(:upsert_guidance).twice
  end

  it "is idempotent: a re-run updates by guidance_key and never duplicates" do
    seed_all
    id = entry_for("alpha").id
    write_memory("alpha", name: "Alpha note", description: "The gist v2", type: "feedback")

    expect(seed_all(described_class.for_memory(account: account, dir: memory_dir))).to eq(%i[updated unchanged])
    expect(Ai::SharedKnowledge.where(account: account).count).to eq(2)
    expect(entry_for("alpha").id).to eq(id)
  end

  it "skips index, subdirectories and notes without frontmatter" do
    File.write(File.join(memory_dir, "MEMORY.md"), "---\nname: index\n---\nx\n")
    File.write(File.join(memory_dir, "plain.md"), "no frontmatter\n")
    FileUtils.mkdir_p(File.join(memory_dir, "archive"))
    write_memory("old", dir: File.join(memory_dir, "archive"))

    seed_all

    expect(Ai::SharedKnowledge.where(account: account).count).to eq(2)
  end
end

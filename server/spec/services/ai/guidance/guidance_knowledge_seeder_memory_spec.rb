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

  def entry_for(slug)
    Ai::SharedKnowledge.where(account: account).where("provenance->>'guidance_key' = ?", "memory:#{slug}").first
  end

  it "seeds each note account-scoped as a reference entry, never global" do
    result = seeder.call

    expect(result.created).to eq(2)
    entry = entry_for("alpha")
    expect(entry.access_level).to eq("account")
    expect(Ai::SharedKnowledge.where(account: account).pluck(:access_level).uniq).to eq(%w[account])
    expect(entry.content_type).to eq("reference")
  end

  it "titles the entry with the frontmatter name and leads the content with the description" do
    seeder.call

    entry = entry_for("alpha")
    expect(entry.title).to eq("Alpha note")
    expect(entry.content.lines.first.strip).to eq("The gist")
  end

  it "tags memory, memory-<type> and memory-<slug>" do
    seeder.call

    expect(entry_for("alpha").tags).to include("memory", "memory-feedback", "memory-alpha")
    expect(entry_for("alpha").tags).not_to include("guidance")
  end

  it "records the provenance" do
    seeder.call

    expect(entry_for("alpha").provenance).to include(
      "guidance_key" => "memory:alpha", "slug" => "alpha", "memory_type" => "feedback",
      "origin_session_id" => "sess-1", "links" => [ "beta" ], "source_path" => "memory/alpha.md"
    )
  end

  it "does not refuse a note that structurally names a private extension (gate #9 off)" do
    write_memory("leaky", body: "Uses Quokkaworks::Service from the extension.")

    result = described_class.for_memory(account: account, dir: memory_dir).call

    expect(result.refused).to eq(0)
    expect(entry_for("leaky")).to be_present
  end

  it "reuses the key-anchored upsert_guidance (no second upsert)" do
    allow(seeder).to receive(:upsert_guidance).and_call_original

    seeder.call

    expect(seeder).to have_received(:upsert_guidance).with(hash_including(key: "memory:alpha", content_type: "reference")).once
    expect(seeder).to have_received(:upsert_guidance).twice
  end

  it "is idempotent: a re-run updates by guidance_key and never duplicates" do
    seeder.call
    id = entry_for("alpha").id
    write_memory("alpha", name: "Alpha note", description: "The gist v2", type: "feedback")

    result = described_class.for_memory(account: account, dir: memory_dir).call

    expect(result).to have_attributes(created: 0, updated: 1, unchanged: 1)
    expect(Ai::SharedKnowledge.where(account: account).count).to eq(2)
    expect(entry_for("alpha").id).to eq(id)
  end

  it "skips index, subdirectories and notes without frontmatter" do
    File.write(File.join(memory_dir, "MEMORY.md"), "---\nname: index\n---\nx\n")
    File.write(File.join(memory_dir, "plain.md"), "no frontmatter\n")
    FileUtils.mkdir_p(File.join(memory_dir, "archive"))
    write_memory("old", dir: File.join(memory_dir, "archive"))

    seeder.call

    expect(Ai::SharedKnowledge.where(account: account).count).to eq(2)
  end
end

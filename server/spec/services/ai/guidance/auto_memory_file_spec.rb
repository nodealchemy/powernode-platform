# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Guidance::AutoMemoryFile do
  include_context "auto memory fixtures"

  it "parses name, description, type, session id and body from the frontmatter" do
    write_memory("alpha", body: "Some body.", name: "Alpha note", description: "The gist",
                          type: "feedback", extra_front: "originSessionId: sess-1\n")

    file = described_class.load_dir(memory_dir).files.first

    expect(file.slug).to eq("alpha")
    expect(file.title).to eq("Alpha note")
    expect(file.description).to eq("The gist")
    expect(file.memory_type).to eq("feedback")
    expect(file.origin_session_id).to eq("sess-1")
    expect(file.content).to eq("The gist\n\nSome body.")
    expect(file.content.lines.first.strip).to eq("The gist")
  end

  it "falls back to the slug for a nameless note and reads a top-level type" do
    File.write(File.join(memory_dir, "no-name.md"), "---\ndescription: d\ntype: user\n---\nbody\n")

    file = described_class.load_dir(memory_dir).files.first

    expect(file.title).to eq("no name")
    expect(file.memory_type).to eq("user")
  end

  it "collects [[slug]] links in order, deduplicated, never the note itself" do
    write_memory("alpha", body: "See [[beta]] and [[gamma|alias]] and [[beta]] and [[alpha]].")

    expect(described_class.load_dir(memory_dir).files.first.links).to eq(%w[beta gamma])
  end

  describe ".load_dir skip rules" do
    it "skips MEMORY.md, every subdirectory and notes without frontmatter (reported by slug)" do
      write_memory("kept")
      File.write(File.join(memory_dir, "MEMORY.md"), "---\nname: index\n---\n- [x](x.md)\n")
      File.write(File.join(memory_dir, "plain.md"), "# No frontmatter here\n")
      File.write(File.join(memory_dir, "broken.md"), "---\nname: [unterminated\n---\nbody\n")
      %w[archive apo-sprint-staging archive-2026-09-19].each do |sub|
        FileUtils.mkdir_p(File.join(memory_dir, sub))
        write_memory("hidden-#{sub}", dir: File.join(memory_dir, sub))
      end

      loaded = described_class.load_dir(memory_dir)

      expect(loaded.files.map(&:slug)).to eq(%w[kept])
      expect(loaded.without_frontmatter).to contain_exactly("plain", "broken")
    end

    it "returns nothing for a missing directory" do
      loaded = described_class.load_dir(File.join(memory_dir, "absent"))

      expect(loaded.files).to be_empty
    end
  end
end

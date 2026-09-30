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

  it "keeps a note whose frontmatter has an unquoted YAML date" do
    File.write(File.join(memory_dir, "dated.md"), "---\nname: Dated\ndescription: d\ncreated: 2026-09-30\n---\nbody\n")

    expect(described_class.load_dir(memory_dir).files.map(&:slug)).to eq(%w[dated])
  end

  it "still refuses arbitrary YAML objects" do
    File.write(File.join(memory_dir, "evil.md"), "---\nname: !ruby/object:OpenStruct {}\n---\nbody\n")

    loaded = described_class.load_dir(memory_dir)

    expect(loaded.files).to be_empty
    expect(loaded.without_frontmatter).to eq(%w[evil])
  end

  it "reports a non-UTF-8 note instead of aborting the run" do
    write_memory("fine")
    File.binwrite(File.join(memory_dir, "binary.md"), "---\nname: x\n---\n\xff\xfe\n".b)

    loaded = described_class.load_dir(memory_dir)

    expect(loaded.files.map(&:slug)).to eq(%w[fine])
    expect(loaded.without_frontmatter).to eq(%w[binary])
  end

  describe ".load_dir skip rules" do
    it "does not follow symlinks (to an archived or outside file) and reports them" do
      FileUtils.mkdir_p(File.join(memory_dir, "archive"))
      write_memory("old", dir: File.join(memory_dir, "archive"))
      write_memory("outside", dir: scratch_dir)
      File.symlink(File.join(memory_dir, "archive", "old.md"), File.join(memory_dir, "linked-archive.md"))
      File.symlink(File.join(scratch_dir, "outside.md"), File.join(memory_dir, "linked-outside.md"))
      write_memory("kept")

      loaded = described_class.load_dir(memory_dir)

      expect(loaded.files.map(&:slug)).to eq(%w[kept])
      expect(loaded.symlinks).to contain_exactly("linked-archive.md", "linked-outside.md")
    end

    it "treats glob metacharacters in the directory path literally" do
      odd = File.join(scratch_dir, "we[ir]d{dir}")
      FileUtils.mkdir_p(odd)
      write_memory("inside", dir: odd)

      expect(described_class.load_dir(odd).files.map(&:slug)).to eq(%w[inside])
    end

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

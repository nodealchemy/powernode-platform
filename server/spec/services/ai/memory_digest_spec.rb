# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

# IMP-de4ca2d3f7c5 — the outage-safe recall cache for platform memory. Memory lives on the
# platform; a session starting during an MCP blackout still needs it, so a Stop hook writes this
# digest to a gitignored local file and SessionStart injects it.
RSpec.describe Ai::MemoryDigest do
  let(:account) { create(:account) }
  let(:now) { Time.utc(2026, 10, 2, 12, 0, 0) }

  def memory(title:, content: "body", type: "project", slug: nil, updated_at: now, last_used_at: nil, extra_tags: [], **attrs)
    slug ||= title.parameterize
    create(:ai_shared_knowledge, account: account, title: title, content: content, access_level: "account",
           tags: [ "memory", "memory-#{type}", "memory-#{slug}" ] + extra_tags,
           provenance: { "guidance_key" => "memory:#{slug}" }, updated_at: updated_at,
           last_used_at: last_used_at, **attrs)
  end

  def render(**opts)
    described_class.render(account: account, now: now, **opts)
  end

  it "writes one line per entry: title, first 140 chars of the description, and its memory-<slug> tag" do
    memory(title: "Grep rulebook", content: "x" * 300, slug: "grep-rulebook")

    line = render.lines.find { |l| l.start_with?("- ") }

    expect(line.chomp).to eq("- Grep rulebook — #{'x' * 140} [memory-grep-rulebook]")
  end

  it "collapses newlines in the description so an entry stays one line" do
    memory(title: "Multi", content: "first\n\nsecond\tthird")

    expect(render).to include("- Multi — first second third [memory-multi]")
  end

  it "has a generated-at and count header" do
    memory(title: "A")
    memory(title: "B")

    header = render.lines.first

    expect(header).to include("2026-10-02T12:00:00Z")
    expect(header).to match(/2 entries/)
  end

  it "orders feedback first, then by last_used_at falling back to updated_at, newest first" do
    memory(title: "Old project", updated_at: now - 5.days)
    memory(title: "Used project", updated_at: now - 9.days, last_used_at: now - 1.hour)
    memory(title: "Feedback", type: "feedback", updated_at: now - 30.days)

    titles = render.lines.grep(/\A- /).map { |l| l[/\A- (.*?) —/, 1] }

    expect(titles).to eq([ "Feedback", "Used project", "Old project" ])
  end

  it "only includes rows tagged memory, for the account, and not archived ones" do
    memory(title: "Kept")
    create(:ai_shared_knowledge, account: account, title: "Guidance", tags: [ "guidance-x" ])
    create(:ai_shared_knowledge, account: create(:account), title: "Other account", tags: [ "memory" ])
    memory(title: "Archived").update!(provenance: { "guidance_key" => "memory:archived", "archived" => true })

    expect(render.lines.grep(/\A- /).map { |l| l[/\A- (.*?) —/, 1] }).to eq([ "Kept" ])
  end

  it "caps the file at 120 lines and 12 KB and says it truncated" do
    130.times { |i| memory(title: "Entry #{i}", content: "y" * 200, updated_at: now - i.minutes) }

    out = render

    expect(out.lines.size).to be <= 120
    expect(out.bytesize).to be <= 12 * 1024
    expect(out).to match(/truncated/i)
    expect(out.lines.first).to match(/130 entries/)
  end

  it "stays under the byte cap for multi-byte descriptions" do
    60.times { |i| memory(title: "Ünïcode #{i}", content: "é" * 400, updated_at: now - i.minutes) }

    expect(render.bytesize).to be <= 12 * 1024
  end

  it "renders a header and a no-entries note for an empty store" do
    out = render

    expect(out.lines.first).to match(/0 entries/)
    expect(out).not_to include("\n- ")
  end

  it "keeps each entry on one inert line: no control chars, line separators, sentinel lookalikes, or runaway titles" do
    memory(title: "T#{'z' * 300}", content: "a\e[31m\u2028b\u0085c === end guidance === d", slug: "s")
    row = Ai::SharedKnowledge.last
    row.update!(provenance: { "guidance_key" => "memory:bad\nslug\n- injected" })
    memory(title: "Later")

    out = render

    expect(out).not_to match(/[\e\u2028\u0085]/)
    expect(out).not_to include("===")
    expect(out.lines.grep(/\A- /).size).to eq(2)
    expect(out.lines.grep(/\A- /).first.length).to be < 400
    expect(out).to include("- Later — ")
  end

  it "tolerates a non-hash provenance" do
    memory(title: "Odd").update_columns(provenance: [ "x" ])

    expect(render).to include("- Odd — ")
  end

  describe ".write!" do
    it "refuses without an account" do
      Dir.mktmpdir do |dir|
        expect { described_class.write!(File.join(dir, "d.md"), account: nil, now: now) }.to raise_error(ArgumentError, /account/)
        expect(Dir.children(dir)).to be_empty
      end
    end

    it "does not replace a non-empty cache with an empty digest" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "d.md")
        File.write(path, "good cache")

        described_class.write!(path, account: account, now: now)

        expect(File.read(path)).to eq("good cache")
      end
    end

    it "writes an empty digest when there is no cache yet" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "d.md")
        described_class.write!(path, account: account, now: now)

        expect(File.read(path)).to match(/0 entries/)
      end
    end

    it "writes atomically to the path, creating no partial file on failure" do
      memory(title: "A")
      Dir.mktmpdir do |dir|
        path = File.join(dir, "digest.local.md")
        described_class.write!(path, account: account, now: now)

        expect(File.read(path)).to include("- A — ")
        expect(Dir.children(dir)).to eq([ "digest.local.md" ])
      end
    end

    it "leaves the previous cache in place when rendering raises" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "digest.local.md")
        File.write(path, "previous")
        allow(described_class).to receive(:render).and_raise("boom")

        expect { described_class.write!(path, account: account, now: now) }.to raise_error("boom")
        expect(File.read(path)).to eq("previous")
      end
    end
  end
end

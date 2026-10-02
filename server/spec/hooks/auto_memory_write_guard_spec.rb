# frozen_string_literal: true

require "spec_helper"
require "json"
require "open3"
require "tmpdir"
require "fileutils"

# IMP-c4f263d08b3a — memory lives on the platform, but a memory write is a plain Write/Edit
# call, so "never write local memory" needs a harness-level guard. This PreToolUse hook exits 2
# when the target is under the auto-memory directory (~/.claude/projects/*/memory/) and is not
# that directory's MEMORY.md pointer. Shell-level spec, no Rails.
RSpec.describe ".claude/hooks/auto-memory-write-guard.sh" do
  let(:repo_root) { File.expand_path("../../..", __dir__) }
  let(:hook) { File.join(repo_root, ".claude", "hooks", "auto-memory-write-guard.sh") }
  let(:home) { Dir.mktmpdir("guard-home") }
  let(:memory_dir) { File.join(home, ".claude", "projects", "-work-proj", "memory") }

  before { FileUtils.mkdir_p(memory_dir) }
  after { FileUtils.remove_entry(home) if File.exist?(home) }

  def run_hook(payload, env: {})
    stdin = payload.is_a?(String) ? payload : payload.to_json
    Open3.capture3({ "HOME" => home, "CLAUDE_CONFIG_DIR" => nil }.merge(env), "bash", hook, stdin_data: stdin)
  end

  def call(tool, key, path, **extra)
    run_hook({ tool_name: tool, tool_input: { key => path }, **extra })
  end

  def blocked?(result)
    result[2].exitstatus == 2
  end

  describe "what it blocks" do
    %w[Write Edit MultiEdit].each do |tool|
      it "blocks a #{tool} of a new memory file, telling the writer to use the platform" do
        out, err, status = call(tool, :file_path, File.join(memory_dir, "feedback-new.md"))

        expect(status.exitstatus).to eq(2)
        expect(out).to eq("")
        expect(err).to include("create_knowledge")
        expect(err).to include("memory-<type>")
        expect(err).to include("memory-<slug>")
        expect(err).to include("access_level account")
        expect(err).to include('"memory:<slug>"')
      end
    end

    it "blocks the filesystem MCP write_file and edit_file, which carry the target in .tool_input.path" do
      expect(blocked?(call("mcp__filesystem__write_file", :path, File.join(memory_dir, "a.md")))).to be true
      expect(blocked?(call("mcp__filesystem__edit_file", :path, File.join(memory_dir, "a.md")))).to be true
    end

    it "blocks an edit of an EXISTING memory file too" do
      path = File.join(memory_dir, "old.md")
      File.write(path, "x")

      expect(blocked?(call("Edit", :file_path, path))).to be true
    end

    it "blocks every project's memory directory, and nested paths under it" do
      other = File.join(home, ".claude", "projects", "-other", "memory", "sub", "deep.md")

      expect(blocked?(call("Write", :file_path, other))).to be true
    end

    it "blocks a ~/ path and a path that climbs back into the directory with .." do
      expect(blocked?(call("Write", :file_path, "~/.claude/projects/-work-proj/memory/t.md"))).to be true
      expect(blocked?(call("Write", :file_path, File.join(home, "elsewhere", "..", ".claude", "projects", "p", "memory", "t.md")))).to be true
    end

    it "blocks a relative path resolved against the session's cwd" do
      expect(blocked?(call("Write", :file_path, "t.md", cwd: memory_dir))).to be true
    end

    it "blocks a write through a symlink that points into the memory directory" do
      link = File.join(home, "shortcut")
      File.symlink(memory_dir, link)

      expect(blocked?(call("Write", :file_path, File.join(link, "t.md")))).to be true
    end

    it "blocks a MEMORY.md that is NOT the directory's own pointer (nested)" do
      expect(blocked?(call("Write", :file_path, File.join(memory_dir, "archive", "MEMORY.md")))).to be true
    end

    it "honours CLAUDE_CONFIG_DIR as the config root" do
      cfg = Dir.mktmpdir("guard-cfg")
      target = File.join(cfg, "projects", "-p", "memory", "t.md")

      expect(blocked?(run_hook({ tool_name: "Write", tool_input: { file_path: target } }, env: { "CLAUDE_CONFIG_DIR" => cfg }))).to be true
    ensure
      FileUtils.remove_entry(cfg) if cfg
    end
  end

  describe "what it lets through (exit 0, silent)" do
    def allowed?(result)
      expect(result[2].exitstatus).to eq(0)
      expect(result[1]).to eq("")
      true
    end

    it "the MEMORY.md pointer itself" do
      expect(allowed?(call("Edit", :file_path, File.join(memory_dir, "MEMORY.md")))).to be true
    end

    it "a file in the project, in another .claude directory, or in a sibling 'memory-*' directory" do
      expect(allowed?(call("Write", :file_path, File.join(repo_root, "docs", "x.md")))).to be true
      expect(allowed?(call("Write", :file_path, File.join(home, ".claude", "settings.json")))).to be true
      expect(allowed?(call("Write", :file_path, File.join(home, ".claude", "projects", "-p", "memory-notes", "a.md")))).to be true
      expect(allowed?(call("Write", :file_path, File.join(home, "memory", "a.md")))).to be true
    end

    it "a tool without a path, malformed JSON, empty input, and a non-string path" do
      expect(allowed?(run_hook({ tool_name: "Write", tool_input: {} }))).to be true
      expect(allowed?(run_hook("{not json"))).to be true
      expect(allowed?(run_hook(""))).to be true
      expect(allowed?(run_hook({ tool_name: "Write", tool_input: { file_path: [ 1 ] } }))).to be true
    end
  end

  it "is wired as a PreToolUse hook on every writing tool, with a short timeout" do
    settings = JSON.parse(File.read(File.join(repo_root, ".claude", "settings.json")))
    group = settings.dig("hooks", "PreToolUse").to_a.find do |g|
      g["hooks"].to_a.any? { |h| h["command"].include?("auto-memory-write-guard.sh") }
    end

    expect(group).to be_truthy
    matchers = group["matcher"].split("|")
    expect(matchers).to include("Write", "Edit", "MultiEdit", "mcp__filesystem__write_file", "mcp__filesystem__edit_file")
    expect(group["hooks"].find { |h| h["command"].include?("auto-memory-write-guard.sh") }["timeout"]).to be <= 5
  end

  it "does not disable auto memory (the operator keeps MEMORY.md loaded as a pointer)" do
    settings = JSON.parse(File.read(File.join(repo_root, ".claude", "settings.json")))

    expect(settings).not_to have_key("autoMemoryEnabled")
    expect(settings["env"].to_h).not_to have_key("CLAUDE_CODE_DISABLE_AUTO_MEMORY")
  end
end

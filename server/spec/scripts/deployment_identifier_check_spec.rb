# frozen_string_literal: true

require "spec_helper"
require "open3"
require "json"
require "tmpdir"
require "fileutils"

# Deployment-local identifiers (this deployment's hostnames, internal IP ranges,
# VM ids, operator details) must never ship in a git-tracked file — their home is
# the deployment's own platform knowledge (tag deployment-*). Two enforcement
# paths share ONE implementation:
#   * scripts/checks/deployment-identifier-check.sh   (model-agnostic scan; tree
#     mode is wired into scripts/pattern-validation.sh as security-critical)
#   * .claude/hooks/deployment-identifier-check.sh    (blocking edit-time hook,
#     calls the scan in --file mode)
#
# The identifier patterns live in a GITIGNORED per-deployment list, because a
# guard against name leakage must not itself contain the names. So the fixture
# below invents its own identifiers (hub.example.invalid, 198.51.100.0/24) and
# its own list; it never names this repo's real ones.
RSpec.describe "deployment-identifier leak guard" do
  repo_root = File.expand_path("../../..", __dir__) # server/spec/scripts -> repo root
  let(:scan) { File.join(repo_root, "scripts/checks/deployment-identifier-check.sh") }
  let(:hook) { File.join(repo_root, ".claude/hooks/deployment-identifier-check.sh") }

  # A miniature project: a core repo with a tracked doc, a tracked clean doc and a
  # gitignored local doc; a PUBLIC extension as its own nested git repo; a PRIVATE
  # extension as its own nested git repo under extensions/private/ (which the core
  # .gitignore ignores, as in the real tree).
  def build_tree(dir, with_list: true)
    root = File.realpath(dir)
    write = lambda do |rel, body|
      path = File.join(root, rel)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, body)
      path
    end
    git = lambda do |where, *args|
      out, status = Open3.capture2e("git", "-C", where, *args)
      raise "git #{args.join(' ')} failed in #{where}: #{out}" unless status.success?
      out
    end
    init = lambda do |where|
      git.call(where, "init", "-q")
      git.call(where, "config", "user.email", "spec@example.invalid")
      git.call(where, "config", "user.name", "spec")
    end

    write.call(".gitignore", "/extensions/private/\n/docs/operations/local/\n/CLAUDE.local.md\n/.claude/hooks/deployment-identifiers.local.txt\n")
    write.call("docs/operations/leaky.md", "The hub is hub.example.invalid on 198.51.100.7.\n")
    write.call("docs/operations/clean.md", "The hub is <hub-host> on an RFC 5737 address.\n")
    write.call("docs/operations/local/notes.md", "hub.example.invalid — allowed here, gitignored.\n")
    write.call("CLAUDE.local.md", "hub.example.invalid — allowed here, untracked.\n")
    init.call(root)
    git.call(root, "add", "-A")
    git.call(root, "commit", "-qm", "core")

    ext = write.call("extensions/beta/docs/runbook.md", "reprovision hub.example.invalid\n")
    write.call("extensions/beta/docs/clean.md", "reprovision <hub-host>\n")
    write.call("extensions/beta/.gitignore", "/scratch/\n")
    write.call("extensions/beta/scratch/local.md", "198.51.100.9 lives here, ignored by the extension\n")
    init.call(File.dirname(File.dirname(ext)))
    git.call(File.join(root, "extensions/beta"), "add", "-A")
    git.call(File.join(root, "extensions/beta"), "commit", "-qm", "beta")

    priv = write.call("extensions/private/alpha/docs/ops.md", "hub.example.invalid is fine in a private extension\n")
    init.call(File.dirname(File.dirname(priv)))
    git.call(File.join(root, "extensions/private/alpha"), "add", "-A")
    git.call(File.join(root, "extensions/private/alpha"), "commit", "-qm", "alpha")

    if with_list
      write.call(".claude/hooks/deployment-identifiers.local.txt",
                 "# fixture list\nhub\\.example\\.invalid\n\n198\\.51\\.100\\.[0-9]+   # trailing comment\n")
    end
    root
  end

  def run_scan(root, *args, list: nil)
    env = { "DEPLOYMENT_ID_ROOT" => root }
    env["DEPLOYMENT_ID_LIST"] = list if list
    out, err, status = Open3.capture3(env, "bash", scan, *args)
    [out, err, status.exitstatus]
  end

  around do |example|
    Dir.mktmpdir("deployment-id-guard") { |dir| @root = build_tree(dir, with_list: example.metadata.fetch(:with_list, true)); example.run }
  end

  describe "tree mode (scripts/pattern-validation.sh mirror)" do
    it "counts every TRACKED file in core and in each PUBLIC extension that names an identifier" do
      out, _err, rc = run_scan(@root)
      expect(rc).to eq(0)
      expect(out.strip).to eq("2") # docs/operations/leaky.md + extensions/beta/docs/runbook.md
    end

    it "lists hits as <repo-relative-path>:<line>:<text>, never a gitignored or private file" do
      out, _err, _rc = run_scan(@root, "--list")
      paths = out.lines.map { |l| l.split(":", 2).first }
      expect(paths).to contain_exactly("docs/operations/leaky.md", "extensions/beta/docs/runbook.md")
      expect(out).to include("docs/operations/leaky.md:1:The hub is hub.example.invalid")
      expect(out).not_to include("docs/operations/local/")
      expect(out).not_to include("CLAUDE.local.md")
      expect(out).not_to include("extensions/private/")
      expect(out).not_to include("scratch/local.md")
      expect(out).not_to include("clean.md")
    end

    it "is a no-op PASS (0, nothing listed) when the deployment has no identifier list", with_list: false do
      out, _err, rc = run_scan(@root)
      expect([out.strip, rc]).to eq(["0", 0])
      out, = run_scan(@root, "--list")
      expect(out).to eq("")
    end

    it "ignores comment lines and blank lines in the list, and treats each line as one regex" do
      list = File.join(@root, "only-ip.txt")
      File.write(list, "# only the address range\n\n198\\.51\\.100\\.[0-9]+\n")
      out, = run_scan(@root, "--list", list: list)
      expect(out.lines.size).to eq(1)
      expect(out).to include("docs/operations/leaky.md:1:")
    end
  end

  describe "--file mode (the edit-time hook's entry point)" do
    it "exits 2 and prints the offending lines for a tracked file that names an identifier" do
      out, _err, rc = run_scan(@root, "--file", File.join(@root, "docs/operations/leaky.md"))
      expect(rc).to eq(2)
      expect(out).to include("1:The hub is hub.example.invalid")
    end

    it "exits 0 for a clean tracked file" do
      _out, _err, rc = run_scan(@root, "--file", File.join(@root, "docs/operations/clean.md"))
      expect(rc).to eq(0)
    end

    it "exits 0 for a gitignored file — resolved in the file's OWN repo for a submodule path" do
      _out, _err, rc = run_scan(@root, "--file", File.join(@root, "docs/operations/local/notes.md"))
      expect(rc).to eq(0)
      _out, _err, rc = run_scan(@root, "--file", File.join(@root, "extensions/beta/scratch/local.md"))
      expect(rc).to eq(0)
    end

    it "flags a tracked file inside a public extension" do
      _out, _err, rc = run_scan(@root, "--file", File.join(@root, "extensions/beta/docs/runbook.md"))
      expect(rc).to eq(2)
    end

    it "never flags the identifier list itself, and exits 0 with no list", with_list: false do
      list = File.join(@root, ".claude/hooks/deployment-identifiers.local.txt")
      FileUtils.mkdir_p(File.dirname(list))
      File.write(list, "hub\\.example\\.invalid\n")
      _out, _err, rc = run_scan(@root, "--file", list)
      expect(rc).to eq(0)
      File.delete(list)
      _out, _err, rc = run_scan(@root, "--file", File.join(@root, "docs/operations/leaky.md"))
      expect(rc).to eq(0)
    end
  end

  describe ".claude/hooks/deployment-identifier-check.sh (blocking hook)" do
    def run_hook(project_dir, file)
      payload = JSON.generate("tool_input" => { "file_path" => file })
      # The hook resolves the scan script relative to CLAUDE_PROJECT_DIR, so the
      # fixture project needs a copy of it at the same relative path.
      FileUtils.mkdir_p(File.join(project_dir, "scripts/checks"))
      FileUtils.cp(scan, File.join(project_dir, "scripts/checks/deployment-identifier-check.sh"))
      out, err, status = Open3.capture3({ "CLAUDE_PROJECT_DIR" => project_dir }, "bash", hook, stdin_data: payload)
      [out, err, status.exitstatus]
    end

    it "blocks (exit 2) with a pointer to the convention when a tracked file names an identifier" do
      _out, err, rc = run_hook(@root, File.join(@root, "docs/operations/leaky.md"))
      expect(rc).to eq(2)
      expect(err).to include("BLOCKED (deployment-identifier leak)")
      expect(err).to include("hub.example.invalid")
      expect(err).to include("deployment-knowledge.md")
      expect(err).to include("search_knowledge").or include("create_knowledge")
    end

    it "passes a clean file, a gitignored file, a private-extension file, and an out-of-repo file" do
      expect(run_hook(@root, File.join(@root, "docs/operations/clean.md")).last).to eq(0)
      expect(run_hook(@root, File.join(@root, "docs/operations/local/notes.md")).last).to eq(0)
      expect(run_hook(@root, File.join(@root, "extensions/private/alpha/docs/ops.md")).last).to eq(0)
      Dir.mktmpdir("elsewhere") do |other|
        stray = File.join(other, "note.md")
        File.write(stray, "hub.example.invalid\n")
        expect(run_hook(@root, stray).last).to eq(0)
      end
    end

    it "passes when the deployment has no identifier list (nothing to guard)", with_list: false do
      expect(run_hook(@root, File.join(@root, "docs/operations/leaky.md")).last).to eq(0)
    end
  end

  describe "wiring" do
    it "is registered as a PostToolUse Edit|Write hook in .claude/settings.json" do
      settings = JSON.parse(File.read(File.join(repo_root, ".claude/settings.json")))
      commands = settings.dig("hooks", "PostToolUse").flat_map { |e| e["hooks"].map { |h| h["command"] } }
      expect(commands).to include(a_string_including("deployment-identifier-check.sh"))
    end

    it "runs in scripts/pattern-validation.sh as a security-critical check" do
      pv = File.read(File.join(repo_root, "scripts/pattern-validation.sh"))
      expect(pv).to include("scripts/checks/deployment-identifier-check.sh")
      expect(pv).to include('security_critical_failed_checks+=("No deployment-local identifiers in tracked files (leak guard)")')
    end

    it "keeps the identifier list and the local docs directory gitignored" do
      %w[.claude/hooks/deployment-identifiers.local.txt docs/operations/local/x.md].each do |rel|
        out, status = Open3.capture2("git", "-C", repo_root, "check-ignore", "-q", rel)
        expect(status.success?).to be(true), "#{rel} is not gitignored: #{out}"
      end
    end

    it "carries the guard in the convention doc that the guidance seeder ingests" do
      doc = File.read(File.join(repo_root, "docs/contributing/conventions/deployment-knowledge.md"))
      expect(doc).to include("deployment-identifier-check.sh")
      expect(doc).to include("deployment-identifiers.local.txt")
      expect(doc).to include("search_knowledge tag:deployment-")
    end
  end
end

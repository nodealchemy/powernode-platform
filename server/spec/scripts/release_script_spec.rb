# frozen_string_literal: true

require "spec_helper"
require "open3"
require "tmpdir"
require "json"
require "fileutils"

# scripts/release.sh X.Y.Z -- running it IS the release. These examples drive the
# real script against a throwaway parent repo that has a package.json, a
# frontend/package.json and one submodule carrying a gemspec, with bare local
# "remotes" so the push is real too. The platform's own repo is never touched.
RSpec.describe "scripts/release.sh" do
  let(:script) { File.expand_path("../../../scripts/release.sh", __dir__) }
  let(:git_env) do
    { "GIT_AUTHOR_NAME" => "T", "GIT_AUTHOR_EMAIL" => "t@example.invalid",
      "GIT_COMMITTER_NAME" => "T", "GIT_COMMITTER_EMAIL" => "t@example.invalid",
      "GIT_CONFIG_COUNT" => "1", "GIT_CONFIG_KEY_0" => "protocol.file.allow", "GIT_CONFIG_VALUE_0" => "always" }
  end

  def sh!(*cmd, chdir:)
    out, err, st = Open3.capture3(git_env, *cmd, chdir: chdir)
    raise "#{cmd.join(' ')} failed: #{out}#{err}" unless st.success?

    out.strip
  end

  def git(dir, *args) = sh!("git", *args, chdir: dir)

  def release(*args, chdir: @parent)
    out, err, st = Open3.capture3(git_env, "bash", script, *args, chdir: chdir)
    [ st, out + err ]
  end

  # parent (with package.json x2 + submodule extensions/ext) and ext, each with
  # a bare origin, tag 0.2.0 on master, develop and release/0.3.0 branches.
  before do
    @root = Dir.mktmpdir("release-spec")
    ext_origin = File.join(@root, "ext.git")
    par_origin = File.join(@root, "parent.git")
    ext = File.join(@root, "ext")
    @parent = File.join(@root, "parent")
    [ ext_origin, par_origin ].each { |d| sh!("git", "init", "-q", "--bare", "-b", "master", d, chdir: @root) }

    FileUtils.mkdir_p(File.join(ext, "server"))
    sh!("git", "init", "-q", "-b", "master", ext, chdir: @root)
    File.write(File.join(ext, "server/ext.gemspec"), <<~RUBY)
      Gem::Specification.new do |spec|
        spec.name        = "ext"
        # Bundler requires a literal. scripts/release.sh is the ONLY writer of this value
        spec.version     = "0.1.0"
      end
    RUBY
    git(ext, "add", "-A"); git(ext, "commit", "-q", "-m", "init ext")
    git(ext, "remote", "add", "origin", ext_origin)
    git(ext, "push", "-q", "origin", "master")

    sh!("git", "init", "-q", "-b", "master", @parent, chdir: @root)
    FileUtils.mkdir_p(File.join(@parent, "frontend"))
    File.write(File.join(@parent, "package.json"), JSON.pretty_generate(name: "root", version: "0.2.0", lockfileVersion: 3) + "\n")
    File.write(File.join(@parent, "package-lock.json"), JSON.pretty_generate(name: "root", version: "0.2.0", lockfileVersion: 3, requires: true, packages: { "" => { name: "root", version: "0.2.0" } }) + "\n")
    File.write(File.join(@parent, "frontend/package.json"), JSON.pretty_generate(name: "fe", version: "0.2.0") + "\n")
    File.write(File.join(@parent, "frontend/package-lock.json"), JSON.pretty_generate(name: "fe", version: "0.2.0", lockfileVersion: 3, requires: true, packages: { "" => { name: "fe", version: "0.2.0" } }) + "\n")
    git(@parent, "add", "-A"); git(@parent, "commit", "-q", "-m", "init")
    git(@parent, "submodule", "add", "-q", ext_origin, "extensions/ext")
    git(@parent, "commit", "-q", "-m", "add ext")
    git(@parent, "remote", "add", "origin", par_origin)
    @par_gitea = File.join(@root, "parent-gitea.git")
    sh!("git", "init", "-q", "--bare", "-b", "master", @par_gitea, chdir: @root)
    git(@parent, "remote", "add", "gitea", @par_gitea)
    git(@parent, "tag", "0.2.0")
    git(@parent, "branch", "develop")
    [ "origin", "gitea" ].each { |r| git(@parent, "push", "-q", r, "master", "develop", "--tags") }
    @par_origin = par_origin

    sub = File.join(@parent, "extensions/ext")
    git(sub, "checkout", "-q", "-b", "develop")
    git(sub, "push", "-q", "origin", "develop")
    [ @parent, sub ].each { |d| git(d, "checkout", "-q", "-b", "release/0.3.0", "develop") }
  end

  after { FileUtils.remove_entry(@root) }

  def gemspec_version(dir)
    File.read(File.join(dir, "extensions/ext/server/ext.gemspec"))[/spec.version\s*=\s*"([^"]+)"/, 1]
  end

  it "rejects a missing or v-prefixed version" do
    st, out = release
    expect(st).not_to be_success
    expect(out).to match(/usage/i)
    st, out = release("v0.3.0")
    expect(st).not_to be_success
    expect(out).to match(/X\.Y\.Z/)
  end

  it "refuses a dirty tree" do
    File.write(File.join(@parent, "stray.txt"), "x")
    st, out = release("0.3.0")
    expect(st).not_to be_success
    expect(out).to match(/not clean|dirty/i)
  end

  it "refuses to run off release/X.Y.Z" do
    git(@parent, "checkout", "-q", "develop")
    st, out = release("0.3.0")
    expect(st).not_to be_success
    expect(out).to match(%r{release/0\.3\.0})
  end

  it "refuses when the tag already exists in a submodule" do
    git(File.join(@parent, "extensions/ext"), "tag", "0.3.0")
    st, out = release("0.3.0")
    expect(st).not_to be_success
    expect(out).to match(/tag 0\.3\.0 already exists/i)
  end

  it "dies when a registered submodule is not initialised (no partial release)" do
    git(@parent, "submodule", "deinit", "-q", "-f", "extensions/ext")
    st, out = release("0.3.0", "--dry-run")
    expect(st).not_to be_success
    expect(out).to match(/submodule.*extensions\/ext.*not initiali[sz]ed/i)
    expect(out).to include("git -C extensions/ext checkout release/0.3.0")
  end

  it "refuses when master has a commit the release branch does not contain" do
    git(@parent, "checkout", "-q", "master")
    File.write(File.join(@parent, "hotfix.txt"), "master only")
    git(@parent, "add", "-A"); git(@parent, "commit", "-q", "-m", "master-only")
    [ "origin", "gitea" ].each { |r| git(@parent, "push", "-q", r, "master") }
    git(@parent, "checkout", "-q", "release/0.3.0")
    st, out = release("0.3.0", "--dry-run")
    expect(st).not_to be_success
    expect(out).to match(/master.*not.*(contained|ancestor)|does not contain/i)
  end

  it "refuses when a submodule's master has a commit its release branch lacks" do
    sub = File.join(@parent, "extensions/ext")
    git(sub, "checkout", "-q", "master")
    File.write(File.join(sub, "extra.txt"), "x")
    git(sub, "add", "-A"); git(sub, "commit", "-q", "-m", "ext master-only")
    git(sub, "push", "-q", "origin", "master")
    git(sub, "checkout", "-q", "release/0.3.0")
    st, out = release("0.3.0", "--dry-run")
    expect(st).not_to be_success
    expect(out).to match(/extensions\/ext/)
  end

  it "refuses to run from inside a submodule" do
    st, out = release("0.3.0", "--dry-run", chdir: File.join(@parent, "extensions/ext"))
    expect(st).not_to be_success
    expect(out).to match(/inside a submodule|superproject/i)
  end

  describe "--dry-run" do
    it "validates, prints the plan, and changes nothing" do
      before_head = git(@parent, "rev-parse", "HEAD")
      before_pkg  = File.read(File.join(@parent, "package.json"))
      st, out = release("0.3.0", "--dry-run")
      expect(st).to be_success, out
      expect(out).to match(/dry.run/i)
      expect(out).to include("0.3.0")
      expect(out).to match(/tag 0\.3\.0/i)
      expect(git(@parent, "rev-parse", "HEAD")).to eq(before_head)
      expect(File.read(File.join(@parent, "package.json"))).to eq(before_pkg)
      expect(gemspec_version(@parent)).to eq("0.1.0")
      expect(git(@parent, "tag", "-l", "0.3.0")).to be_empty
      expect(git(@parent, "status", "--porcelain")).to be_empty
      expect(git(@parent, "ls-remote", "--tags", "origin", "0.3.0")).to be_empty
    end

    it "still fails validation in dry-run mode" do
      git(@parent, "tag", "0.3.0")
      st, = release("0.3.0", "--dry-run")
      expect(st).not_to be_success
    end
  end

  describe "a real release in the throwaway repo" do
    before do
      @st, @out = release("0.3.0")
    end

    it "succeeds" do
      expect(@st).to be_success, @out
    end

    it "stamps the gemspec, package.json files and lockfiles from the tag" do
      git(@parent, "checkout", "-q", "master")
      git(@parent, "submodule", "update", "-q", "--init")
      expect(gemspec_version(@parent)).to eq("0.3.0")
      expect(JSON.parse(File.read(File.join(@parent, "package.json")))["version"]).to eq("0.3.0")
      expect(JSON.parse(File.read(File.join(@parent, "frontend/package.json")))["version"]).to eq("0.3.0")
      expect(JSON.parse(File.read(File.join(@parent, "package-lock.json")))["version"]).to eq("0.3.0")
    end

    it "tags master and the submodule with the plain version and pushes the tags" do
      master = git(@parent, "rev-parse", "master")
      expect(git(@parent, "rev-list", "-n1", "0.3.0")).to eq(master)
      expect(git(@parent, "ls-remote", "--tags", "origin", "0.3.0")).to include(master)
      sub = File.join(@parent, "extensions/ext")
      expect(git(sub, "tag", "-l", "0.3.0")).to eq("0.3.0")
      expect(git(sub, "ls-remote", "--tags", "origin", "0.3.0")).not_to be_empty
      expect(git(@parent, "tag", "-l", "v0.3.0")).to be_empty
    end

    it "merges with --no-ff and back-merges into develop" do
      expect(git(@parent, "log", "-1", "--format=%p", "master").split.size).to eq(2)
      expect(git(@parent, "merge-base", "--is-ancestor", "master", "develop")).to eq("")
      expect(git(@parent, "show", "develop:package.json")).to include('"0.3.0"')
    end

    it "carries no AI attribution in any commit it made" do
      log = git(@parent, "log", "--format=%B", "0.2.0..master")
      expect(log).not_to match(/co-authored-by|generated with|claude/i)
    end
  end

  def remote_tag(bare, tag) = git(bare, "tag", "-l", tag)

  describe "remotes" do
    it "pushes the parent to every configured remote (gitea first) and the origin-only submodule to origin" do
      st, out = release("0.3.0")
      expect(st).to be_success, out
      master = git(@parent, "rev-parse", "master")
      expect(git(@par_gitea, "rev-parse", "refs/tags/0.3.0^{commit}")).to eq(master)
      expect(git(@par_origin, "rev-parse", "refs/tags/0.3.0^{commit}")).to eq(master)
      expect(git(@par_gitea, "rev-parse", "master")).to eq(master)
      expect(out.index("gitea")).to be < out.index("origin")
      expect(remote_tag(File.join(@root, "ext.git"), "0.3.0")).to eq("0.3.0")
    end

    it "queries every remote for an existing tag" do
      git(@parent, "tag", "0.3.0")
      git(@parent, "push", "-q", "gitea", "refs/tags/0.3.0")
      git(@parent, "tag", "-d", "0.3.0")
      st, out = release("0.3.0")
      expect(st).not_to be_success
      expect(out).to match(/tag 0\.3\.0 already exists.*gitea/i)
    end

    it "honours RELEASE_REMOTES" do
      out = nil
      st, out = Open3.capture3(git_env.merge("RELEASE_REMOTES" => "origin"), "bash", script, "0.3.0", chdir: @parent).then { |o, e, status| [ status, o + e ] }
      expect(st).to be_success, out
      expect(remote_tag(@par_origin, "0.3.0")).to eq("0.3.0")
      expect(remote_tag(@par_gitea, "0.3.0")).to be_empty
    end

    it "aborts when a remote is unreachable" do
      git(@parent, "remote", "set-url", "gitea", File.join(@root, "nowhere.git"))
      st, out = release("0.3.0")
      expect(st).not_to be_success
      expect(out).to match(/gitea/)
      expect(out).to match(/nowhere\.git/), "the fetch error must be shown"
      expect(git(@parent, "tag", "-l", "0.3.0")).to be_empty
    end

    it "refuses when local master is not the remote tip" do
      other = File.join(@root, "other")
      sh!("git", "clone", "-q", @par_gitea, other, chdir: @root)
      File.write(File.join(other, "late.txt"), "x")
      git(other, "add", "-A"); git(other, "commit", "-q", "-m", "late")
      git(other, "push", "-q", "origin", "master")
      st, out = release("0.3.0")
      expect(st).not_to be_success
      expect(out).to match(/master.*(differs|equal|tip)/i)
    end
  end

  describe "partial failure and resume" do
    it "does all local work first, prints resume instructions on a failed push, and a re-run completes without redoing work" do
      git(@parent, "config", "remote.gitea.pushurl", File.join(@root, "readonly-nowhere.git"))
      st, out = release("0.3.0")
      expect(st).not_to be_success
      expect(out).to match(/resume/i)
      expect(out).to match(/scripts\/release\.sh 0\.3\.0/)
      # local work is complete: merged, tagged, back-merged
      expect(git(@parent, "tag", "-l", "0.3.0")).to eq("0.3.0")
      expect(git(@parent, "merge-base", "--is-ancestor", "master", "develop")).to eq("")
      expect(git(@par_gitea, "tag", "-l", "0.3.0")).to be_empty
      count = git(@parent, "rev-list", "--count", "develop")

      git(@parent, "config", "--unset", "remote.gitea.pushurl")
      st, out = release("0.3.0")
      expect(st).to be_success, out
      expect(git(@parent, "rev-list", "--count", "develop")).to eq(count)
      expect(git(@par_gitea, "tag", "-l", "0.3.0")).to eq("0.3.0")
      expect(git(@par_origin, "tag", "-l", "0.3.0")).to eq("0.3.0")
      expect(git(@par_gitea, "rev-parse", "develop")).to eq(git(@parent, "rev-parse", "develop"))
    end
  end

  describe "resuming a partly finished release" do
    it "validates the develop tip before pushing, and a failing gate blocks the push" do
      git(@parent, "config", "remote.gitea.pushurl", File.join(@root, "readonly-nowhere.git"))
      st, = release("0.3.0")
      expect(st).not_to be_success
      git(@parent, "config", "--unset", "remote.gitea.pushurl")

      FileUtils.mkdir_p(File.join(@parent, "scripts"))
      File.write(File.join(@parent, "scripts/validate.sh"), "#!/usr/bin/env bash\necho GATE_RAN_ON=$(git rev-parse --abbrev-ref HEAD)\nexit 1\n")
      FileUtils.chmod(0o755, File.join(@parent, "scripts/validate.sh"))
      git(@parent, "checkout", "-q", "develop")
      git(@parent, "add", "-A"); git(@parent, "commit", "-q", "-m", "unvalidated develop change")

      st, out = release("0.3.0")

      expect(st).not_to be_success
      expect(out).to include("GATE_RAN_ON=develop")
      expect(out).to match(/develop.*(validate|gate)/i)
      expect(git(@par_gitea, "tag", "-l", "0.3.0")).to be_empty
    end
  end

  describe "back-merge conflicts" do
    def advance_develop_pointer
      sub = File.join(@parent, "extensions/ext")
      git(@parent, "checkout", "-q", "develop")
      git(sub, "checkout", "-q", "develop")
      File.write(File.join(sub, "late.txt"), "late")
      git(sub, "add", "-A"); git(sub, "commit", "-q", "-m", "late ext change")
      git(sub, "push", "-q", "origin", "develop")
      git(@parent, "add", "extensions/ext"); git(@parent, "commit", "-q", "-m", "bump ext on develop")
      %w[origin gitea].each { |r| git(@parent, "push", "-q", r, "develop") }
      git(sub, "checkout", "-q", "release/0.3.0")
      git(@parent, "checkout", "-q", "release/0.3.0")
    end

    it "resolves a gitlink-only conflict by taking the submodule's develop tip" do
      advance_develop_pointer
      st, out = release("0.3.0")
      expect(st).to be_success, out
      sub = File.join(@parent, "extensions/ext")
      git(@parent, "checkout", "-q", "develop")
      expect(git(@parent, "ls-tree", "develop", "extensions/ext").split[2]).to eq(git(sub, "rev-parse", "develop"))
      expect(git(sub, "ls-tree", "-r", "--name-only", "develop")).to include("late.txt")
      expect(git(@parent, "status", "--porcelain", "--ignore-submodules=all")).to be_empty
    end

    it "aborts on any non-gitlink conflict, before pushing anything" do
      git(@parent, "checkout", "-q", "develop")
      pkg = File.join(@parent, "package.json")
      File.write(pkg, File.read(pkg).sub('"0.2.0"', '"0.2.5"'))
      git(@parent, "commit", "-q", "-am", "develop edits the version line")
      %w[origin gitea].each { |r| git(@parent, "push", "-q", r, "develop") }
      git(@parent, "checkout", "-q", "release/0.3.0")
      st, out = release("0.3.0")
      expect(st).not_to be_success
      expect(out).to match(/non-gitlink conflict/i)
      expect(git(@parent, "status", "--porcelain", "--ignore-submodules=all")).to be_empty
      expect(git(@par_gitea, "tag", "-l", "0.3.0")).to be_empty
      expect(git(@par_origin, "tag", "-l", "0.3.0")).to be_empty
    end
  end

  describe "the gate" do
    def add_gate(bad:)
      FileUtils.mkdir_p(File.join(@parent, "scripts"))
      File.write(File.join(@parent, "scripts/validate.sh"), "#!/usr/bin/env bash\n[ ! -e GATE_BAD ]\n")
      FileUtils.chmod(0o755, File.join(@parent, "scripts/validate.sh"))
      File.write(File.join(@parent, "GATE_BAD"), "x") if bad
      git(@parent, "add", "-A"); git(@parent, "commit", "-q", "-m", "add gate")
    end

    it "validates the stamped release head BEFORE any merge or tag; a fix on the release branch then tags the fixed content" do
      add_gate(bad: true)
      master_before = git(@parent, "rev-parse", "master")
      st, out = release("0.3.0")
      expect(st).not_to be_success
      expect(out).to match(/validate\.sh failed/)
      expect(git(@parent, "tag", "-l", "0.3.0")).to be_empty
      expect(git(File.join(@parent, "extensions/ext"), "tag", "-l", "0.3.0")).to be_empty
      expect(git(@parent, "rev-parse", "master")).to eq(master_before)
      expect(git(@parent, "rev-parse", "--abbrev-ref", "HEAD")).to eq("release/0.3.0")

      git(@parent, "rm", "-q", "GATE_BAD"); git(@parent, "commit", "-q", "-m", "fix gate")
      st, out = release("0.3.0")
      expect(st).to be_success, out
      expect(git(@parent, "ls-tree", "--name-only", "0.3.0")).not_to include("GATE_BAD")
      expect(git(@par_gitea, "tag", "-l", "0.3.0")).to eq("0.3.0")
    end

    it "warns loudly when the gate is skipped or absent" do
      st, out = release("0.3.0")
      expect(st).to be_success, out
      expect(out).to match(/WARNING.*gate/i)
    end
  end

  describe "a hotfix resume" do
    it "finds hotfix/X.Y.Z from the ref even though the first run left the parent on develop" do
      [ @parent, File.join(@parent, "extensions/ext") ].each { |d| git(d, "branch", "-m", "release/0.3.0", "hotfix/0.3.1") }
      git(@parent, "config", "remote.gitea.pushurl", File.join(@root, "readonly-nowhere.git"))
      st, out = release("0.3.1")
      expect(st).not_to be_success
      expect(out).to match(/resume/i)
      expect(git(@parent, "rev-parse", "--abbrev-ref", "HEAD")).to eq("develop")

      git(@parent, "config", "--unset", "remote.gitea.pushurl")
      st, out = release("0.3.1")
      expect(st).to be_success, out
      expect(git(@par_gitea, "tag", "-l", "0.3.1")).to eq("0.3.1")
      expect(git(@par_origin, "tag", "-l", "0.3.1")).to eq("0.3.1")
    end
  end
end

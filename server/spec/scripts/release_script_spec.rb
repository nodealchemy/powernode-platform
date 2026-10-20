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
    git(@parent, "tag", "0.2.0")
    git(@parent, "branch", "develop")
    git(@parent, "push", "-q", "origin", "master", "develop", "--tags")

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
end

# frozen_string_literal: true

require "spec_helper"
require "open3"
require "tmpdir"
require "fileutils"

# IMP-ba424a66188f — the pre-push pointer gate must verify the gitlinks of the commits
# being PUSHED (pre-push stdin: `<local ref> <local sha> <remote ref> <remote sha>`), not
# the checkout's HEAD, and must work from a linked worktree. Everything here runs in temp
# dirs against a temp bare "submodule remote"; no real remote is touched.
RSpec.describe "scripts/verify-submodule-pointers.sh (IMP-ba424a66188f)" do
  root = File.expand_path("../../..", __dir__)
  script = File.join(root, "scripts", "verify-submodule-pointers.sh")
  zeros = "0" * 40
  git_env = {
    "GIT_AUTHOR_NAME" => "t", "GIT_AUTHOR_EMAIL" => "t@example.invalid",
    "GIT_COMMITTER_NAME" => "t", "GIT_COMMITTER_EMAIL" => "t@example.invalid",
    "GIT_CONFIG_GLOBAL" => "/dev/null", "GIT_CONFIG_SYSTEM" => "/dev/null",
    "GIT_CONFIG_NOSYSTEM" => "1"
  }.freeze

  def git(dir, *args, env: {})
    out, err, st = Open3.capture3(env, "git", "-C", dir, *args)
    raise "git #{args.join(' ')} failed: #{err}" unless st.success?

    out.strip
  end

  around do |ex|
    Dir.mktmpdir("verify-pointers") do |tmp|
      @tmp = tmp
      ex.run
    end
  end

  let(:env) { git_env }

  # Parent with one submodule at extensions/system whose remote is a temp bare repo.
  #   branch main:    gitlink -> GOOD (pushed to the submodule remote)
  #   branch feature: gitlink -> BAD  (exists only in the local submodule clone)
  let(:fixture) do
    bare = File.join(@tmp, "sub.git")
    parent = File.join(@tmp, "parent")
    git(@tmp, "init", "--bare", "-q", "-b", "develop", bare, env: env)
    FileUtils.mkdir_p(parent)
    git(parent, "init", "-q", "-b", "main", env: env)
    sub = File.join(parent, "extensions", "system")
    git(@tmp, "clone", "-q", bare, sub, env: env)
    git(sub, "checkout", "-q", "-b", "develop", env: env)
    File.write(File.join(sub, "a.txt"), "a")
    git(sub, "add", "a.txt", env: env)
    git(sub, "commit", "-q", "-m", "good", env: env)
    good = git(sub, "rev-parse", "HEAD", env: env)
    git(sub, "push", "-q", "origin", "develop", env: env)
    File.write(File.join(sub, "b.txt"), "b")
    git(sub, "add", "b.txt", env: env)
    git(sub, "commit", "-q", "-m", "bad (unpublished)", env: env)
    bad = git(sub, "rev-parse", "HEAD", env: env)
    git(sub, "checkout", "-q", good, env: env)

    File.write(File.join(parent, ".gitmodules"),
               "[submodule \"extensions/system\"]\n\tpath = extensions/system\n\turl = #{bare}\n")
    git(parent, "add", ".gitmodules", env: env)
    git(parent, "update-index", "--add", "--cacheinfo", "160000,#{good},extensions/system", env: env)
    git(parent, "commit", "-q", "-m", "good pointer", env: env)
    good_sha = git(parent, "rev-parse", "HEAD", env: env)
    git(parent, "checkout", "-q", "-b", "feature", env: env)
    git(parent, "update-index", "--cacheinfo", "160000,#{bad},extensions/system", env: env)
    git(parent, "commit", "-q", "-m", "bad pointer", env: env)
    bad_sha = git(parent, "rev-parse", "HEAD", env: env)
    { parent: parent, good: good_sha, bad: bad_sha }
  end

  def run_hook(script, cwd, stdin, env)
    Open3.capture3(env.merge("PUSH_REMOTE" => "origin"), "bash", script, "--remote", "origin",
                   chdir: cwd, stdin_data: stdin)
  end

  def line(ref, sha, remote_sha = "0" * 40)
    "#{ref} #{sha} #{ref} #{remote_sha}\n"
  end

  it "(a) refuses a non-HEAD ref whose gitlink is missing from the submodule remote, though HEAD is fine" do
    git(fixture[:parent], "checkout", "-q", "main", env: env) # HEAD good
    _out, err, st = run_hook(script, fixture[:parent], line("refs/heads/feature", fixture[:bad]), env)
    expect(st.exitstatus).to eq(1), err
  end

  it "(b) allows a good pushed ref even when HEAD's gitlink is bad" do
    git(fixture[:parent], "checkout", "-q", "feature", env: env) # HEAD bad
    out, err, st = run_hook(script, fixture[:parent], line("refs/heads/main", fixture[:good]), env)
    expect(st.exitstatus).to eq(0), "#{out}\n#{err}"
  end

  it "(c) works when pushed from a linked worktree (submodule not initialised there)" do
    parent = fixture[:parent]
    wt = File.join(@tmp, "wt")
    git(parent, "checkout", "-q", "main", env: env)
    git(parent, "worktree", "add", "-q", wt, "feature", env: env)
    expect(File.directory?(File.join(wt, "extensions", "system", ".git"))).to be(false)

    _o, e1, bad = run_hook(script, wt, line("refs/heads/feature", fixture[:bad]), env)
    expect(bad.exitstatus).to eq(1), e1
    o2, e2, good = run_hook(script, wt, line("refs/heads/main", fixture[:good]), env)
    expect(good.exitstatus).to eq(0), "#{o2}\n#{e2}"
  end

  it "(d) ignores a delete push (zero local sha) even when HEAD is bad" do
    git(fixture[:parent], "checkout", "-q", "feature", env: env)
    out, err, st = run_hook(script, fixture[:parent], line("(delete)", zeros, fixture[:bad]), env)
    expect(st.exitstatus).to eq(0), "#{out}\n#{err}"
  end

  # git exports GIT_DIR (and friends) to hooks. Without clearing it, every `git -C <submodule>`
  # call in the checker queries the PARENT repository, so each pointer reads "not found".
  it "(e) works under the hook environment, where git exports GIT_DIR for the parent" do
    parent = fixture[:parent]
    git(parent, "checkout", "-q", "main", env: env)
    hook_env = env.merge("GIT_DIR" => File.join(parent, ".git"))
    out, err, st = run_hook(script, parent, line("refs/heads/main", fixture[:good]), hook_env)
    expect(st.exitstatus).to eq(0), "#{out}\n#{err}"
    _o, e2, bad = run_hook(script, parent, line("refs/heads/feature", fixture[:bad]), hook_env)
    expect(bad.exitstatus).to eq(1), e2
  end

  it "falls back to HEAD when no ref lines are supplied (manual invocation)" do
    git(fixture[:parent], "checkout", "-q", "feature", env: env)
    _o, err, st = run_hook(script, fixture[:parent], "", env)
    expect(st.exitstatus).to eq(1), err
  end

  # git passes the URL (not a remote name) as $1 when pushing to a bare URL. Previously the
  # checker looked for a submodule remote literally named like the URL, found none and SKIPPED.
  describe "when the push target is a URL rather than a remote name" do
    it "resolves the URL to the matching parent remote and still catches an unpublished pointer" do
      parent = fixture[:parent]
      url = "https://git.example.invalid/org/parent.git"
      git(parent, "remote", "add", "origin", url, env: env)
      _o, err, st = Open3.capture3(env, "bash", script, "--remote", url, chdir: parent,
                                   stdin_data: line("refs/heads/feature", fixture[:bad]))
      expect(st.exitstatus).to eq(1), err
      expect(err + _o).not_to match(/\[skip\]/)
    end

    it "falls back to the default remotes (never skips) when the URL matches no remote" do
      parent = fixture[:parent]
      out, err, st = Open3.capture3(env, "bash", script, "--remote", "https://other.example.invalid/x.git",
                                    chdir: parent, stdin_data: line("refs/heads/feature", fixture[:bad]))
      expect(st.exitstatus).to eq(1), "#{out}\n#{err}"
    end

    it "allows a good pointer pushed to an unmatched URL" do
      parent = fixture[:parent]
      out, err, st = Open3.capture3(env, "bash", script, "--remote", "https://other.example.invalid/x.git",
                                    chdir: parent, stdin_data: line("refs/heads/main", fixture[:good]))
      expect(st.exitstatus).to eq(0), "#{out}\n#{err}"
    end
  end
end

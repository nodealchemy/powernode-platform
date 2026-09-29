# frozen_string_literal: true

require "spec_helper"
require "open3"
require "tmpdir"
require "json"
require "fileutils"

# IMP-6d060f65ccae — scripts/wt.sh. Runs the REAL script and the REAL scripts/prepare-worktree.sh
# against a throwaway "main checkout" (a git repo with one public submodule and a bare origin), so
# the lane ledger, the extension branches, the stranded-commit refusal and the teardown are
# exercised end to end. The test database is not touched: create runs with --no-db and remove drops
# through a WT_DROPDB_CMD stub that records what it was asked to drop.
RSpec.describe "scripts/wt.sh" do
  repo_scripts = File.expand_path("../../../scripts", __dir__)

  def sh!(*cmd, chdir: nil, env: {})
    out, err, st = Open3.capture3({ "GIT_AUTHOR_NAME" => "T", "GIT_AUTHOR_EMAIL" => "t@example.invalid",
                                    "GIT_COMMITTER_NAME" => "T", "GIT_COMMITTER_EMAIL" => "t@example.invalid",
                                    "GIT_CONFIG_COUNT" => "1", "GIT_CONFIG_KEY_0" => "protocol.file.allow",
                                    "GIT_CONFIG_VALUE_0" => "always" }.merge(env), *cmd, chdir: chdir || @dir)
    raise "#{cmd.join(' ')} failed: #{err}" unless st.success?

    out.strip
  end

  def commit_file(repo, name, msg)
    File.write(File.join(repo, name), "#{name}-#{rand(1e9)}\n")
    sh!("git", "add", name, chdir: repo)
    sh!("git", "commit", "-q", "-m", msg, chdir: repo)
    sh!("git", "rev-parse", "HEAD", chdir: repo)
  end

  around do |example|
    Dir.mktmpdir("wt-spec") do |dir|
      @dir = File.realpath(dir)
      example.run
    end
  end

  before do
    @origin = File.join(@dir, "origin.git")
    @ext_origin = File.join(@dir, "ext.git")
    @main = File.join(@dir, "main")
    @wts = File.join(@dir, "wts")
    @drops = File.join(@dir, "drops.log")
    [ @origin, @ext_origin ].each { |r| sh!("git", "init", "-q", "--bare", "-b", "develop", r) }

    seed_ext = File.join(@dir, "seed-ext")
    sh!("git", "clone", "-q", @ext_origin, seed_ext)
    sh!("git", "checkout", "-q", "-b", "develop", chdir: seed_ext)
    commit_file(seed_ext, "e0.txt", "ext base")
    sh!("git", "push", "-q", "origin", "develop", chdir: seed_ext)

    sh!("git", "clone", "-q", @origin, @main)
    sh!("git", "checkout", "-q", "-b", "develop", chdir: @main)
    FileUtils.mkdir_p([ File.join(@main, "scripts/lib"), File.join(@main, "server") ])
    %w[wt.sh prepare-worktree.sh].each { |f| FileUtils.cp(File.join(repo_scripts, f), File.join(@main, "scripts", f)) }
    FileUtils.cp(File.join(repo_scripts, "lib/landing-common.sh"), File.join(@main, "scripts/lib/landing-common.sh"))
    File.write(File.join(@main, ".gitignore"), "/scripts/local/\n")
    File.write(File.join(@main, "server/.keep"), "")
    sh!("git", "add", ".", chdir: @main)
    sh!("git", "commit", "-q", "-m", "core base", chdir: @main)
    sh!("git", "submodule", "add", "-q", @ext_origin, "extensions/widgets", chdir: @main)
    sh!("git", "commit", "-q", "-m", "add ext", chdir: @main)
    sh!("git", "push", "-q", "origin", "develop", chdir: @main)
    sh!("git", "-C", File.join(@main, "extensions/widgets"), "fetch", "-q", "origin")
    @other = File.join(@dir, "other")
    sh!("git", "clone", "-q", "-b", "develop", @origin, @other)

    File.write(File.join(@dir, "dropdb.sh"), "#!/usr/bin/env bash\necho \"$TEST_DB_NAME $TEST_ENV_NUMBER\" >> #{@drops}\n")
    File.chmod(0o755, File.join(@dir, "dropdb.sh"))
  end

  def wt(*args, env: {})
    full = { "WT_ROOT" => @wts, "WT_DROPDB_CMD" => File.join(@dir, "dropdb.sh"), "WORKTREE_MAX" => "9" }.merge(env)
    out, err, st = Open3.capture3(full, File.join(@main, "scripts/wt.sh"), *args)
    [ out, err, st.exitstatus ]
  end

  def create(key, *extra, env: {})
    out, err, code = wt("create", key, "--no-db", *extra, env: env)
    raise "create #{key} failed (#{code}): #{err}" unless code.zero?

    JSON.parse(out.lines.last)
  end

  def ledger
    path = File.join(@main, "scripts/local/worktree-lanes")
    File.exist?(path) ? File.readlines(path).map { |l| l.chomp.split("\t") } : []
  end

  def lane_of(path)
    File.read(File.join(path, "server/.env.test.local"))[/^TEST_REDIS_LANE=(\d+)/, 1].to_i
  end

  it "creates a worktree on a new branch with a ledger lane, isolated DB name and an extension branch" do
    info = create("imp-a1")

    expect(info).to include("path" => File.join(@wts, "imp-a1"), "branch" => "imp-a1", "redis_lane" => 1)
    expect(info["test_database"]).to match(/\Apowernode_test_imp_a1\z/)
    expect(sh!("git", "-C", info["path"], "branch", "--show-current")).to eq("imp-a1")
    expect(sh!("git", "-C", File.join(info["path"], "extensions/widgets"), "branch", "--show-current")).to eq("imp-a1")
    expect(sh!("git", "-C", info["path"], "rev-parse", "HEAD")).to eq(sh!("git", "-C", @main, "rev-parse", "origin/develop"))
    expect(lane_of(info["path"])).to eq(1)
    expect(ledger.map { |l| l.values_at(0, 1, 2) }).to eq([ [ "1", info["path"], "imp-a1" ] ])
  end

  it "symlinks vendor/bundle and copies the bundle config and private lockfile from the main checkout" do
    FileUtils.mkdir_p(File.join(@main, "server/vendor/bundle"))
    FileUtils.mkdir_p(File.join(@main, "worker/vendor/bundle"))
    FileUtils.mkdir_p(File.join(@main, "server/.bundle"))
    File.write(File.join(@main, "server/.bundle/config"), "BUNDLE_PATH: \"vendor/bundle\"\n")
    File.write(File.join(@main, "server/Gemfile.private.lock"), "LOCK\n")
    info = create("imp-a2")
    path = info["path"]

    expect(File.readlink(File.join(path, "server/vendor/bundle"))).to eq(File.join(@main, "server/vendor/bundle"))
    expect(File.readlink(File.join(path, "worker/vendor/bundle"))).to eq(File.join(@main, "worker/vendor/bundle"))
    expect(File.read(File.join(path, "server/.bundle/config"))).to include("vendor/bundle")
    expect(File.symlink?(File.join(path, "server/.bundle/config"))).to be false
    expect(File.read(File.join(path, "server/Gemfile.private.lock"))).to eq("LOCK\n")
  end

  it "never hands out a held lane: legacy .env.test.local lanes count, and a released lane is reused" do
    first = create("imp-a3")
    second = create("imp-a4")
    expect([ first["redis_lane"], second["redis_lane"] ]).to eq([ 1, 2 ])

    # a worktree made the OLD way (prepare-worktree.sh alone: lane only in .env.test.local)
    legacy = File.join(@wts, "legacy")
    sh!(File.join(@main, "scripts/prepare-worktree.sh"), legacy, "--create", "develop", env: { "WORKTREE_MAX" => "9" })
    expect(lane_of(legacy)).to eq(3)
    expect(create("imp-a5")["redis_lane"]).to eq(4)

    _out, _err, code = wt("remove", first["path"])
    expect(code).to eq(0)
    expect(create("imp-a6")["redis_lane"]).to eq(1)
  end

  it "gives concurrent creates distinct lanes" do
    threads = %w[imp-b1 imp-b2 imp-b3].map { |k| Thread.new { create(k) } }
    lanes = threads.map(&:value).map { |i| i["redis_lane"] }

    expect(lanes.sort).to eq([ 1, 2, 3 ])
    expect(ledger.map(&:first).sort).to eq(%w[1 2 3])
  end

  it "refuses to create when every lane is held, leaving no worktree, branch or ledger line behind" do
    create("imp-c1")
    _out, err, code = wt("create", "imp-c2", "--no-db", env: { "WT_MAX_LANE" => "1" })

    expect(code).not_to eq(0)
    expect(err).to match(/no free redis lane/)
    expect(File.exist?(File.join(@wts, "imp-c2"))).to be false
    expect(sh!("git", "-C", @main, "branch", "--list", "imp-c2")).to eq("")
    expect(ledger.size).to eq(1)
  end

  it "releases the lane and removes the half-made worktree when creation fails" do
    _out, err, code = wt("create", "imp-d1", "--no-db", "--base", "no-such-branch")

    expect(code).not_to eq(0)
    expect(err).not_to be_empty
    expect(File.exist?(File.join(@wts, "imp-d1"))).to be false
    expect(ledger).to be_empty
  end

  describe "remove" do
    let!(:info) { create("imp-e1") }
    let(:path) { info["path"] }

    it "refuses while core holds a commit that is not on origin/develop, and removes nothing" do
      commit_file(path, "work.txt", "unlanded core work")
      _out, err, code = wt("remove", path)

      expect(code).to eq(1)
      expect(err).to match(/STRANDED: core: 1 commit/)
      expect(err).to match(/refusing to remove/)
      expect(File.directory?(path)).to be true
      expect(ledger.size).to eq(1)
      expect(File.exist?(@drops)).to be false
    end

    it "refuses while a nested extension worktree holds an unlanded commit" do
      commit_file(File.join(path, "extensions/widgets"), "ext-work.txt", "unlanded ext work")
      _out, err, code = wt("remove", path)

      expect(code).to eq(1)
      expect(err).to match(/STRANDED:.* extensions\/widgets: 1 commit/)
      expect(File.directory?(path)).to be true
    end

    it "does not count a commit whose patch already landed under another sha" do
      sha = commit_file(path, "same.txt", "the change")
      # land the identical patch from another clone with a different sha
      File.write(File.join(@other, "same.txt"), File.read(File.join(path, "same.txt")))
      sh!("git", "add", "same.txt", chdir: @other)
      sh!("git", "commit", "-q", "-m", "the change (rebased)", chdir: @other)
      sh!("git", "push", "-q", "origin", "develop", chdir: @other)
      _out, err, code = wt("remove", path)

      expect(code).to eq(0), err
      expect(File.exist?(path)).to be false
    end

    it "removes a clean worktree: drops the lane database, releases the lane, deletes the merged branches" do
      _out, err, code = wt("remove", path)

      expect(code).to eq(0), err
      expect(File.exist?(path)).to be false
      expect(File.read(@drops).split).to eq([ "powernode_test_imp_e1", "_imp_e1" ])
      expect(ledger).to be_empty
      expect(sh!("git", "-C", @main, "branch", "--list", "imp-e1")).to eq("")
      expect(sh!("git", "-C", File.join(@main, "extensions/widgets"), "branch", "--list", "imp-e1")).to eq("")
      expect(sh!("git", "-C", @main, "worktree", "list")).not_to include("imp-e1")
    end

    it "with --strand-ok removes the worktree but keeps the branch, so the commit stays reachable" do
      sha = commit_file(path, "keep.txt", "unlanded core work")
      out, err, code = wt("remove", path, "--strand-ok")

      expect(code).to eq(0), err
      expect(File.exist?(path)).to be false
      expect(err).to match(/branches are KEPT/)
      expect(sh!("git", "-C", @main, "rev-parse", "imp-e1")).to eq(sha)
      expect(ledger).to be_empty
      expect(out).to eq("")
    end

    it "stops before removing anything when the database cannot be dropped" do
      _out, err, code = wt("remove", path, env: { "WT_DROPDB_CMD" => "false" })

      expect(code).to eq(1)
      expect(err).to match(/nothing was removed/)
      expect(File.directory?(path)).to be true
      expect(ledger.size).to eq(1)
    end

    it "refuses while another process has its working directory inside the worktree" do
      pid = Process.spawn("sleep", "30", chdir: File.join(path, "server"))
      begin
        _out, err, code = wt("remove", path)
        expect(code).to eq(1)
        expect(err).to match(/working directory inside/)
        expect(File.directory?(path)).to be true

        _out, _err, code = wt("remove", path, "--busy-ok")
        expect(code).to eq(0)
      ensure
        Process.kill("TERM", pid)
        Process.wait(pid)
      end
    end

    it "refuses the main checkout and paths that are not worktrees" do
      _out, err, code = wt("remove", @main)
      expect(code).to eq(1)
      expect(err).to match(/main checkout/)

      stray = File.join(@dir, "stray")
      FileUtils.mkdir_p(stray)
      _out, err, code = wt("remove", stray)
      expect(code).to eq(1)
      expect(err).to match(/not a worktree/)
    end
  end

  describe "audit" do
    it "lists lane, ledger state, liveness and ahead-counts per tree, and flags a shared lane" do
      a = create("imp-f1")
      b = create("imp-f2")
      commit_file(a["path"], "ahead.txt", "unlanded")
      commit_file(File.join(b["path"], "extensions/widgets"), "ext-ahead.txt", "unlanded ext")
      out, err, code = wt("audit", "--json")

      expect(code).to eq(0), err
      doc = JSON.parse(out)
      rows = doc["worktrees"].to_h { |r| [ r["path"], r ] }
      expect(rows[a["path"]]).to include("lane" => 1, "in_ledger" => "yes", "liveness" => "idle", "core_ahead" => "1")
      expect(rows[a["path"]]["ext_ahead"]).to eq("extensions/widgets" => "0")
      expect(rows[b["path"]]).to include("lane" => 2, "core_ahead" => "0")
      expect(rows[b["path"]]["ext_ahead"]).to eq("extensions/widgets" => "1")
      expect(rows[@main]).to include("in_ledger" => "no", "lane" => nil)
      expect(doc["duplicate_lanes"]).to eq([])

      File.write(File.join(b["path"], "server/.env.test.local"), "TEST_ENV_NUMBER=_imp_f2\nTEST_REDIS_LANE=1\n")
      out, _err, _code = wt("audit", "--json")
      expect(JSON.parse(out)["duplicate_lanes"]).to eq([ "1" ])
    end

    it "prints a readable table by default" do
      create("imp-f3")
      out, err, code = wt("audit")

      expect(code).to eq(0), err
      expect(out).to match(/PATH\s+BRANCH\s+LANE\s+LEDGER\s+LIVENESS\s+AHEAD/)
      expect(out).to match(/imp-f3\s+imp-f3\s+1\s+yes\s+idle\s+core 0 \| widgets 0/)
    end
  end
end

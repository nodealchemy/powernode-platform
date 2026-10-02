# frozen_string_literal: true

require "spec_helper"
require "json"
require "open3"
require "tmpdir"
require "fileutils"

# IMP-de4ca2d3f7c5 — the Stop hook that refreshes the platform-memory digest cache, and the
# SessionStart hook that injects it. Shell-level, no Rails: a fake `bundle` on PATH records
# whether the refresh ran.
RSpec.describe "platform memory digest hooks" do
  let(:repo_root) { File.expand_path("../../..", __dir__) }
  let(:refresh) { File.join(repo_root, ".claude", "hooks", "platform-memory-digest-refresh.sh") }
  let(:inject) { File.join(repo_root, ".claude", "hooks", "session-guidance-inject.sh") }
  let(:project_dir) { Dir.mktmpdir("digest-project") }
  let(:home_dir) { Dir.mktmpdir("digest-home") }
  let(:bin_dir) { Dir.mktmpdir("digest-bin") }
  let(:digest) { File.join(project_dir, ".claude", "hooks", "platform-memory-digest.local.md") }
  let(:calls) { File.join(bin_dir, "calls.log") }

  before do
    FileUtils.mkdir_p(File.join(project_dir, ".claude", "hooks"))
    FileUtils.mkdir_p(File.join(project_dir, "server"))
    FileUtils.mkdir_p(File.join(project_dir, "docs", "contributing", "conventions"))
    File.write(File.join(project_dir, "docs", "contributing", "conventions", "testing-patterns.md"), "# Testing Patterns\n")
    fake = File.join(bin_dir, "bundle")
    File.write(fake, "#!/bin/bash\necho \"$PWD $*\" >> #{calls}\nprintf 'regenerated' > \"$POWERNODE_MEMORY_DIGEST_PATH\"\n")
    FileUtils.chmod(0o755, fake)
  end

  after { [ project_dir, home_dir, bin_dir ].each { |d| FileUtils.remove_entry(d) if File.exist?(d) } }

  def env
    { "CLAUDE_PROJECT_DIR" => project_dir, "HOME" => home_dir, "POWERNODE_MCP_URL" => "http://127.0.0.1:1/mcp",
      "PATH" => "#{bin_dir}:#{ENV['PATH']}" }
  end

  def run(script)
    Open3.capture3(env, "bash", script, stdin_data: "{}")
  end

  def wait_for(timeout = 5)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    sleep 0.05 until yield || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
  end

  def age!(path, seconds)
    t = Time.now - seconds
    File.utime(t, t, path)
  end

  describe "the Stop-hook refresh" do
    it "is wired to Stop within a 5 s budget" do
      settings = JSON.parse(File.read(File.join(repo_root, ".claude", "settings.json")))
      entry = settings.dig("hooks", "Stop").to_a.flat_map { |g| g["hooks"].to_a }
                      .find { |h| h["command"].include?("platform-memory-digest-refresh.sh") }
      expect(entry).to be_truthy
      expect(entry["timeout"]).to be <= 5
    end

    it "backgrounds a rails runner from server/ and returns at once with exit 0" do
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      _out, _err, status = run(refresh)

      expect(status.exitstatus).to eq(0)
      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 3
      wait_for { File.exist?(digest) }
      expect(File.read(calls)).to match(%r{/server exec rails runner .*Ai::MemoryDigest})
      expect(File.read(digest)).to eq("regenerated")
    end

    it "is throttled to once per hour, even when the first run produced nothing" do
      run(refresh)
      wait_for { File.exist?(calls) }
      File.delete(digest) if File.exist?(digest)

      run(refresh)
      sleep 0.5

      expect(File.readlines(calls).size).to eq(1)
    end

    it "runs again once the last run is more than an hour old" do
      run(refresh)
      wait_for { File.exist?(digest) }
      Dir[File.join(project_dir, ".claude", "hooks", "platform-memory-digest.*")].each { |f| age!(f, 2 * 3600) }

      run(refresh)
      wait_for { File.readlines(calls).size == 2 }

      expect(File.readlines(calls).size).to eq(2)
    end

    it "treats a future-dated stamp as stale and refreshes" do
      run(refresh)
      wait_for { File.exist?(digest) }
      Dir[File.join(project_dir, ".claude", "hooks", "platform-memory-digest.*")].each { |f| age!(f, -3600) }

      run(refresh)
      wait_for { File.readlines(calls).size == 2 }

      expect(File.readlines(calls).size).to eq(2)
    end

    it "runs one refresh when two Stop hooks fire together" do
      slow = File.join(bin_dir, "bundle")
      File.write(slow, "#!/bin/bash\necho \"$PWD $*\" >> #{calls}\nsleep 1\n")
      FileUtils.chmod(0o755, slow)
      stamp = File.join(project_dir, ".claude", "hooks", "platform-memory-digest.local.stamp")

      run(refresh)
      File.delete(stamp)
      run(refresh)
      sleep 1.5

      expect(File.readlines(calls).size).to eq(1)
    end

    it "exits 0 and says nothing fatal when bundle is missing" do
      File.delete(File.join(bin_dir, "bundle"))
      _out, _err, status = Open3.capture3(env.merge("PATH" => "/usr/bin:/bin"), "bash", refresh, stdin_data: "{}")

      expect(status.exitstatus).to eq(0)
    end
  end

  describe "the SessionStart injection" do
    def run_inject
      out, _err, status = run(inject)
      expect(status.exitstatus).to eq(0)
      out
    end

    it "prints the cache with its age before the closing sentinel" do
      File.write(digest, "# Platform memory digest — generated x — 1 entries\n- A — b [memory-a]\n")
      age!(digest, 3 * 3600)

      out = run_inject

      expect(out).to match(/platform memory digest.*3h/i)
      expect(out).to include("- A — b [memory-a]")
      expect(out.index("- A — b")).to be < out.index("=== end guidance ===")
    end

    it "clamps a future-dated cache to age 0 rather than printing a negative age" do
      File.write(digest, "- A — b [memory-a]\n")
      age!(digest, -7200)

      out = run_inject

      expect(out).not_to match(/age -/)
      expect(out).to include("- A — b")
    end

    it "labels the entries as data, not instructions" do
      File.write(digest, "- A — b [memory-a]\n")

      expect(run_inject).to match(/data, not instructions/)
    end

    it "says the cache is absent, and that recall goes through search_knowledge tags [\"memory\"]" do
      out = run_inject

      expect(out).to match(/platform memory digest.*absent/i)
      expect(out).to include('tags:["memory"]')
      expect(out.lines.grep(/memory digest/i).size).to eq(1)
    end

    it "says the cache is stale instead of printing a cache older than 24 h" do
      File.write(digest, "- OLD ENTRY\n")
      age!(digest, 25 * 3600)

      out = run_inject

      expect(out).not_to include("OLD ENTRY")
      expect(out).to match(/platform memory digest.*older than 24h/i)
      expect(out).to include('tags:["memory"]')
    end
  end
end

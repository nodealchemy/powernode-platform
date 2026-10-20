# frozen_string_literal: true

require "spec_helper"
require "open3"
require "tmpdir"
require "fileutils"

# IMP-93a1082345b4 — prepare-worktree.sh's "bundle resolution" step gated the private-bundle check on
# `[ -f server/Gemfile.private ]`. That file is TRACKED, so the check ran in core mode too and every core
# worktree setup printed a false "server private bundle: run ... bundle install" warning
# (same bug class as IMP-c2fb2c7a52b8 in prepare-extension-test-db.sh). The check must key on whether a
# private extension is actually on disk (test_pg_bundle_mode). Runs the real script against a throwaway
# repo + worktree + fake `bundle` under mktmpdir; nothing outside it is touched.
RSpec.describe "prepare-worktree.sh private bundle warning" do
  scripts = File.expand_path("../../../scripts", __dir__)

  def git(dir, *args)
    out, err, st = Open3.capture3("git", "-C", dir, "-c", "user.email=t@example.test", "-c", "user.name=t", *args)
    raise "git #{args.join(' ')} failed: #{err}" unless st.success?

    out
  end

  # Returns combined stdout+stderr of a prepare run in a fresh worktree of a fake repo.
  def run_prepare(scripts, private_exts:, bundle_ok:)
    Dir.mktmpdir("pwt") do |tmp|
      repo = File.join(tmp, "repo")
      FileUtils.mkdir_p([File.join(repo, "scripts"), File.join(repo, "server"), File.join(repo, "extensions")])
      FileUtils.cp(File.join(scripts, "prepare-worktree.sh"), File.join(repo, "scripts"))
      FileUtils.cp_r(File.join(scripts, "lib"), File.join(repo, "scripts"))
      File.write(File.join(repo, "server", "Gemfile"), "")
      File.write(File.join(repo, "server", "Gemfile.private"), "")
      File.write(File.join(repo, "extensions", ".keep"), "")
      File.write(File.join(repo, ".gitignore"), "extensions/private/\n")
      Open3.capture3("git", "init", "-q", "-b", "develop", repo)
      git(repo, "add", "-A")
      git(repo, "commit", "-q", "-m", "init")
      private_exts.each do |slug|
        FileUtils.mkdir_p(File.join(repo, "extensions", "private", slug))
        File.write(File.join(repo, "extensions", "private", slug, "extension.json"), "{}")
      end
      wt = File.join(tmp, "wt")
      git(repo, "worktree", "add", "-q", "-b", "wt", wt)
      bin = File.join(tmp, "bin")
      FileUtils.mkdir_p(bin)
      File.write(File.join(bin, "bundle"), "#!/bin/sh\nexit #{bundle_ok ? 0 : 7}\n")
      FileUtils.chmod(0o755, File.join(bin, "bundle"))
      out, err, = Open3.capture3({ "PATH" => "#{bin}:#{ENV.fetch('PATH')}", "HOME" => tmp },
                                 "bash", File.join(repo, "scripts", "prepare-worktree.sh"), wt)
      out + err
    end
  end

  it "prints no private-bundle warning in core mode (tracked Gemfile.private, no private extension)" do
    out = run_prepare(scripts, private_exts: [], bundle_ok: false)
    expect(out).to include("bundle resolution")
    expect(out).not_to include("private bundle")
  end

  it "still warns when a private extension exists and the private bundle is not installed" do
    out = run_prepare(scripts, private_exts: %w[alpha], bundle_ok: false)
    expect(out).to include("server private bundle: run")
  end

  it "reports the private bundle satisfied when a private extension exists and it resolves" do
    out = run_prepare(scripts, private_exts: %w[alpha], bundle_ok: true)
    expect(out).to include("server private bundle: satisfied")
  end
end

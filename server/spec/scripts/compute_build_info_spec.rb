# frozen_string_literal: true

require "spec_helper"
require "open3"
require "tmpdir"
require "json"
require "fileutils"

# scripts/compute-build-info.sh -- the CI side of Powernode::Version: prints the
# BUILD_INFO.json for a full clone (docker-build.yml and release.yml pass it to
# the image builds as POWERNODE_BUILD_INFO_JSON). Same version format as
# server/config/version.rb.
RSpec.describe "scripts/compute-build-info.sh" do
  let(:script) { File.expand_path("../../../scripts/compute-build-info.sh", __dir__) }
  let(:env) do
    { "GIT_AUTHOR_NAME" => "T", "GIT_AUTHOR_EMAIL" => "t@example.invalid",
      "GIT_COMMITTER_NAME" => "T", "GIT_COMMITTER_EMAIL" => "t@example.invalid" }
  end

  def git(dir, *args)
    out, err, st = Open3.capture3(env, "git", *args, chdir: dir)
    raise "git #{args.join(' ')}: #{out}#{err}" unless st.success?

    out.strip
  end

  def compute(dir, *args, extra_env: {})
    out, err, st = Open3.capture3(env.merge(extra_env), "bash", script, *args, chdir: dir)
    raise "compute failed: #{out}#{err}" unless st.success?

    JSON.parse(out)
  end

  def commit(dir, msg)
    File.write(File.join(dir, "f"), "#{msg}#{rand}")
    git(dir, "add", "-A")
    git(dir, "commit", "-q", "-m", msg)
  end

  around do |ex|
    Dir.mktmpdir("cbi") do |d|
      @dir = d
      git(d, "init", "-q", "-b", "master")
      ex.run
    end
  end

  it "is the plain tag with release=true on master's tip at an exact tag" do
    commit(@dir, "a")
    git(@dir, "tag", "0.2.0")
    info = compute(@dir, "--branch", "master")
    expect(info).to include("version" => "0.2.0", "tag" => "0.2.0", "release" => true, "branch" => "master")
    expect(info["short_sha"]).to eq(info["sha"][0, 7])
  end

  it "guesses the next minor on develop" do
    commit(@dir, "a")
    git(@dir, "tag", "0.2.0")
    git(@dir, "checkout", "-q", "-b", "develop")
    commit(@dir, "b")
    commit(@dir, "c")
    info = compute(@dir, "--branch", "develop")
    expect(info["version"]).to eq("0.3.0-dev.2+#{info['short_sha']}")
    expect(info).to include("release" => false, "tag" => nil)
  end

  it "is -rc.N on a release branch" do
    commit(@dir, "a")
    git(@dir, "tag", "0.2.0")
    git(@dir, "checkout", "-q", "-b", "release/0.3.0")
    commit(@dir, "b")
    info = compute(@dir, "--branch", "release/0.3.0")
    expect(info["version"]).to eq("0.3.0-rc.1+#{info['short_sha']}")
  end

  it "is 0.0.0-dev.0 when no tag is reachable" do
    commit(@dir, "a")
    info = compute(@dir, "--branch", "develop")
    expect(info["version"]).to eq("0.0.0-dev.0+#{info['short_sha']}")
  end

  it "is not a release when the exact tag is off master's tip" do
    commit(@dir, "a")
    git(@dir, "checkout", "-q", "-b", "develop")
    commit(@dir, "b")
    git(@dir, "tag", "0.2.0")
    git(@dir, "checkout", "-q", "master")
    git(@dir, "checkout", "-q", "develop")
    info = compute(@dir, "--branch", "develop")
    expect(info).to include("version" => "0.2.0", "tag" => "0.2.0", "release" => false)
  end
end

# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

# Powernode::Version's display contract: a release build (exact X.Y.Z tag that
# equals the version, built from master's tip) displays the version; every other
# build displays the 7-char sha the module build stamped; a build with no
# identity at all displays "<version>-dev". The build identity is read from
# BUILD_INFO.json (written by extensions/system/scripts/module-build/stage15.sh
# into /opt/powernode/server) or from POWERNODE_BUILD_INFO; the git shell-out
# is a local-dev fallback only, because the staged tree ships without .git.
RSpec.describe Powernode::Version do
  around do |example|
    original = ENV.fetch("POWERNODE_BUILD_INFO", nil)
    described_class.reset!
    example.run
  ensure
    original.nil? ? ENV.delete("POWERNODE_BUILD_INFO") : ENV["POWERNODE_BUILD_INFO"] = original
    described_class.reset!
  end

  def with_env(path)
    ENV["POWERNODE_BUILD_INFO"] = path
    described_class.reset!
    yield
  end

  def with_build_info(hash, &block)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "BUILD_INFO.json")
      File.write(path, JSON.generate(hash))
      with_env(path, &block)
    end
  end

  let(:version) { "0.3.1" }
  let(:no_info) { File.join(Dir.tmpdir, "absent-build-info.json") }

  it "displays the version for a release build" do
    with_build_info(version: version, sha: "a" * 40, short_sha: "aaaaaaa", branch: "master",
                    tag: version, release: true, built_at: "2026-09-03T16:00:00Z") do
      expect(described_class.release?).to be(true)
      expect(described_class.display_version).to eq(version)
      expect(described_class.git_commit).to eq("aaaaaaa")
      expect(described_class.git_branch).to eq("master")
      expect(described_class.git_tag).to eq(version)
    end
  end

  it "displays the short sha for an incremental build" do
    with_build_info(version: version, sha: "b" * 40, short_sha: "bbbbbbb", branch: "develop",
                    tag: nil, release: false, built_at: "2026-09-03T16:00:00Z") do
      expect(described_class.release?).to be(false)
      expect(described_class.display_version).to eq("bbbbbbb")
      expect(described_class.build_date).to eq("2026-09-03T16:00:00Z")
    end
  end

  it "never trusts a release flag whose tag does not equal the version" do
    with_build_info(version: version, sha: "c" * 40, short_sha: "ccccccc", branch: "master",
                    tag: "9.9.9", release: true, built_at: "2026-09-03T16:00:00Z") do
      expect(described_class.release?).to be(false)
      expect(described_class.display_version).to eq("ccccccc")
    end
  end

  it "displays 0.0.0-dev when no build identity exists and git is unavailable" do
    with_env(no_info) do
      allow(described_class).to receive(:git_output).and_return(nil)
      allow(described_class).to receive(:warn)
      expect(described_class.current).to eq("0.0.0-dev.0")
      expect(described_class.release?).to be(false)
      expect(described_class.git_commit).to eq("unknown")
      expect(described_class.display_version).to eq("0.0.0-dev")
    end
  end

  it "falls back to the local git checkout's short sha when no build identity exists" do
    with_env(no_info) do
      allow(described_class).to receive(:git_output).with("describe --tags --long --match '[0-9]*.[0-9]*.[0-9]*'").and_return(nil)
      allow(described_class).to receive(:warn)
      allow(described_class).to receive(:git_output).with("rev-parse --short HEAD").and_return("deadbee")
      allow(described_class).to receive(:git_output).with("rev-parse --abbrev-ref HEAD").and_return("develop")
      expect(described_class.display_version).to eq("deadbee")
      expect(described_class.git_branch).to eq("develop")
    end
  end

  it "reports no prerelease for a plain X.Y.Z (it used to echo the patch digit)" do
    allow(described_class).to receive(:current).and_return("0.3.1")
    expect(described_class.prerelease).to be_nil
    expect(described_class.patch).to eq(1)
    described_class.reset!
    allow(described_class).to receive(:current).and_return("1.2.3-beta.1")
    expect(described_class.prerelease).to eq("beta.1")
    expect(described_class.patch).to eq(3)
  end

  it "parses the dev format: core, prerelease without build metadata" do
    allow(described_class).to receive(:current).and_return("0.3.0-dev.12+abc1234")
    expect([ described_class.major, described_class.minor, described_class.patch ]).to eq([ 0, 3, 0 ])
    expect(described_class.prerelease).to eq("dev.12")
    expect(described_class.core_version).to eq("0.3.0")
  end

  describe ".version_from_describe" do
    it "is the plain tag on an exact tag" do
      expect(described_class.version_from_describe("0.2.0-0-gabc1234", "master")).to eq("0.2.0")
    end

    it "guesses the next minor with -dev.N+sha off a release line" do
      expect(described_class.version_from_describe("0.2.0-137-gabc1234", "develop")).to eq("0.3.0-dev.137+abc1234")
    end

    it "is X.Y.Z-rc.N+sha on release/X.Y.Z and hotfix/X.Y.Z" do
      expect(described_class.version_from_describe("0.2.0-5-gabc1234", "release/0.3.0")).to eq("0.3.0-rc.5+abc1234")
      expect(described_class.version_from_describe("0.2.0-2-gabc1234", "hotfix/0.2.1")).to eq("0.2.1-rc.2+abc1234")
    end

    it "is nil when describe is unusable" do
      expect(described_class.version_from_describe(nil, "develop")).to be_nil
      expect(described_class.version_from_describe("fatal", "develop")).to be_nil
    end
  end

  describe "current resolution" do
    it "prefers BUILD_INFO.json's version" do
      with_build_info(version: "0.4.0-dev.3+abc1234", short_sha: "abc1234") do
        expect(described_class.current).to eq("0.4.0-dev.3+abc1234")
      end
    end

    it "falls back to git describe when BUILD_INFO has no version" do
      with_env(no_info) do
        allow(described_class).to receive(:git_output).with("describe --tags --long --match '[0-9]*.[0-9]*.[0-9]*'").and_return("0.2.0-9-g1234567")
        allow(described_class).to receive(:git_output).with("rev-parse --abbrev-ref HEAD").and_return("develop")
        expect(described_class.current).to eq("0.3.0-dev.9+1234567")
      end
    end

    it "has no VERSION_FILE" do
      expect(described_class.const_defined?(:VERSION_FILE)).to be(false)
    end
  end

  it "exposes the display contract on semantic_version" do
    with_build_info(version: version, sha: "d" * 40, short_sha: "ddddddd", branch: "develop",
                    tag: nil, release: false, built_at: "2026-09-03T16:00:00Z") do
      info = described_class.semantic_version
      expect(info).to include(version: version, display: "ddddddd", short_sha: "ddddddd",
                              git_commit: "ddddddd", git_branch: "develop", git_tag: nil,
                              release: false, built_at: "2026-09-03T16:00:00Z")
    end
  end

  it "reports git_branch 'unknown' (not 'HEAD') on a detached HEAD" do
    with_env(no_info) do
      allow(described_class).to receive(:git_output).with("rev-parse --abbrev-ref HEAD").and_return("HEAD")
      expect(described_class.git_branch).to eq("unknown")
    end
  end

  it "does not treat a detached HEAD as a branch when resolving the version" do
    with_env(no_info) do
      allow(described_class).to receive(:git_output).with("describe --tags --long --match '[0-9]*.[0-9]*.[0-9]*'").and_return("0.2.0-4-gabc1234")
      allow(described_class).to receive(:git_output).with("rev-parse --abbrev-ref HEAD").and_return("HEAD")
      expect(described_class.current).to eq("0.3.0-dev.4+abc1234")
    end
  end
end

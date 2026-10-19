# frozen_string_literal: true

require "spec_helper"
require "open3"
require "tmpdir"
require "fileutils"

# IMP-c2fb2c7a52b8 — prepare-extension-test-db.sh exported BUNDLE_GEMFILE=Gemfile.private whenever the
# TRACKED server/Gemfile.private existed, so a core-mode checkout (no private extensions, no private gems)
# died in bin/rails with "Could not find gem". test_pg_bundle_mode decides the bundle from what is on disk.
# Fake checkout layouts and a fake `bundle` on PATH: no real DB, no real bundler.
RSpec.describe "prepare-extension-test-db.sh bundle mode" do
  lib = File.expand_path("../../../scripts/lib/test-pg.sh", __dir__)
  script = File.expand_path("../../../scripts/prepare-extension-test-db.sh", __dir__)

  def mode(lib, repo, bundle_ok:)
    Dir.mktmpdir("fakebin") do |bin|
      File.write(File.join(bin, "bundle"), <<~SH)
        #!/bin/sh
        # The check must run under the private Gemfile, from server/.
        case "$BUNDLE_GEMFILE" in */server/Gemfile.private) ;; *) exit 91 ;; esac
        case "$PWD" in */server) ;; *) exit 92 ;; esac
        exit #{bundle_ok ? 0 : 7}
      SH
      FileUtils.chmod(0o755, File.join(bin, "bundle"))
      Open3.capture3({ "PATH" => "#{bin}:#{ENV.fetch('PATH')}" },
                     "bash", "-c", 'source "$1"; test_pg_bundle_mode "$2"', "_", lib, repo)
    end
  end

  def layout(root, gemfile_private: true, private_exts: [])
    FileUtils.mkdir_p(File.join(root, "server"))
    FileUtils.touch(File.join(root, "server", "Gemfile.private")) if gemfile_private
    private_exts.each do |slug|
      FileUtils.mkdir_p(File.join(root, "extensions", "private", slug))
      File.write(File.join(root, "extensions", "private", slug, "extension.json"), "{}")
    end
    root
  end

  it "is core when Gemfile.private is tracked but no private extension exists (bundle not consulted)" do
    Dir.mktmpdir("repo") do |root|
      out, _err, st = mode(lib, layout(root), bundle_ok: false)
      expect([st.success?, out.strip]).to eq([true, "core"])
    end
  end

  it "is core when extensions/private exists but is empty" do
    Dir.mktmpdir("repo") do |root|
      FileUtils.mkdir_p(File.join(layout(root), "extensions", "private"))
      out, _err, st = mode(lib, root, bundle_ok: false)
      expect([st.success?, out.strip]).to eq([true, "core"])
    end
  end

  it "is private when a private extension exists and the private bundle resolves" do
    Dir.mktmpdir("repo") do |root|
      out, _err, st = mode(lib, layout(root, private_exts: %w[alpha]), bundle_ok: true)
      expect([st.success?, out.strip]).to eq([true, "private"])
    end
  end

  it "errors loudly (naming the install command) when private extensions exist but the bundle is missing" do
    Dir.mktmpdir("repo") do |root|
      out, err, st = mode(lib, layout(root, private_exts: %w[alpha]), bundle_ok: false)
      expect(st.success?).to be(false)
      expect(out.strip).to be_empty
      expect(err).to include("BUNDLE_GEMFILE=Gemfile.private bundle install")
    end
  end

  it "errors when private extensions exist but Gemfile.private is missing" do
    Dir.mktmpdir("repo") do |root|
      out, err, st = mode(lib, layout(root, gemfile_private: false, private_exts: %w[alpha]), bundle_ok: true)
      expect([st.success?, out.strip]).to eq([false, ""])
      expect(err).to include("Gemfile.private is missing")
    end
  end

  it "wires the decision into the script instead of keying on Gemfile.private's existence" do
    code = File.readlines(script).reject { |l| l.strip.start_with?("#") }.join
    expect(code).to include("test_pg_bundle_mode")
    expect(code).not_to match(/-f "\$SERVER\/Gemfile\.private"/)
  end
end

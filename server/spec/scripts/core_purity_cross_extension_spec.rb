# frozen_string_literal: true

require "spec_helper"
require "open3"
require "json"
require "tmpdir"
require "fileutils"
require "set"

# IMP-7beedfd810c4 — gate #9 (core-purity) had a wholesale early exit:
#
#     # A file inside an extension may reference its own namespace.
#     [[ "$FILE_PATH" == *"/extensions/"* ]] && exit 0
#
# The COMMENT sanctions a file referencing its OWN namespace; the CODE exempted
# every file under extensions/ from every check in the hook. So the gate only
# ever enforced core -> extension and had no opinion on extension -> OTHER
# extension — including a PUBLIC (MIT, publicly cloned) extension naming a
# PRIVATE one, which is absent from public clones and is therefore the same class
# of leak the gate blocks in core.
#
# These specs pin the tightened rule on BOTH enforcement paths:
#   * .claude/hooks/core-purity-check.sh                (blocking, Claude edit-time)
#   * scripts/checks/extension-cross-reference-check.sh (model-agnostic scan mirror,
#     wired into scripts/pattern-validation.sh)
#
# The rule: a file inside an extension may name its OWN extension freely, and only
# its own. Sanctioned forms are preserved exactly as for core — another PUBLIC
# extension's name in a comment or a `defined?` guard is not a dependency — and
# already-committed references are grandfathered through the same
# .claude/hooks/core-purity-baseline.txt ledger the core->public half uses.
#
# The fixture deliberately uses INVENTED extension slugs (alpha/beta/gamma) rather
# than this repo's real ones: both enforcement paths derive names dynamically from
# the tree they are pointed at, so invented slugs exercise the same code, and a
# spec naming a real private extension would (correctly) be blocked by gate #9.
RSpec.describe "gate #9 cross-extension coverage (IMP-7beedfd810c4)" do
  repo_root = File.expand_path("../../..", __dir__) # server/spec/scripts -> repo root
  let(:hook) { File.join(repo_root, ".claude/hooks/core-purity-check.sh") }
  let(:scan) { File.join(repo_root, "scripts/checks/extension-cross-reference-check.sh") }

  baseline_header = "# GENERATED — do not hand-edit.\n"

  # A miniature project tree: two private extensions (alpha, and the kebab-slugged
  # alpha-two), two public ones (beta, gamma) and a core tree.
  #
  # The fixture reproduces the two structural properties of the REAL repo that a
  # naive fixture omits, because both silently changed the verdict:
  #   * `/extensions/private/` is gitignored by the PARENT repo, so any
  #     `git check-ignore` run at the parent root swallows that entire tree;
  #   * every extension is a SUBMODULE — its own git toplevel — so gitignore has
  #     to be resolved there, and a public extension's path makes a parent-root
  #     `git check-ignore` fatal outright.
  # `submodule: false` keeps only the parent repo initialised, for the degenerate
  # non-submodule layout.
  define_method(:build_tree) do |dir, baseline_entries: [], local_entries: nil, submodule: true|
    root = File.realpath(dir)

    write = lambda do |rel, body|
      path = File.join(root, rel)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, body)
      path
    end

    write.call("extensions/private/alpha/server/app/services/alpha/own_ref.rb",
               "Alpha::Registry.call\n")
    # A PRIVATE extension naming a PUBLIC one, in code. Gitignored by the parent,
    # not by its own toplevel — the case that made hook and scan disagree.
    write.call("extensions/private/alpha/server/app/services/alpha/uses_beta.rb",
               "Beta::Registry.call\n")
    write.call("extensions/private/alpha-two/server/app/services/alpha_two/own_ref.rb",
               "AlphaTwo::Registry.call\n")
    write.call("extensions/beta/server/app/services/beta/own_ref.rb",
               "Beta::Registry.call\n")
    write.call("extensions/beta/server/app/services/beta/private_leak.rb",
               "Alpha::Registry.call\n")
    # Kebab-slugged private extension: the derived token is PascalCase
    # (alpha-two -> AlphaTwo::), and both enforcement paths must derive it the same.
    write.call("extensions/beta/server/app/services/beta/kebab_leak.rb",
               "AlphaTwo::Registry.call\n")
    write.call("extensions/beta/server/app/services/beta/public_leak.rb",
               "Gamma::Registry.call\n")
    write.call("extensions/beta/server/app/services/beta/public_comment.rb",
               "# Gamma::Registry lives in the gamma extension.\nBeta::Registry.call\n")
    write.call("extensions/gamma/frontend/src/features/gamma/panel.tsx",
               "export const Panel = () => null;\n")
    write.call("server/app/services/core_leak.rb", "Alpha::Registry.call\n")

    write.call(".gitignore", "/extensions/private/\n")

    baseline = File.join(root, ".claude/hooks/core-purity-baseline.txt")
    FileUtils.mkdir_p(File.dirname(baseline))
    File.write(baseline, baseline_header + baseline_entries.map { |e| "#{e}\n" }.join)
    if local_entries
      File.write(File.join(root, ".claude/hooks/core-purity-baseline.local.txt"),
                 baseline_header + local_entries.map { |e| "#{e}\n" }.join)
    end

    system("git", "init", "-q", root, out: File::NULL, err: File::NULL)
    if submodule
      %w[extensions/beta extensions/gamma
         extensions/private/alpha extensions/private/alpha-two].each do |sub|
        system("git", "init", "-q", File.join(root, sub), out: File::NULL, err: File::NULL)
      end
    end
    root
  end

  # Every source file in the fixture, repo-relative — used by the agreement spec.
  define_method(:fixture_extension_files) do |root|
    Dir.glob(File.join(root, "extensions/**/*.{rb,tsx}"))
       .map { |p| p.sub("#{root}/", "") }
       .sort
  end

  define_method(:run_hook) do |root, rel_path|
    payload = JSON.dump(tool_input: { file_path: File.join(root, rel_path) })
    out, status = Open3.capture2e({ "CLAUDE_PROJECT_DIR" => root }, "bash", hook,
                                  stdin_data: payload)
    [status.exitstatus, out]
  end

  define_method(:run_scan) do |root, *args|
    out, status = Open3.capture2e({ "EXT_CROSS_ROOT" => root }, "bash", scan, *args)
    [status.exitstatus, out]
  end

  describe "the blocking hook" do
    it "blocks a PUBLIC extension file that names a PRIVATE extension" do
      Dir.mktmpdir do |dir|
        root = build_tree(dir)
        code, out = run_hook(root, "extensions/beta/server/app/services/beta/private_leak.rb")
        expect(code).to eq(2)
        expect(out).to include("alpha")
      end
    end

    it "blocks a PUBLIC extension file that names ANOTHER public extension in code" do
      Dir.mktmpdir do |dir|
        root = build_tree(dir)
        code, out = run_hook(root, "extensions/beta/server/app/services/beta/public_leak.rb")
        expect(code).to eq(2)
        expect(out).to include("gamma")
      end
    end

    it "still blocks a cross-extension reference when the extension is its own git toplevel" do
      Dir.mktmpdir do |dir|
        root = build_tree(dir, submodule: true)
        code, = run_hook(root, "extensions/beta/server/app/services/beta/private_leak.rb")
        expect(code).to eq(2)
      end
    end

    it "allows an extension file naming its OWN extension" do
      Dir.mktmpdir do |dir|
        root = build_tree(dir)
        expect(run_hook(root, "extensions/beta/server/app/services/beta/own_ref.rb").first).to eq(0)
        expect(run_hook(root, "extensions/private/alpha/server/app/services/alpha/own_ref.rb").first).to eq(0)
      end
    end

    it "allows a comment-only reference to another PUBLIC extension (sanctioned form)" do
      Dir.mktmpdir do |dir|
        root = build_tree(dir)
        expect(run_hook(root, "extensions/beta/server/app/services/beta/public_comment.rb").first).to eq(0)
      end
    end

    it "does not apply the core frontend placement gate to an extension's own frontend tree" do
      Dir.mktmpdir do |dir|
        root = build_tree(dir)
        expect(run_hook(root, "extensions/gamma/frontend/src/features/gamma/panel.tsx").first).to eq(0)
      end
    end

    it "grandfathers a cross-extension reference listed in the baseline" do
      Dir.mktmpdir do |dir|
        root = build_tree(dir, baseline_entries: [
                            "extensions/beta/server/app/services/beta/private_leak.rb|alpha",
                            "extensions/beta/server/app/services/beta/public_leak.rb|gamma"
                          ])
        expect(run_hook(root, "extensions/beta/server/app/services/beta/private_leak.rb").first).to eq(0)
        expect(run_hook(root, "extensions/beta/server/app/services/beta/public_leak.rb").first).to eq(0)
      end
    end

    it "blocks a PRIVATE extension file that names a PUBLIC extension in code" do
      # The parent repo gitignores /extensions/private/, so this file is invisible
      # to any gitignore probe run at the parent root. The hook resolves gitignore
      # in the file's OWN toplevel and enforces here; the scan must agree.
      Dir.mktmpdir do |dir|
        root = build_tree(dir)
        code, out = run_hook(root, "extensions/private/alpha/server/app/services/alpha/uses_beta.rb")
        expect(code).to eq(2)
        expect(out).to include("beta")
      end
    end

    it "derives a PascalCase token for a kebab-slugged PRIVATE extension" do
      Dir.mktmpdir do |dir|
        root = build_tree(dir)
        code, out = run_hook(root, "extensions/beta/server/app/services/beta/kebab_leak.rb")
        expect(code).to eq(2)
        expect(out).to include("alpha-two")
      end
    end

    it "grandfathers a private-extension-owned reference through the LOCAL ledger" do
      # Entries naming a path under extensions/private/ must never be written to the
      # COMMITTED baseline — that file is published to the public mirror, and the
      # path itself discloses a private extension. They live in the gitignored
      # sibling ledger instead, which both enforcement paths also consult.
      Dir.mktmpdir do |dir|
        root = build_tree(dir, local_entries: [
                            "extensions/private/alpha/server/app/services/alpha/uses_beta.rb|beta"
                          ])
        expect(run_hook(root, "extensions/private/alpha/server/app/services/alpha/uses_beta.rb").first).to eq(0)
        expect(run_scan(root, "--list").last)
          .not_to include("extensions/private/alpha/server/app/services/alpha/uses_beta.rb")
      end
    end

    it "still blocks a CORE file naming a private extension (no regression)" do
      Dir.mktmpdir do |dir|
        root = build_tree(dir)
        code, = run_hook(root, "server/app/services/core_leak.rb")
        expect(code).to eq(2)
      end
    end
  end

  describe "the model-agnostic scan mirror" do
    it "counts the cross-extension references and lists them" do
      Dir.mktmpdir do |dir|
        root = build_tree(dir)
        code, out = run_scan(root)
        expect(code).to eq(0)
        expect(out.strip).to eq("4")

        listed = run_scan(root, "--list").last
        expect(listed).to include("extensions/beta/server/app/services/beta/private_leak.rb|alpha")
        expect(listed).to include("extensions/beta/server/app/services/beta/public_leak.rb|gamma")
        expect(listed).to include("extensions/beta/server/app/services/beta/kebab_leak.rb|alpha-two")
        # The gitignored-by-the-parent private tree must NOT be silently dropped.
        expect(listed).to include("extensions/private/alpha/server/app/services/alpha/uses_beta.rb|beta")
        expect(listed).not_to include("own_ref.rb")
        expect(listed).not_to include("public_comment.rb")
      end
    end

    it "reports 0 once the references are grandfathered in the baseline" do
      Dir.mktmpdir do |dir|
        root = build_tree(dir,
                          baseline_entries: [
                            "extensions/beta/server/app/services/beta/private_leak.rb|alpha",
                            "extensions/beta/server/app/services/beta/kebab_leak.rb|alpha-two",
                            "extensions/beta/server/app/services/beta/public_leak.rb|gamma"
                          ],
                          local_entries: [
                            "extensions/private/alpha/server/app/services/alpha/uses_beta.rb|beta"
                          ])
        expect(run_scan(root).last.strip).to eq("0")
      end
    end

    it "is a no-op PASS when no extensions are checked out" do
      Dir.mktmpdir do |dir|
        root = File.realpath(dir)
        system("git", "init", "-q", root, out: File::NULL, err: File::NULL)
        expect(run_scan(root).last.strip).to eq("0")
      end
    end
  end

  describe "pattern-validation wiring" do
    it "runs the cross-extension check as a security-critical gate" do
      body = File.read(File.join(repo_root, "scripts/pattern-validation.sh"))
      expect(body).to include("scripts/checks/extension-cross-reference-check.sh")
      expect(body).to include("Extension source references no OTHER extension (core-purity mirror)")
    end
  end

  describe "hook and scan agree" do
    # The two enforcement paths are only a mirror if they return the SAME verdict
    # for the SAME file. They diverged once already, silently and in the direction
    # that matters: the scan resolved gitignore at the parent root, which drops the
    # whole /extensions/private/ tree, while the hook resolved it per-toplevel and
    # hard-blocked those same files — a green gate for a tree the hook rejects.
    it "returns the same verdict for every extension source file in the fixture" do
      Dir.mktmpdir do |dir|
        root = build_tree(dir)
        listed = run_scan(root, "--list").last.lines.map { |l| l.split("|").first.strip }.to_set

        fixture_extension_files(root).each do |rel|
          hook_blocks = run_hook(root, rel).first == 2
          expect(hook_blocks).to eq(listed.include?(rel)),
                                 "hook #{hook_blocks ? 'BLOCKS' : 'allows'} #{rel} but the scan " \
                                 "#{listed.include?(rel) ? 'lists' : 'does not list'} it"
        end
      end
    end
  end

  describe "pattern-validation wiring" do
    it "fails the gate when the check script is missing rather than passing silently" do
      body = File.read(File.join(repo_root, "scripts/pattern-validation.sh"))
      # A security-critical gate must not coerce "script absent or errored" into
      # "0 hits". Pin the existence guard and its FAIL branch.
      expect(body).to match(/if \[ ! -r scripts\/checks\/extension-cross-reference-check\.sh \]/)
      expect(body).to include("core-purity mirror script MISSING")
      expect(File).to be_readable(File.join(repo_root, "scripts/checks/extension-cross-reference-check.sh"))
    end
  end

  describe "the baseline generator" do
    it "sources its cross-extension entries from the same check the gates use" do
      body = File.read(File.join(repo_root, "scripts/generate-core-purity-baseline.sh"))
      expect(body).to include("extension-cross-reference-check.sh")
    end

    it "routes private-extension-owned entries to the gitignored LOCAL ledger" do
      body = File.read(File.join(repo_root, "scripts/generate-core-purity-baseline.sh"))
      expect(body).to include("core-purity-baseline.local.txt")
    end

    it "routes by EITHER half of the entry — private path or private slug" do
      # An entry is public-safe only when NEITHER half names a private extension.
      # Run the generator for real against a fixture repo rather than asserting on
      # its source text: routing is the control that keeps the tracked ledger clean.
      Dir.mktmpdir do |dir|
        root = File.realpath(dir)
        FileUtils.mkdir_p(File.join(root, "scripts/checks"))
        FileUtils.mkdir_p(File.join(root, ".claude/hooks"))
        FileUtils.cp(File.join(repo_root, "scripts/generate-core-purity-baseline.sh"),
                     File.join(root, "scripts"))
        FileUtils.cp(File.join(repo_root, "scripts/checks/extension-cross-reference-check.sh"),
                     File.join(root, "scripts/checks"))

        w = lambda do |rel, body|
          FileUtils.mkdir_p(File.dirname(File.join(root, rel)))
          File.write(File.join(root, rel), body)
        end
        # public path, PRIVATE slug  -> local
        w.call("extensions/beta/server/app/services/beta/leak.rb", "Alpha::Registry.call\n")
        # PRIVATE path, public slug  -> local
        w.call("extensions/private/alpha/server/app/services/alpha/uses_beta.rb", "Beta::Registry.call\n")
        # public path, public slug   -> tracked
        w.call("extensions/beta/server/app/services/beta/gamma_leak.rb", "Gamma::Registry.call\n")
        w.call("extensions/gamma/server/app/services/gamma/own.rb", "Gamma::Registry.call\n")
        w.call(".gitignore", "/extensions/private/\n")
        %w[. extensions/beta extensions/gamma extensions/private/alpha].each do |sub|
          system("git", "init", "-q", File.join(root, sub), out: File::NULL, err: File::NULL)
        end

        Open3.capture2e("bash", "scripts/generate-core-purity-baseline.sh", chdir: root)
        tracked = File.read(File.join(root, ".claude/hooks/core-purity-baseline.txt"))
        local   = File.read(File.join(root, ".claude/hooks/core-purity-baseline.local.txt"))

        expect(tracked).to include("extensions/beta/server/app/services/beta/gamma_leak.rb|gamma")
        expect(tracked).not_to include("|alpha")
        expect(tracked).not_to include("extensions/private/")
        expect(local).to include("extensions/beta/server/app/services/beta/leak.rb|alpha")
        expect(local).to include("extensions/private/alpha/server/app/services/alpha/uses_beta.rb|beta")
      end
    end
  end

  describe "the committed baseline" do
    # This file is tracked in core and published to the PUBLIC mirror. A path under
    # extensions/private/ in it discloses a private extension's name and internal
    # layout — the very leak class gate #9 exists to prevent.
    it "never names a path inside a private extension" do
      committed = File.read(File.join(repo_root, ".claude/hooks/core-purity-baseline.txt"))
      offenders = committed.lines.grep(%r{^extensions/private/})
      expect(offenders).to be_empty,
                           "committed baseline discloses private-extension paths: #{offenders.inspect}"
    end

    it "never names a private extension's SLUG either" do
      # Both HALVES of an entry disclose. `<public path>|trading` names no private
      # PATH, but `trading` is itself a private extension's slug — and this file is
      # published to the public mirror. Slugs are derived from disk, so this spec is
      # correctly vacuous in a public clone, which has no private extensions.
      priv = Dir.glob(File.join(repo_root, "extensions/private/*"))
                .select { |d| File.directory?(d) }.map { |d| File.basename(d) }
      skip "no private extensions checked out" if priv.empty?

      committed = File.read(File.join(repo_root, ".claude/hooks/core-purity-baseline.txt"))
      offenders = committed.lines.reject { |l| l.start_with?("#") }
                           .select { |l| priv.include?(l.strip.split("|").last.to_s) }
      expect(offenders).to be_empty,
                           "committed baseline discloses private-extension slugs: #{offenders.inspect}"
    end

    it "is gitignored in its LOCAL form" do
      ignored = File.read(File.join(repo_root, ".gitignore"))
      expect(ignored).to include("core-purity-baseline.local.txt")
    end
  end
end

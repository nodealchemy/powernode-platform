# frozen_string_literal: true

require "rails_helper"
require "open3"

# IMP-70a6c8b3b375. The secret-material block in the repo-root .gitignore
# declares its own design principle at :54-58:
#
#   "Secret material — match by file SHAPE, not any path containing the
#    substring 'secret'. Source code named 'secret*' ... is NOT a secret and
#    must stay tracked."
#
# One rule in that block violated it. `*private*` matched any path with
# "private" anywhere in its name, so a legitimately-named source file was
# ignored with no error and no git status entry — the file simply never became
# trackable. It ate the first draft of spec/lint/extension_namespace_ratchet_spec.rb
# during IMP-cf4f8bcd02c3, which is why that file carries its current name, and
# it had already forced the `!/server/Gemfile.private` un-ignore at :401.
#
# BLOCKING BY CONSTRUCTION, deliberately. This lives in an rspec example rather
# than in scripts/pattern-validation.sh because a non-security-critical
# pattern-validation failure is only a WARN in scripts/validate.sh (it exits 1
# without touching OVERALL_EXIT), whereas a red spec fails the gate. A rule
# whose failure mode is silence needs a guard that stops the build, not one
# that advises.
#
# BOTH ARMS ARE REQUIRED. An "is it ignored" test alone cannot tell a fix from a
# deletion of the rule, and a "is it trackable" test alone cannot tell a fix
# from a hole in the private-extension protection — which matters more than
# usual here, because this repo publishes to a PUBLIC GitHub mirror.
RSpec.describe "repo-root .gitignore substring overreach" do
  # NOT a constant: `REPO_ROOT = ...` inside an RSpec.describe block lands on
  # Object, and spec/integration/worker_job_class_contract_spec.rb:55 already
  # defines REPO_ROOT there. The two are equal today, so it is only a redefinition
  # warning — but whichever file rspec loads second wins, and a wrong root makes
  # every check-ignore call exit 128.
  let(:repo_root) { Rails.root.join("..").cleanpath }

  # Reports the winning rule for a path, or nil when the path is NOT ignored.
  # `git check-ignore` needs no file on disk, so these are hypothetical paths —
  # the guard must not depend on creating files with dangerous names.
  #
  # --no-index so the answer is about the RULES, not about what happens to be
  # tracked already: without it a tracked file reports "not ignored" even when a
  # pattern covers it, which would let a real overreach hide behind an existing
  # commit.
  #
  # A NEGATION IS A MATCH THAT MEANS THE OPPOSITE. With --no-index, `-v` reports
  # a winning `!` rule and exits 0 — so "status.success?" alone reads
  # `!/server/Gemfile.private` as "ignored". The pattern is the third
  # colon-separated field of `<source>:<line>:<pattern>\t<path>`; a leading "!"
  # un-ignores.
  def ignoring_rule(path)
    out, err, status = Open3.capture3(
      "git", "check-ignore", "-v", "--no-index", path, chdir: repo_root.to_s
    )

    # git check-ignore: 0 = ignored, 1 = not ignored, 128 = fatal. Treating 128
    # as "not ignored" would pass every "MUST be trackable" example vacuously —
    # a wrong chdir or a non-git checkout would read as a clean bill of health.
    raise "git check-ignore failed for #{path.inspect}: #{err.strip}" if status.exitstatus != 0 && status.exitstatus != 1
    return nil unless status.success?

    rule = out.strip
    pattern = rule.split("\t").first.to_s.split(":", 3).last.to_s
    pattern.start_with?("!") ? nil : rule
  end

  it "distinguishes a negation from an ignore (the helper is not fooled)" do
    # server/Gemfile.private is un-ignored by an explicit `!` rule. If the helper
    # ever stops parsing negations, this reds instead of silently reporting every
    # negated path as ignored.
    _out, _err, status = Open3.capture3(
      "git", "check-ignore", "-v", "--no-index", "server/Gemfile.private", chdir: repo_root.to_s
    )
    expect(status).to be_success, "expected git to report a winning rule for this path"
    expect(ignoring_rule("server/Gemfile.private")).to be_nil
  end

  describe "paths that MUST stay ignored" do
    # The private-extension tree is the thing the pattern is popularly believed
    # to protect. It is protected by its OWN anchored rule (/extensions/private/),
    # which is why narrowing the substring rule is safe — but that has to be
    # asserted, not assumed, since committing a private extension to a repo with
    # a public mirror is the worst outcome available here.
    it "still ignores everything under extensions/private/" do
      %w[
        extensions/private/business/app/models/thing.rb
        extensions/private/trading/lib/strategy.rb
        extensions/private/anything-at-all
      ].each do |path|
        expect(ignoring_rule(path)).to be_present, "#{path} is NOT ignored — a private extension could be committed"
      end
    end

    # The bare `extensions/private` entry, not just the trailing-slash one: a
    # trailing-slash pattern matches DIRECTORIES only, so a symlinked
    # extensions/private would slip past it and commit the extension's name.
    it "ignores extensions/private as a bare entry, not only as a directory" do
      expect(ignoring_rule("extensions/private")).to be_present
    end

    it "still ignores private key material by shape" do
      {
        "config/private_key" => "extension-less private key",
        "config/deploy.private" => ".private extension",
        "tmp/server_private_key" => "suffixed private key",
        "privatekey.txt" => "no separator, .txt dump",
        "private_key.txt" => "underscore, .txt dump",
        "private-key" => "hyphen, extension-less",
        "privatekeys" => "plural",
        "config/private_key.pem" => "already covered by *.pem, pinned so both cannot be lost at once"
      }.each do |path, why|
        expect(ignoring_rule(path)).to be_present, "#{path} (#{why}) is NOT ignored"
      end
    end

    it "still ignores the private-mode bundle lock but not the Gemfile itself" do
      expect(ignoring_rule("server/Gemfile.private.lock")).to be_present
      expect(ignoring_rule("server/Gemfile.private")).to be_nil,
        "Gemfile.private is committed on purpose (it only flips the discovery flag)"
    end
  end

  describe "legitimately-named source files that MUST be trackable" do
    # Each of these is a plausible real file. Every one of them was silently
    # unaddable before this fix.
    it "does not ignore source, spec, doc or fixture files merely for saying 'private'" do
      {
        "server/spec/lint/private_extension_namespace_spec.rb" => "the spec this pattern actually ate",
        "server/app/models/private_note.rb" => "a model",
        "server/app/services/private_channel_service.rb" => "a service",
        "docs/guides/private-methods.md" => "a doc",
        "frontend/src/components/PrivateRoute.tsx" => "a component",
        "server/spec/fixtures/private_profile.json" => "a fixture"
      }.each do |path, what|
        rule = ignoring_rule(path)
        expect(rule).to be_nil,
          "#{path} (#{what}) is ignored by `#{rule}` — it would never appear in git status, " \
          "and `git add` of a directory containing it stays silent"
      end
    end
  end
end

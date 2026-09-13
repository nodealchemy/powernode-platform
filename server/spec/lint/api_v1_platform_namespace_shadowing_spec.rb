# frozen_string_literal: true

require "spec_helper"
require "find"

# CAMPAIGN 01a08c9b — the shadowing this increment created, and the guard that
# stops it coming back.
#
# `Api::V1::Platform::ComponentStatusesController` (increment A4) defines the
# constant `Api::V1::Platform`. Ruby resolves an unqualified constant through
# the LEXICAL scope first, so from that moment every class nested inside
# `module Api; module V1` resolves a bare `Platform::…` to `Api::V1::Platform`,
# not to the top-level `::Platform` namespace that holds the status model.
#
# This is not hypothetical. Lane 1's `Api::V1::Internal::PlatformStatusController`
# called `Platform::Status::SweepRunner` unqualified and started raising
# `NameError: uninitialized constant Api::V1::Platform::Status`. It rescues per
# account, so the endpoint kept returning HTTP 200 with an error string in each
# account's slot: a sweep that did nothing, reported as a success. A guard that
# only watched the status code would never have seen it.
#
# The codebase already lives with the identical hazard for `Api::V1::Ai` and
# has already settled the convention — fully qualify. See
# `app/controllers/api/v1/ai/campaigns_controller.rb`, which writes
# `::Ai::DevLoop::CampaignDriver` for exactly this reason.
#
# THE RULE: inside `server/app/controllers/api/v1/**`, a reference to the core
# `Platform` namespace is written `::Platform::…`. `Api::V1::Platform::…` is
# also fine — it names the controller namespace explicitly, which is never
# ambiguous.
#
# COMMENTS: full-line comments are stripped before scanning, because a comment
# cannot resolve a constant and the header of the very file that was bitten
# needs to spell the bare form to explain itself. A TRAILING comment is NOT
# stripped: distinguishing one from a `#` inside a string or an interpolation
# needs a real lexer, and the conservative direction here is to flag. If a
# trailing comment trips this, qualify the token in the comment too.
#
# Both arms are asserted below over fixtures, so this cannot become a check
# that passes for everything (or fails for everything) unnoticed.
RSpec.describe "Api::V1::Platform namespace shadowing" do
  controllers_root = File.expand_path("../../app/controllers/api/v1", __dir__)

  # `Platform::` NOT already qualified and NOT the tail of a longer constant.
  #   ::Platform::Status      → preceded by ":"  → no match (qualified)
  #   Api::V1::Platform::X    → preceded by ":"  → no match (explicit)
  #   SystemPlatform::X       → preceded by "m"  → no match (different constant)
  #   Platform::Status        → unqualified      → MATCH
  UNQUALIFIED = /(?<![:\w])Platform::/

  def offending_lines(source)
    source.each_line.with_index(1).filter_map do |line, number|
      next if line.match?(/\A\s*#/)

      [ number, line.strip ] if line.match?(UNQUALIFIED)
    end
  end

  describe "the matcher itself" do
    it "flags an unqualified reference" do
      expect(offending_lines("Platform::Status::SweepRunner.run!(account)\n")).not_to be_empty
    end

    it "accepts the qualified form" do
      expect(offending_lines("::Platform::Status::SweepRunner.run!(account)\n")).to be_empty
    end

    it "accepts an explicit Api::V1::Platform reference and a different constant ending in Platform" do
      expect(offending_lines("Api::V1::Platform::ComponentStatusesController\n")).to be_empty
      # A constant whose name merely ENDS in Platform is a different thing.
      expect(offending_lines("Some::NodePlatform::Thing\n")).to be_empty
    end

    it "ignores a full-line comment but still flags the same token in code" do
      expect(offending_lines("  # a bare Platform::Status resolves to the controller namespace\n")).to be_empty
      expect(offending_lines("  x = Platform::Status\n")).not_to be_empty
    end

    it "reports the line number, not just a boolean" do
      source = "class Foo\n  Platform::Status\nend\n"
      expect(offending_lines(source)).to eq([ [ 2, "Platform::Status" ] ])
    end
  end

  it "has controllers to scan (an empty sweep is not a pass)" do
    files = []
    Find.find(controllers_root) { |path| files << path if File.file?(path) && path.end_with?(".rb") }
    expect(files.size).to be > 20
  end

  it "qualifies every reference to the core Platform namespace under api/v1" do
    offenders = []

    Find.find(controllers_root) do |path|
      next unless File.file?(path) && path.end_with?(".rb")

      rel = path.delete_prefix("#{File.expand_path('../..', controllers_root)}/")
      offending_lines(File.read(path)).each do |number, text|
        offenders << "#{rel}:#{number} — #{text}"
      end
    end

    expect(offenders).to be_empty, <<~MSG
      Unqualified `Platform::` under app/controllers/api/v1.

      `Api::V1::Platform` (the component-status controller namespace) shadows the
      top-level `::Platform` for every class lexically inside Api::V1, so these
      resolve to `Api::V1::Platform::…` and raise NameError at runtime — and a
      controller that rescues per item will report HTTP 200 while doing nothing.

      Write `::Platform::…`. Precedent: api/v1/ai/campaigns_controller.rb uses
      `::Ai::DevLoop::CampaignDriver` for the identical Api::V1::Ai shadowing.

      #{offenders.join("\n")}
    MSG
  end
end

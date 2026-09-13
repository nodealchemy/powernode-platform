# frozen_string_literal: true

require "rails_helper"

# Campaign 01a08c9b, increment A5 — Platform::ComponentStatus#remediation has
# exactly ONE writer.
#
# Design §4.3 states the column is "derived from SignalState,
# RemediationOutcome, ApprovalRequest and the lane binding — never
# hand-written". That sentence is the whole guarantee the operator screen
# rests on: `remediation.state` is what tells a person whether anybody is
# doing anything about a failing component. A second writer does not produce a
# wrong value so much as TWO values, with nothing to say which is current —
# and the screen would render whichever wrote last.
#
# It needs a detector rather than a convention because the defect is
# invisible: a `remediation:` slipped into some other service's `update!` is a
# one-word diff that reviews cleanly, breaks nothing, and quietly makes the
# column mean two things.
#
# SCOPE: core `app/` AND every extension's `server/app/`. A core-only scan
# would report zero while an extension lane hand-wrote the column, which is
# the likelier place for it to happen — the lanes live there.
RSpec.describe "Platform::ComponentStatus#remediation has one writer", type: :lint do
  # THE writer. Relative to the repo root so the failure message names
  # something a person can open.
  #
  # A METHOD, not a constant. A constant assigned inside an RSpec.describe
  # block lands on Object, where a same-named constant in any other spec file
  # in the same process clobbers it — and `SOLE_WRITER` / `WRITE_CALL_RX` /
  # `ATTR_WRITE_RX` are exactly the generic names that collide. This suite has
  # been bitten by duplicate-constant clobber before.
  def sole_writer
    "server/app/services/platform/status/remediation_state.rb"
  end

  let(:repo_root) { File.expand_path("../../..", __dir__) }
  let(:core_app) { File.join(repo_root, "server", "app") }

  let(:scanned_files) do
    files = Dir.glob(File.join(core_app, "**", "*.rb")) +
            Dir.glob(File.join(repo_root, "extensions", "*", "server", "app", "**", "*.rb")) +
            Dir.glob(File.join(repo_root, "extensions", "private", "*", "server", "app", "**", "*.rb"))
    files = files.uniq.sort

    # A scan of nothing passes vacuously. Assert the corpus is real, and that
    # it actually reaches the extension trees — a glob that silently matched
    # only core would report "zero violations" over half the code.
    expect(files).not_to be_empty, "scanned no Ruby sources under #{core_app}"
    expect(files.any? { |f| f.include?("/extensions/") }).to be(true),
      "scanned no extension sources — the glob has stopped reaching extensions/*/server/app"
    files
  end

  # KEYWORD-ARGUMENT WRITE. Bounded by `[^)]` so the match cannot run past the
  # call's own closing paren into an unrelated hash further down the file, and
  # multiline so a `remediation:` on its own line inside a wrapped `update!`
  # is still caught.
  #
  # Deliberately NOT a bare /remediation:/ — the column is READ all over the
  # serializers and the drawer payloads, and a lint that fires on every read
  # is a lint that gets deleted.
  def write_call_rx
    /
      \b(?:update!?|update_columns?|update_attribute|assign_attributes|upsert|insert!?|create!?|new)
      \s*\(?[^)]{0,400}?\bremediation:\s
    /xm
  end

  # ATTRIBUTE WRITER. `[^=~]` after the `=` keeps `==`, `=~` and `=>` out.
  def attr_write_rx
    /\.remediation\s*=[^=~]/
  end

  def violations_in(source)
    source.scan(write_call_rx).size + source.scan(attr_write_rx).size
  end

  it "finds no writer outside Platform::Status::RemediationState" do
    offenders = scanned_files.filter_map do |file|
      next if file.end_with?(sole_writer)

      count = violations_in(File.read(file))
      next if count.zero?

      file.delete_prefix("#{repo_root}/")
    end

    expect(offenders).to be_empty, <<~MSG
      #{offenders.size} file(s) write Platform::ComponentStatus#remediation:

        #{offenders.join("\n  ")}

      That column is DERIVED (design §4.3) and has exactly one writer,
      #{sole_writer}. Supply the facts through
      Platform::Status::SignalSources instead and let the derivation run — a
      second writer gives the operator screen two answers with no way to tell
      which is current.
    MSG
  end

  # THE OTHER ARM. A detector that matches nothing passes for the wrong
  # reason, and this one is a pair of hand-written regexes over a moving
  # codebase — the likeliest way it fails is by quietly matching zero things.
  describe "the detector is live" do
    it "matches the sole writer's own assignment" do
      source = File.read(File.join(repo_root, sole_writer))

      expect(violations_in(source)).to be >= 1,
        "#{sole_writer} no longer matches the detector — either the writer moved " \
        "(update #{sole_writer.inspect} above) or the regexes have gone dead and this lint now " \
        "passes over everything."
    end

    it "matches a keyword-argument write, including a wrapped one" do
      expect(violations_in('row.update!(remediation: payload)')).to eq(1)
      expect(violations_in("row.update!(\n  remediation: payload\n)")).to eq(1)
      expect(violations_in('Platform::ComponentStatus.create!(component_kind: k, remediation: p)')).to eq(1)
    end

    it "matches the attribute writer" do
      expect(violations_in("row.remediation = payload")).to eq(1)
    end

    it "does not match a READ of the column" do
      expect(violations_in("render_success(remediation: row.remediation)")).to eq(0)
      expect(violations_in("return if row.remediation == other")).to eq(0)
      expect(violations_in('state = row.remediation["state"]')).to eq(0)
      expect(violations_in("{ remediation: status.remediation }")).to eq(0)
    end
  end
end

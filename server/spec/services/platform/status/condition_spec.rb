# frozen_string_literal: true

require "rails_helper"

# Component status plane, increment A1 — the condition shape (design §4.2).
RSpec.describe Platform::Status::Condition do
  let(:now) { Time.current.change(usec: 0) }

  describe ".build" do
    it "produces string keys, a normalized status and an evidence hash" do
      condition = described_class.build(type: "Reachable", status: false, reason: "HeartbeatStale",
                                        message: "no heartbeat for 7m 12s",
                                        evidence: { "seconds" => 432 }, observed_generation: "7", now: now)

      expect(condition.keys).to all(be_a(String))
      expect(condition["type"]).to eq("Reachable")
      expect(condition["status"]).to be(false)
      expect(condition["reason"]).to eq("HeartbeatStale")
      expect(condition["message"]).to eq("no heartbeat for 7m 12s")
      expect(condition["evidence"]).to eq("seconds" => 432)
      expect(condition["observed_generation"]).to eq("7")
      expect(condition["observed_at"]).to eq(now)
    end

    it "normalizes an unmeasurable status to the string unknown, never to nil" do
      expect(described_class.build(type: "Fresh", status: nil, reason: "NoSnapshot")["status"]).to eq("unknown")
      expect(described_class.build(type: "Fresh", status: "unknown", reason: "NoSnapshot")["status"]).to eq("unknown")
      expect(described_class.build(type: "Fresh", status: true, reason: "Recent")["status"]).to be(true)
    end

    it "rejects a non-CamelCase type or reason, and accepts the CamelCase form" do
      expect { described_class.build(type: "reachable", status: true, reason: "Ok") }
        .to raise_error(ArgumentError, /type must be UpperCamelCase/)
      expect { described_class.build(type: "Reachable", status: true, reason: "heartbeat_stale") }
        .to raise_error(ArgumentError, /reason must be UpperCamelCase/)
      expect { described_class.build(type: "Reachable", status: true, reason: "Ok") }.not_to raise_error
    end

    it "rejects an invented severity and accepts the two real ones" do
      expect { described_class.build(type: "Reachable", status: false, reason: "Gone", severity: "critical") }
        .to raise_error(ArgumentError, /severity must be one of/)
      expect(described_class.build(type: "Reachable", status: false, reason: "Gone", severity: "down")["severity"]).to eq("down")
      expect(described_class.build(type: "Reachable", status: false, reason: "Slow")["severity"]).to be_nil
    end

    it "rejects a status that is neither boolean nor unknown" do
      expect { described_class.build(type: "Reachable", status: "maybe", reason: "Ok") }
        .to raise_error(ArgumentError, /status must be true, false/)
    end
  end

  describe "last_transition_at" do
    let(:earlier) { 3.hours.ago.change(usec: 0) }

    it "PRESERVES the previous transition time when the status is unchanged" do
      previous = described_class.build(type: "Reachable", status: false, reason: "Timeout", now: earlier)

      rebuilt = described_class.build(type: "Reachable", status: false, reason: "Timeout",
                                      previous: previous, now: now)

      expect(rebuilt["last_transition_at"]).to eq(earlier)
      expect(rebuilt["observed_at"]).to eq(now)
    end

    it "UPDATES it when the status flips" do
      previous = described_class.build(type: "Reachable", status: false, reason: "Timeout", now: earlier)

      flipped = described_class.build(type: "Reachable", status: true, reason: "Responding",
                                      previous: previous, now: now)

      expect(flipped["last_transition_at"]).to eq(now)
    end

    it "treats a first sighting (no previous) as a transition" do
      expect(described_class.build(type: "Reachable", status: true, reason: "Responding", now: now)["last_transition_at"])
        .to eq(now)
    end

    it "distinguishes false from unknown, so blindness is a transition and not a silent hold" do
      previous = described_class.build(type: "Reachable", status: false, reason: "Timeout", now: earlier)

      unknown = described_class.build(type: "Reachable", status: "unknown", reason: "ContributorError",
                                      previous: previous, now: now)

      expect(unknown["last_transition_at"]).to eq(now)
    end
  end

  describe ".index_by_type" do
    it "keys stored conditions by type and ignores malformed entries" do
      stored = [ { "type" => "Fresh", "status" => true }, "junk", { "status" => true } ]

      expect(described_class.index_by_type(stored).keys).to eq(%w[Fresh])
      expect(described_class.index_by_type(nil)).to eq({})
    end
  end

  describe ".verdict_for" do
    def condition(type:, status:, severity: nil)
      described_class.build(type: type, status: status, reason: "Reason", severity: severity)
    end

    it "maps a true condition to ok and a false one to degraded by default" do
      expect(described_class.verdict_for(condition(type: "Reachable", status: true))).to eq("ok")
      expect(described_class.verdict_for(condition(type: "Reachable", status: false))).to eq("degraded")
    end

    it "escalates a false condition to down only when it asks for it" do
      expect(described_class.verdict_for(condition(type: "Reachable", status: false, severity: "down"))).to eq("down")
      expect(described_class.verdict_for(condition(type: "Reachable", status: false, severity: "degraded"))).to eq("degraded")
    end

    it "maps an unknown status to not_measured, never to ok" do
      expect(described_class.verdict_for(condition(type: "Reachable", status: "unknown"))).to eq("not_measured")
    end

    it "reaches held and progressing ONLY through their own condition types, and only when true" do
      expect(described_class.verdict_for(condition(type: "Held", status: true))).to eq("held")
      expect(described_class.verdict_for(condition(type: "Progressing", status: true))).to eq("progressing")

      # An absent intent is the ordinary case, not a failure.
      expect(described_class.verdict_for(condition(type: "Held", status: false))).to eq("ok")
      expect(described_class.verdict_for(condition(type: "Progressing", status: false))).to eq("ok")
    end
  end

  describe ".verdict_for_set" do
    it "takes the worst condition" do
      set = [
        described_class.build(type: "Reachable", status: true, reason: "Up"),
        described_class.build(type: "Converged", status: false, reason: "Drift")
      ]

      expect(described_class.verdict_for_set(set)).to eq("degraded")
    end

    it "calls NO conditions not_measured rather than ok" do
      expect(described_class.verdict_for_set([])).to eq("not_measured")
      expect(described_class.verdict_for_set(nil)).to eq("not_measured")
    end

    it "lets a real failure outrank operator intent on the same component" do
      set = [
        described_class.build(type: "Held", status: true, reason: "Cordoned"),
        described_class.build(type: "Reachable", status: false, reason: "Gone", severity: "down")
      ]

      # held ranks just above ok, so a drained node that is ALSO down reports
      # down. Intent hides a plan, never an outage.
      expect(described_class.verdict_for_set(set)).to eq("down")
    end
  end
end

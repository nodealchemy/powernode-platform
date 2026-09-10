# frozen_string_literal: true

require "rails_helper"

# Component status plane, increment A1 — the row and the verdict ladder.
RSpec.describe Platform::ComponentStatus do
  let(:account) { create(:account) }

  describe "validations" do
    it "requires a kind, a ref and a known verdict, and accepts a valid row" do
      row = build(:platform_component_status, account: account)
      expect(row).to be_valid

      expect(build(:platform_component_status, account: account, component_kind: nil)).not_to be_valid
      expect(build(:platform_component_status, account: account, component_ref: nil)).not_to be_valid

      bad = build(:platform_component_status, account: account, verdict: "amber")
      expect(bad).not_to be_valid
      expect(bad.errors[:verdict]).to be_present
    end

    it "allows a NULL account for a shared kind and still refuses a duplicate ref there" do
      create(:platform_component_status, :shared, component_kind: "redis", component_ref: "primary")

      duplicate = build(:platform_component_status, :shared, component_kind: "redis", component_ref: "primary")
      expect(duplicate).not_to be_valid

      # ...and the database backs the model up: NULLS NOT DISTINCT means the
      # two null accounts are ONE value, so a validation bypass still fails.
      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)

      # A different ref under the same null account is fine.
      expect(build(:platform_component_status, :shared, component_kind: "redis", component_ref: "replica")).to be_valid
    end

    it "scopes ref uniqueness to the account and the kind, not globally" do
      other_account = create(:account)
      create(:platform_component_status, account: account, component_kind: "docker_host", component_ref: "h1")

      expect(build(:platform_component_status, account: account, component_kind: "docker_host", component_ref: "h1")).not_to be_valid
      expect(build(:platform_component_status, account: other_account, component_kind: "docker_host", component_ref: "h1")).to be_valid
      expect(build(:platform_component_status, account: account, component_kind: "node", component_ref: "h1")).to be_valid
    end

    it "accepts a known remediation state and rejects an invented one" do
      row = build(:platform_component_status, account: account,
                                              remediation: { "state" => described_class::REMEDIATION_AWAITING_OPERATOR })
      expect(row).to be_valid

      row.remediation = { "state" => "almost_fixed" }
      expect(row).not_to be_valid
      expect(row.errors[:remediation].join).to include("almost_fixed")
    end

    it "defaults every JSON column from the model, not the database" do
      row = described_class.new
      expect(row.conditions).to eq([])
      expect(row.dependencies).to eq([])
      expect(row.links).to eq([])
      expect(row.actions).to eq([])
      expect(row.presentation).to eq({})
      expect(row.remediation).to eq({})
    end
  end

  describe "the verdict ladder" do
    it "orders ok < held < progressing < not_measured < degraded < down" do
      ordered = %w[ok held progressing not_measured degraded down]
      expect(described_class::VERDICTS).to eq(ordered)
      expect(ordered.map { |v| described_class.rank_of(v) }).to eq(ordered.each_index.to_a)
    end

    it "treats an unknown verdict token as not_measured rather than as ok" do
      expect(described_class.rank_of("amber")).to eq(described_class.rank_of(described_class::NOT_MEASURED))
    end

    it "picks the worst verdict, and calls an EMPTY set not_measured rather than ok" do
      expect(described_class.worst(%w[ok degraded held])).to eq("degraded")
      expect(described_class.worst(%w[ok ok])).to eq("ok")
      expect(described_class.worst([])).to eq(described_class::NOT_MEASURED)
    end

    it "excludes components held BY INTENT from the operational verdict, but not a real failure" do
      # Intent is read from the condition, not the derived verdict (A1 review
      # L2). Both arms: a held child never raises it, an unheld failure does.
      ok = build(:platform_component_status, verdict: "ok")
      held = build(:platform_component_status, :held_by_intent, verdict: "ok")
      down = build(:platform_component_status, verdict: "down")

      expect(described_class.worst_operational([ ok, held, held ])).to eq("ok")
      expect(described_class.worst_operational([ held, down ])).to eq("down")
      # All-held is operationally fine; nothing observed is not.
      expect(described_class.worst_operational([ held ])).to eq("ok")
      expect(described_class.worst_operational([])).to eq(described_class::NOT_MEASURED)
    end

    it "keeps a held-AND-down component out of the headline while its own verdict still says down" do
      # The case the ruling exists for: a cordoned node that is also down. Its
      # verdict is the truth (`down`, for the drawer), but it must not turn the
      # header red for a planned drain.
      held_and_down = build(:platform_component_status, :held_by_intent, verdict: "down")
      sibling = build(:platform_component_status, verdict: "ok")

      expect(held_and_down.held_by_intent?).to be(true)
      expect(held_and_down.verdict).to eq("down")
      expect(described_class.worst_operational([ held_and_down, sibling ])).to eq("ok")
    end

    it "reads intent from a TRUE Held condition only" do
      expect(build(:platform_component_status, :held_by_intent).held_by_intent?).to be(true)

      # A Held condition that is false is an absent intent, not a held node.
      not_held = build(:platform_component_status, conditions: [
                         { "type" => "Held", "status" => false, "reason" => "NotCordoned" }
                       ])
      expect(not_held.held_by_intent?).to be(false)

      # ...and a component whose derived verdict happens to be `held` but which
      # carries no Held condition is not counted either — the count keys on
      # evidence, not on the ladder.
      expect(build(:platform_component_status, verdict: "held", conditions: []).held_by_intent?).to be(false)
    end
  end

  describe "scopes" do
    it "separates in-plane, plane-less and out-of-plane rows, all three arms" do
      env = create(:ai_environment, account: account)
      other_env = create(:ai_environment, account: account)

      in_plane = create(:platform_component_status, account: account, environment: env)
      plane_less = create(:platform_component_status, account: account, environment: nil)
      out_of_plane = create(:platform_component_status, account: account, environment: other_env)

      expect(described_class.in_plane(env.id)).to contain_exactly(in_plane)
      expect(described_class.plane_less).to contain_exactly(plane_less)
      expect(described_class.out_of_plane(env.id)).to contain_exactly(out_of_plane)
    end

    it "counts a never-swept row as stale and a freshly swept one as not" do
      fresh = create(:platform_component_status, account: account, last_seen_sweep_at: Time.current)
      stale = create(:platform_component_status, account: account, last_seen_sweep_at: 1.hour.ago)
      never = create(:platform_component_status, account: account, last_seen_sweep_at: nil)

      seen = described_class.not_seen_since(10.minutes.ago)
      expect(seen).to include(stale, never)
      expect(seen).not_to include(fresh)
    end
  end

  describe "#last_transition_at" do
    it "returns the most recent condition transition, and nil when there is none" do
      early = 2.hours.ago.change(usec: 0)
      late = 5.minutes.ago.change(usec: 0)
      row = create(:platform_component_status, account: account, conditions: [
                     { "type" => "Reachable", "status" => false, "reason" => "Timeout", "last_transition_at" => early },
                     { "type" => "Fresh", "status" => true, "reason" => "Recent", "last_transition_at" => late }
                   ])

      expect(row.reload.last_transition_at).to be_within(1.second).of(late)
      expect(create(:platform_component_status, account: account, conditions: []).last_transition_at).to be_nil
    end
  end
end

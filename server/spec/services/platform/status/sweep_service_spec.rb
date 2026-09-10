# frozen_string_literal: true

require "rails_helper"

# Component status plane, increment A1 — the sweep and the reap arm.
# Fakes come from PlatformStatusSpecSupport; the `:platform_status` tag also
# snapshots and restores the process-global registry and emitter seam.
RSpec.describe Platform::Status::SweepService, :platform_status do
  let(:account) { create(:account) }

  describe "the sweep interval" do
    it "reads the SiteSetting and falls back to the documented default, both arms" do
      expect(described_class.sweep_interval_seconds).to eq(described_class::DEFAULT_SWEEP_INTERVAL_SECONDS)

      SiteSetting.create!(key: described_class::SWEEP_INTERVAL_SETTING, value: "120", setting_type: "integer")
      expect(described_class.sweep_interval_seconds).to eq(120)
      expect(described_class.reap_after_seconds).to eq(120 * described_class::REAP_AFTER_SWEEPS)
    end

    it "ignores a non-positive setting rather than reaping everything instantly" do
      SiteSetting.create!(key: described_class::SWEEP_INTERVAL_SETTING, value: "0", setting_type: "integer")

      expect(described_class.sweep_interval_seconds).to eq(described_class::DEFAULT_SWEEP_INTERVAL_SECONDS)
    end
  end

  describe "a registered kind" do
    it "writes one row per component, with the derived verdict and the contributor's presentation" do
      register_fake_kind(records: [ fake_record("a"), fake_record("b", up: false) ])

      summary = described_class.run_once!(account)

      rows = Platform::ComponentStatus.for_account(account).for_kind("fake_kind").order(:component_ref)
      expect(rows.pluck(:component_ref, :verdict)).to eq([ %w[a ok], %w[b degraded] ])
      expect(rows.first.display_name).to eq("Component a")
      expect(rows.first.last_seen_sweep_at).to be_present
      expect(rows.first.presentation["icon"]).to be_present

      expect(summary[:kinds]["fake_kind"]).to include(count: 2, errors: 0)
    end

    it "upserts rather than duplicating, and preserves an unchanged condition's transition time" do
      contributor = register_fake_kind(records: [ fake_record("a", up: false) ])

      described_class.run_once!(account, now: 2.hours.ago)
      first = Platform::ComponentStatus.find_by!(component_ref: "a")
      original_transition = first.conditions.first["last_transition_at"]

      described_class.run_once!(account)
      expect(Platform::ComponentStatus.where(component_ref: "a").count).to eq(1)

      expect(first.reload.conditions.first["last_transition_at"]).to eq(original_transition)

      # And the other arm: flipping the underlying fact moves the timestamp.
      contributor.records = [ fake_record("a", up: true) ]
      described_class.run_once!(account)
      expect(first.reload.conditions.first["last_transition_at"]).not_to eq(original_transition)
    end

    it "returns the transitions and emits NO events itself — A2 is the single producer" do
      contributor = register_fake_kind(records: [ fake_record("a") ])

      first_run = described_class.run_once!(account)
      expect(first_run[:transitions].map { |t| t.values_at(:component_ref, :from, :to) }).to eq([ [ "a", nil, "ok" ] ])

      # A second pass with nothing changed reports NO transition.
      expect(described_class.run_once!(account)[:transitions]).to be_empty

      contributor.records = [ fake_record("a", up: false) ]
      changed = described_class.run_once!(account)
      expect(changed[:transitions].map { |t| t.values_at(:from, :to) }).to eq([ %w[ok degraded] ])
      expect(changed[:kinds]["fake_kind"][:transitions]).to eq(1)
    end
  end

  describe "a contributor that raises" do
    it "marks a single failing component not_measured/ContributorError and keeps its siblings" do
      contributor = register_fake_kind(records: [ fake_record("a"), fake_record("boom") ])
      contributor.raise_on_record = "boom"

      described_class.run_once!(account)

      expect(Platform::ComponentStatus.find_by!(component_ref: "a").verdict).to eq("ok")
      failed = Platform::ComponentStatus.find_by!(component_ref: "boom")
      expect(failed.verdict).to eq("not_measured")
      expect(failed.conditions.first["reason"]).to eq("ContributorError")
      expect(failed.conditions.first["evidence"]["exception_class"]).to eq("RuntimeError")
    end

    # A1 review H1.
    it "marks EVERY EXISTING ROW of the kind not_measured when the ENUMERATION raises" do
      contributor = register_fake_kind(records: [ fake_record("a"), fake_record("b") ])
      described_class.run_once!(account)
      expect(Platform::ComponentStatus.for_kind("fake_kind").pluck(:verdict)).to eq(%w[ok ok])

      contributor.raise_on_enumerate = true
      summary = described_class.run_once!(account)

      rows = Platform::ComponentStatus.for_kind("fake_kind").order(:component_ref)
      expect(rows.pluck(:component_ref, :verdict)).to eq([ %w[a not_measured], %w[b not_measured] ])
      expect(rows.map { |r| r.conditions.first["reason"] }).to all(eq("ContributorError"))
      # No wildcard row: there were refs to key the failure on.
      expect(Platform::ComponentStatus.exists?(component_ref: "*")).to be(false)
      expect(summary[:transitions].map { |t| t.values_at(:component_ref, :to) })
        .to contain_exactly([ "a", "not_measured" ], [ "b", "not_measured" ])
    end

    # A1 review H1, the other arm and the reason the wildcard row still exists.
    it "SURVIVES the reap it used to trigger — the rows are refreshed, not abandoned" do
      contributor = register_fake_kind(records: [ fake_record("a") ])
      described_class.run_once!(account)

      contributor.raise_on_enumerate = true
      # Three sweeps' worth of failure: before H1 the rows kept a stale `ok`
      # and were then deleted outright.
      3.times { described_class.run_once!(account) }
      described_class.run_once!(account, now: Time.current + 10.minutes)

      row = Platform::ComponentStatus.find_by(component_ref: "a")
      expect(row).to be_present
      expect(row.verdict).to eq("not_measured")
    end

    it "lands a failing ENUMERATION on one wildcard row only when the kind has no rows yet" do
      broken = register_fake_kind
      broken.raise_on_enumerate = true
      register_fake_kind(kind: "healthy_kind", records: [ fake_record("h") ])

      summary = described_class.run_once!(account)

      wildcard = Platform::ComponentStatus.find_by!(component_kind: "fake_kind",
                                                    component_ref: Platform::ComponentStatus::WILDCARD_REF)
      expect(wildcard.verdict).to eq("not_measured")
      expect(wildcard.conditions.first["reason"]).to eq("ContributorError")
      expect(summary[:kinds]["fake_kind"][:errors]).to eq(1)

      # The other kind still ran — the whole point.
      expect(Platform::ComponentStatus.find_by!(component_kind: "healthy_kind").verdict).to eq("ok")
      expect(summary[:kinds]["healthy_kind"]).to include(count: 1, errors: 0)
    end

    it "does not preserve a stale ok when it fails to look" do
      contributor = register_fake_kind(records: [ fake_record("a") ])
      described_class.run_once!(account)
      expect(Platform::ComponentStatus.find_by!(component_ref: "a").verdict).to eq("ok")

      contributor.raise_on_record = "a"
      described_class.run_once!(account)

      expect(Platform::ComponentStatus.find_by!(component_ref: "a").verdict).to eq("not_measured")
    end
  end

  # A1 review M3.
  describe "the wildcard row on recovery" do
    it "is deleted as soon as the contributor works again, not left to age out" do
      contributor = register_fake_kind
      contributor.raise_on_enumerate = true
      described_class.run_once!(account)
      expect(Platform::ComponentStatus.exists?(component_ref: "*")).to be(true)

      contributor.raise_on_enumerate = false
      contributor.records = [ fake_record("a") ]
      summary = described_class.run_once!(account)

      expect(Platform::ComponentStatus.exists?(component_ref: "*")).to be(false)
      # ...and the rollup recovers immediately rather than after a reap window.
      expect(Platform::Status::Rollup.rollup(Platform::ComponentStatus.for_account(account))[:verdict]).to eq("ok")
      # The removal is reported, so a consumer can close what it opened.
      expect(summary[:transitions].map { |t| t.values_at(:component_ref, :to, :reason) })
        .to include([ "*", nil, "Recovered" ])
    end

    it "keeps a row whose ref is legitimately '*' when the contributor enumerates it" do
      register_fake_kind(records: [ fake_record("*") ])

      described_class.run_once!(account)
      described_class.run_once!(account)

      row = Platform::ComponentStatus.find_by(component_kind: "fake_kind", component_ref: "*")
      expect(row).to be_present
      expect(row.verdict).to eq("ok")
    end
  end

  describe "a non-account-scoped kind" do
    it "writes a NULL-account row that no per-account rollup sees" do
      register_fake_kind(kind: "shared_kind", records: [ fake_record("primary") ], scoped: false)

      described_class.run_once!(account)

      row = Platform::ComponentStatus.find_by!(component_kind: "shared_kind")
      expect(row.account_id).to be_nil
      expect(Platform::ComponentStatus.shared).to contain_exactly(row)
      expect(Platform::ComponentStatus.for_account(account)).not_to include(row)

      # A second account's sweep re-writes the SAME row rather than a second one.
      described_class.run_once!(create(:account))
      expect(Platform::ComponentStatus.where(component_kind: "shared_kind").count).to eq(1)
    end
  end

  describe "the reap arm" do
    it "deletes a row not seen for three sweeps and spares one seen two sweeps ago" do
      register_fake_kind(records: [ fake_record("a") ])
      interval = described_class.sweep_interval_seconds

      gone = create(:platform_component_status, account: account, component_kind: "fake_kind",
                                                component_ref: "gone",
                                                last_seen_sweep_at: (interval * 4).seconds.ago)
      recent = create(:platform_component_status, account: account, component_kind: "fake_kind",
                                                  component_ref: "recent",
                                                  last_seen_sweep_at: (interval * 2).seconds.ago)

      summary = described_class.run_once!(account)

      expect(Platform::ComponentStatus.exists?(gone.id)).to be(false)
      expect(Platform::ComponentStatus.exists?(recent.id)).to be(true)
      expect(summary[:reaped]).to eq(1)
    end

    # A1 review M4.
    it "REPORTS a reap as a transition to nil, so a consumer can close what it opened" do
      register_fake_kind(records: [ fake_record("a") ])
      create(:platform_component_status, account: account, component_kind: "fake_kind",
                                         component_ref: "gone", verdict: "down",
                                         last_seen_sweep_at: 1.day.ago)

      summary = described_class.run_once!(account)

      removal = summary[:transitions].find { |t| t[:component_ref] == "gone" }
      expect(removal).to include(from: "down", to: nil, reason: "Reaped")
      # The row is gone, so the transition must NOT point at its id.
      expect(removal[:component_status_id]).to be_nil
    end

    it "reaps a kind that is no longer registered, by the same age rule" do
      stale = create(:platform_component_status, account: account, component_kind: "retired_kind",
                                                 last_seen_sweep_at: 1.day.ago)
      young = create(:platform_component_status, account: account, component_kind: "retired_kind",
                                                 last_seen_sweep_at: Time.current)

      described_class.run_once!(account)

      expect(Platform::ComponentStatus.exists?(stale.id)).to be(false)
      expect(Platform::ComponentStatus.exists?(young.id)).to be(true)
    end

    it "never reaps another account's rows" do
      other = create(:account)
      theirs = create(:platform_component_status, account: other, last_seen_sweep_at: 1.day.ago)

      described_class.run_once!(account)

      expect(Platform::ComponentStatus.exists?(theirs.id)).to be(true)
    end

    # A1 review M1.
    it "does NOT reap a shared row whose kind this run never swept" do
      shared = create(:platform_component_status, :shared, component_kind: "shared_kind",
                                                           component_ref: "primary",
                                                           last_seen_sweep_at: 1.day.ago)
      # A process that does not have the shared contributor registered — a
      # core-mode node, a mid-deploy skew, a to_prepare that has not run.
      register_fake_kind(records: [ fake_record("a") ])

      described_class.run_once!(account)

      expect(Platform::ComponentStatus.exists?(shared.id)).to be(true)
    end

    it "DOES reap a shared row whose kind this run swept — the other arm" do
      shared = create(:platform_component_status, :shared, component_kind: "shared_kind",
                                                           component_ref: "vanished",
                                                           last_seen_sweep_at: 1.day.ago)
      register_fake_kind(kind: "shared_kind", records: [ fake_record("primary") ], scoped: false)

      described_class.run_once!(account)

      expect(Platform::ComponentStatus.exists?(shared.id)).to be(false)
    end
  end
end

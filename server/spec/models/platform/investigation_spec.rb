# frozen_string_literal: true

require "rails_helper"

# Component status plane, increment A6 — one investigation of one component.
RSpec.describe Platform::Investigation do
  let(:account) { create(:account) }

  def build_investigation(**overrides)
    described_class.new({
      account_id: account.id,
      component_kind: "docker_host",
      component_ref: "host-1",
      trigger: described_class::TRIGGER_OPERATOR,
      status: described_class::STATUS_OPEN
    }.merge(overrides))
  end

  describe "the fingerprint" do
    it "is derived on save, never taken from the caller" do
      row = build_investigation(fingerprint: "whatever-the-caller-said")
      row.save!

      expect(row.fingerprint).to eq("docker_host:host-1")
    end

    it "follows the component when the component changes" do
      row = build_investigation
      row.save!

      row.update!(component_ref: "host-2")

      expect(row.fingerprint).to eq("docker_host:host-2")
    end

    # Deliberately NOT the component_status id: a reaped and re-created
    # component is the same thing to an operator, and must still dedupe.
    it "does not depend on the component_status row" do
      expect(described_class.fingerprint_for(component_kind: "docker_host", component_ref: "host-1"))
        .to eq("docker_host:host-1")
    end
  end

  describe "validations" do
    it "accepts each declared trigger and status" do
      described_class::TRIGGERS.each do |trigger|
        expect(build_investigation(trigger: trigger)).to be_valid, "trigger #{trigger} rejected"
      end
      described_class::STATUSES.each do |status|
        expect(build_investigation(status: status)).to be_valid, "status #{status} rejected"
      end
    end

    it "rejects a trigger or status outside them" do
      expect(build_investigation(trigger: "because_i_said_so")).not_to be_valid
      expect(build_investigation(status: "running")).not_to be_valid
    end

    it "requires a component" do
      expect(build_investigation(component_kind: nil)).not_to be_valid
      expect(build_investigation(component_ref: nil)).not_to be_valid
    end

    it "allows a shared row with no account, as a process-wide component has no tenant" do
      expect(build_investigation(account_id: nil)).to be_valid
    end
  end

  describe "the open-fingerprint rule" do
    it "refuses a second OPEN investigation of the same component" do
      build_investigation.save!

      expect { build_investigation.save! }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    # The other arm, and the reason the index is PARTIAL rather than plain: a
    # plain unique index would make the first investigation of a component
    # permanent.
    it "allows another once the first is no longer open" do
      first = build_investigation
      first.save!
      first.update!(status: described_class::STATUS_COMPLETED)

      expect { build_investigation.save! }.not_to raise_error
    end

    it "does not collide across components or accounts" do
      build_investigation.save!

      expect { build_investigation(component_ref: "host-2").save! }.not_to raise_error
      expect { build_investigation(account_id: create(:account).id).save! }.not_to raise_error
    end

    # NULL account_id is the SHARED tenant, not "no constraint". Without
    # nulls_not_distinct two open investigations of one process-wide component
    # would both be allowed, because in SQL NULL never equals NULL.
    it "still binds shared rows, whose account_id is NULL" do
      build_investigation(account_id: nil).save!

      expect { build_investigation(account_id: nil).save! }
        .to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe "#open? / #concluded?" do
    it "reads open as open and everything else as concluded" do
      expect(build_investigation(status: described_class::STATUS_OPEN)).to be_open
      (described_class::STATUSES - [ described_class::STATUS_OPEN ]).each do |status|
        expect(build_investigation(status: status)).to be_concluded, "#{status} read as open"
      end
    end
  end

  describe "#top_hypothesis" do
    it "returns the first, because the list is stored already ranked" do
      row = build_investigation(hypotheses: [ { "cause" => "winner" }, { "cause" => "runner up" } ])

      expect(row.top_hypothesis["cause"]).to eq("winner")
    end

    it "returns nil rather than raising when there are none" do
      expect(build_investigation.top_hypothesis).to be_nil
    end
  end

  describe "jsonb defaults" do
    # A default declared only on the column gives a NEW record nil and a
    # RELOADED one {}, and every caller then needs a nil guard.
    it "hands a new record and a reloaded one the same shapes" do
      row = build_investigation
      expect(row.evidence).to eq({})
      expect(row.hypotheses).to eq([])

      row.save!
      expect(row.reload.evidence).to eq({})
      expect(row.reload.hypotheses).to eq([])
    end
  end

  describe "scopes" do
    it "separates open from concluded and orders newest first" do
      old = build_investigation(component_ref: "a")
      old.save!
      old.update!(status: described_class::STATUS_COMPLETED, created_at: 2.days.ago)
      fresh = build_investigation(component_ref: "b")
      fresh.save!

      expect(described_class.open_investigations).to contain_exactly(fresh)
      expect(described_class.concluded).to contain_exactly(old)
      expect(described_class.recent_first.first).to eq(fresh)
      expect(described_class.since(1.day.ago)).to contain_exactly(fresh)
      expect(described_class.for_component("docker_host", "a")).to contain_exactly(old)
      expect(described_class.for_account(account)).to contain_exactly(old, fresh)
    end
  end
end

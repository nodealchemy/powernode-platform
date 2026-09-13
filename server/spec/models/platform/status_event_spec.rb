# frozen_string_literal: true

require "rails_helper"

# Component status plane, increment A2 — the durable transition record.
RSpec.describe Platform::StatusEvent do
  let(:account) { create(:account) }

  describe "validations" do
    it "accepts the two producer kinds and rejects anything else" do
      expect(build(:platform_status_event, account: account,
                                           kind: described_class::KIND_STATUS_CHANGED)).to be_valid
      expect(build(:platform_status_event, :down, account: account)).to be_valid

      invented = build(:platform_status_event, account: account, kind: "platform.something_happened")
      expect(invented).not_to be_valid
      expect(invented.errors[:kind]).to be_present
    end

    it "allows a NIL from_verdict for a first sighting and a NIL to_verdict for a removal" do
      # Neither nil is an accident. A first sighting has no prior verdict; a
      # removal (reap, or a recovered wildcard row) has no destination one.
      # A presence validation on either would force the producer to invent an
      # observation the platform never made.
      expect(build(:platform_status_event, :first_sighting, account: account)).to be_valid
      expect(build(:platform_status_event, :removal, account: account)).to be_valid
    end

    it "still rejects a verdict token that is not on the ladder, on both ends" do
      expect(build(:platform_status_event, account: account, to_verdict: "amber")).not_to be_valid
      expect(build(:platform_status_event, account: account, from_verdict: "amber")).not_to be_valid
    end

    it "requires the component identity and an occurrence time" do
      expect(build(:platform_status_event, account: account, component_kind: nil)).not_to be_valid
      expect(build(:platform_status_event, account: account, component_ref: nil)).not_to be_valid
      expect(build(:platform_status_event, account: account, occurred_at: nil)).not_to be_valid
    end

    it "allows a NULL account for a shared component" do
      expect(build(:platform_status_event, :shared)).to be_valid
    end
  end

  describe "surviving the component it is about" do
    it "keeps the event, and its identity, when the reap arm deletes the status row" do
      status = create(:platform_component_status, account: account,
                                                  component_kind: "fake_kind", component_ref: "a")
      event = create(:platform_status_event, account: account, component_status: status,
                                             component_kind: "fake_kind", component_ref: "a")

      status.destroy!

      event.reload
      expect(event.component_status_id).to be_nil
      # The denormalized identity is the whole reason those columns exist.
      expect(event.component_kind).to eq("fake_kind")
      expect(event.component_ref).to eq("a")
    end
  end

  describe "predicates and scopes" do
    it "distinguishes a down event from a status-changed one" do
      expect(build(:platform_status_event, :down).down_event?).to be(true)
      expect(build(:platform_status_event).down_event?).to be(false)
    end

    it "reports a first sighting only when there was no previous verdict" do
      expect(build(:platform_status_event, :first_sighting).first_sighting?).to be(true)
      expect(build(:platform_status_event).first_sighting?).to be(false)
    end

    it "reports a removal only when there is no destination verdict" do
      expect(build(:platform_status_event, :removal).removal?).to be(true)
      expect(build(:platform_status_event).removal?).to be(false)
    end

    it "separates one account's events from another's and from the shared ones" do
      other = create(:account)
      mine = create(:platform_status_event, account: account)
      theirs = create(:platform_status_event, account: other)
      shared = create(:platform_status_event, :shared)

      expect(described_class.for_account(account)).to contain_exactly(mine)
      expect(described_class.shared).to contain_exactly(shared)
      expect(described_class.for_account(other)).to contain_exactly(theirs)
    end

    it "reads one component's history newest first" do
      old = create(:platform_status_event, account: account, component_kind: "k",
                                           component_ref: "r", occurred_at: 2.hours.ago)
      new = create(:platform_status_event, account: account, component_kind: "k",
                                           component_ref: "r", occurred_at: 1.minute.ago)
      create(:platform_status_event, account: account, component_kind: "k", component_ref: "other")

      expect(described_class.for_component("k", "r").recent_first).to eq([ new, old ])
    end
  end
end

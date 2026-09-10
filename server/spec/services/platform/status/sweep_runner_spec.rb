# frozen_string_literal: true

require "rails_helper"

# Component status plane, increment A2 — the single producer.
RSpec.describe Platform::Status::SweepRunner, :platform_status do
  let(:account) { create(:account) }
  let(:emitters) { Platform::Status::Emitters }

  # Fakes and the registry/emitter snapshot come from PlatformStatusSpecSupport
  # via the :platform_status tag (A1 review L4 — these used to be top-level
  # FakeStatusRecord/FakeStatusContributor constants on Object).
  def register_kind(up: true, scoped: true, ref: "a")
    register_fake_kind(records: [ fake_record(ref, up: up) ], scoped: scoped)
  end

  describe "events" do
    it "writes exactly one status_changed row per transition and broadcasts once" do
      register_kind(up: true)

      expect { described_class.run!(account) }
        .to have_broadcasted_to(PlatformStatusChannel.account_stream(account.id)).exactly(:once)

      events = Platform::StatusEvent.all
      expect(events.count).to eq(1)
      expect(events.first).to have_attributes(
        kind: Platform::StatusEvent::KIND_STATUS_CHANGED,
        component_kind: "fake_kind",
        component_ref: "a",
        from_verdict: nil,
        to_verdict: "ok",
        account_id: account.id
      )
    end

    it "adds a component_down row on a transition to down, and only then" do
      contributor = register_kind(up: true)
      described_class.run!(account)
      expect(Platform::StatusEvent.of_kind(Platform::StatusEvent::KIND_COMPONENT_DOWN)).to be_empty

      contributor.records = [ fake_record("a", up: :down) ]
      described_class.run!(account)

      down = Platform::StatusEvent.of_kind(Platform::StatusEvent::KIND_COMPONENT_DOWN)
      expect(down.count).to eq(1)
      expect(down.first.to_verdict).to eq("down")
      # ...and the generic row is still written alongside it.
      changed = Platform::StatusEvent.of_kind(Platform::StatusEvent::KIND_STATUS_CHANGED)
                                     .where(to_verdict: "down")
      expect(changed.count).to eq(1)
      expect(down.first.occurred_at).to eq(changed.first.occurred_at)
    end

    it "writes NOTHING and broadcasts NOTHING when a sweep produces no transition" do
      register_kind(up: true)
      described_class.run!(account)
      Platform::StatusEvent.delete_all

      expect { described_class.run!(account) }.not_to have_broadcasted_to(
        PlatformStatusChannel.account_stream(account.id)
      )
      expect(Platform::StatusEvent.count).to eq(0)
    end

    it "routes a SHARED component's transition to the shared stream, not the account's" do
      register_kind(up: true, scoped: false)

      expect { described_class.run!(account) }
        .to have_broadcasted_to(PlatformStatusChannel::SHARED_STREAM).exactly(:once)

      event = Platform::StatusEvent.sole
      expect(event.account_id).to be_nil
      expect(event.payload["shared"]).to be(true)
      # The account whose sweep observed it is recorded, so the event is still
      # traceable back to the run that produced it.
      expect(event.payload["swept_account_id"]).to eq(account.id)
    end

    it "does not broadcast a shared transition on the account stream" do
      register_kind(up: true, scoped: false)

      expect { described_class.run!(account) }.not_to have_broadcasted_to(
        PlatformStatusChannel.account_stream(account.id)
      )
    end
  end

  # A1 review M4 — the event stream has to CLOSE.
  describe "a removal" do
    it "emits a status_changed event with a NIL to_verdict when a component is reaped" do
      register_kind(up: true)
      create(:platform_component_status, account: account, component_kind: "fake_kind",
                                         component_ref: "gone", verdict: "down",
                                         last_seen_sweep_at: 1.day.ago)

      described_class.run!(account)

      removal = Platform::StatusEvent.find_by!(component_ref: "gone")
      expect(removal.kind).to eq(Platform::StatusEvent::KIND_STATUS_CHANGED)
      expect(removal.from_verdict).to eq("down")
      expect(removal.to_verdict).to be_nil
      expect(removal.removal?).to be(true)
      expect(removal.payload["reason"]).to eq("Reaped")
      # The status row is gone, so the event must not point at its id.
      expect(removal.component_status_id).to be_nil
    end

    it "does NOT emit a component_down event for a removal — a vanished component did not go down" do
      register_kind(up: true)
      create(:platform_component_status, account: account, component_kind: "fake_kind",
                                         component_ref: "gone", verdict: "down",
                                         last_seen_sweep_at: 1.day.ago)

      described_class.run!(account)

      expect(Platform::StatusEvent.of_kind(Platform::StatusEvent::KIND_COMPONENT_DOWN)).to be_empty
    end

    it "broadcasts the removal with removed: true so a client can drop the row" do
      register_kind(up: true)
      create(:platform_component_status, account: account, component_kind: "fake_kind",
                                         component_ref: "gone", verdict: "down",
                                         last_seen_sweep_at: 1.day.ago)

      expect { described_class.run!(account) }
        .to have_broadcasted_to(PlatformStatusChannel.account_stream(account.id))
        .with(hash_including(removed: true, to_verdict: nil, reason: "Reaped"))
    end
  end

  describe "guards" do
    it "skips with reason kill_switch when the account is suspended, writing nothing" do
      register_kind(up: true)
      account.suspend_ai!

      result = nil
      expect { result = described_class.run!(account) }.not_to have_broadcasted_to(
        PlatformStatusChannel.account_stream(account.id)
      )

      expect(result).to include(skipped: true, reason: "kill_switch")
      expect(Platform::StatusEvent.count).to eq(0)
      # The sweep never ran at all: no status rows either.
      expect(Platform::ComponentStatus.count).to eq(0)
    end

    it "runs once the kill switch is lifted — the other arm" do
      register_kind(up: true)
      account.suspend_ai!
      described_class.run!(account)
      account.resume_ai!

      result = described_class.run!(account)

      expect(result[:skipped]).to be(false)
      expect(Platform::StatusEvent.count).to eq(1)
    end

    it "skips with reason standby when the control-plane role says this plane is not active" do
      register_kind(up: true)
      allow(described_class).to receive(:control_plane_active?).and_return(false)

      result = described_class.run!(account)

      expect(result).to include(skipped: true, reason: "standby")
      expect(Platform::StatusEvent.count).to eq(0)
      expect(Platform::ComponentStatus.count).to eq(0)
    end

    describe ".control_plane_active?" do
      it "is active in core mode (no provider registered)" do
        allow(::Powernode::ExtensionRegistry).to receive(:provider)
          .with(described_class::CONTROL_PLANE_ROLE_PROVIDER).and_return(nil)

        expect(described_class.control_plane_active?).to be(true)
      end

      it "asks a registered provider, and believes both of its answers" do
        active = instance_double("role", active?: true)
        standby = instance_double("role", active?: false)

        allow(::Powernode::ExtensionRegistry).to receive(:provider)
          .with(described_class::CONTROL_PLANE_ROLE_PROVIDER).and_return(active)
        expect(described_class.control_plane_active?).to be(true)

        allow(::Powernode::ExtensionRegistry).to receive(:provider)
          .with(described_class::CONTROL_PLANE_ROLE_PROVIDER).and_return(standby)
        expect(described_class.control_plane_active?).to be(false)
      end

      it "FAILS TOWARD STANDBY when the provider raises" do
        exploding = instance_double("role")
        allow(exploding).to receive(:active?).and_raise("corosync unreachable")
        allow(::Powernode::ExtensionRegistry).to receive(:provider)
          .with(described_class::CONTROL_PLANE_ROLE_PROVIDER).and_return(exploding)

        # A safety device that reports "active" when confused is worse than none.
        expect(described_class.control_plane_active?).to be(false)
      end
    end
  end

  describe "the mirror seam" do
    it "hands each transition to every registered emitter, after the events are written" do
      register_kind(up: true)
      seen = []
      emitters.register(:mirror) do |transition:, events:|
        seen << [ transition[:component_ref], transition[:to], events.map(&:kind), events.all?(&:persisted?) ]
      end

      described_class.run!(account)

      expect(seen).to eq([ [ "a", "ok", [ Platform::StatusEvent::KIND_STATUS_CHANGED ], true ] ])
    end

    it "keeps the event rows and the other emitters when one emitter raises" do
      register_kind(up: true)
      reached = false
      emitters.register(:explodes) { |**| raise "mirror exploded" }
      emitters.register(:still_runs) { |**| reached = true }

      expect { described_class.run!(account) }.not_to raise_error

      expect(reached).to be(true)
      expect(Platform::StatusEvent.count).to eq(1)
    end

    it "calls no emitter when there is no transition" do
      register_kind(up: true)
      described_class.run!(account)

      called = 0
      emitters.register(:counter) { |**| called += 1 }
      described_class.run!(account)

      expect(called).to eq(0)
    end
  end

  describe "the returned summary" do
    it "reports the sweep's own totals plus how many events it wrote" do
      register_kind(up: :down)

      result = described_class.run!(account)

      expect(result[:skipped]).to be(false)
      expect(result[:transitions].size).to eq(1)
      # status_changed + component_down.
      expect(result[:events_written]).to eq(2)
      expect(result[:kinds]["fake_kind"]).to include(count: 1)
    end
  end
end

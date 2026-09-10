# frozen_string_literal: true

require "rails_helper"

# Component status plane, increment A7 — core escalation: the step that makes a
# verdict reach a person.
RSpec.describe Platform::Status::Escalation do
  let(:account) { create(:account) }

  # `platform.status.read` is A4's permission and is not in the catalog yet, so
  # `User.with_permission` resolves it to `system.admin` holders. That is the
  # documented behaviour of an undefined permission on this platform, and it is
  # why this is the operator in every example below.
  let!(:operator) { create(:user, account: account, permissions: [ "system.admin" ]) }

  # Same account, no grants at all: the negative arm of "who is notified".
  let!(:bystander) { create(:user, account: account, permissions: []) }

  def condition(reason:, status: false, severity: "down", transition_at: Time.current)
    {
      "type" => "Reachable", "status" => status, "reason" => reason,
      "message" => "for the spec", "severity" => severity, "evidence" => {},
      "last_transition_at" => transition_at
    }
  end

  def row_for(verdict, conditions: [], **overrides)
    create(:platform_component_status,
           account: account, component_kind: "docker_host", verdict: verdict,
           display_name: "web-1", conditions: conditions, **overrides)
  end

  def transition_to(verdict, row:)
    {
      component_status_id: row&.id, account_id: row&.account_id,
      component_kind: row&.component_kind, component_ref: row&.component_ref,
      from: Platform::ComponentStatus::OK, to: verdict, at: Time.current
    }
  end

  def notifications_for(user) = Notification.where(user_id: user.id)

  describe "a transition to down" do
    let(:row) { row_for(Platform::ComponentStatus::DOWN, conditions: [ condition(reason: "ConnectionError") ]) }

    it "notifies the operator, critically, and names the reason token" do
      created = described_class.run!(transition: transition_to("down", row: row), events: [])

      expect(created.size).to eq(1)
      notification = notifications_for(operator).sole
      expect(notification.severity).to eq("critical")
      expect(notification.notification_type).to eq("system_alert")
      expect(notification.category).to eq("system")
      expect(notification.title).to include("web-1")
      expect(notification.message).to include("ConnectionError")
      expect(notification.metadata["component_kind"]).to eq("docker_host")
      expect(notification.metadata["component_ref"]).to eq(row.component_ref)
    end

    it "does not notify an account member who holds no permission" do
      described_class.run!(transition: transition_to("down", row: row), events: [])

      expect(notifications_for(bystander)).to be_empty
    end

    it "does not notify another account's operator" do
      other = create(:account)
      other_operator = create(:user, account: other, permissions: [ "system.admin" ])

      described_class.run!(transition: transition_to("down", row: row), events: [])

      expect(notifications_for(other_operator)).to be_empty
    end

    it "stakes the claim on the row" do
      expect { described_class.run!(transition: transition_to("down", row: row), events: []) }
        .to change { row.reload.last_notified_at }.from(nil)
    end
  end

  describe "rate limiting" do
    let(:row) { row_for(Platform::ComponentStatus::DOWN, conditions: [ condition(reason: "ConnectionError") ]) }

    it "notifies once per row per interval, and again once the interval has passed" do
      described_class.run!(transition: transition_to("down", row: row), events: [])
      expect(notifications_for(operator).count).to eq(1)

      # Inside the interval: nothing new.
      inside = Time.current + (described_class.notify_interval_minutes - 1).minutes
      described_class.run!(transition: transition_to("down", row: row.reload), events: [], now: inside)
      expect(notifications_for(operator).count).to eq(1)

      # Past it: a second notification, because the outage is still real.
      outside = Time.current + (described_class.notify_interval_minutes + 1).minutes
      described_class.run!(transition: transition_to("down", row: row.reload), events: [], now: outside)
      expect(notifications_for(operator).count).to eq(2)
    end

    it "reads the interval from SiteSetting rather than a constant" do
      SiteSetting.set(described_class::NOTIFY_INTERVAL_SETTING, 5, setting_type: "integer")

      expect(described_class.notify_interval_minutes).to eq(5)

      described_class.run!(transition: transition_to("down", row: row), events: [])
      later = Time.current + 6.minutes
      described_class.run!(transition: transition_to("down", row: row.reload), events: [], now: later)

      expect(notifications_for(operator).count).to eq(2)
    end

    it "falls back to the default for a blank or non-positive setting" do
      SiteSetting.set(described_class::NOTIFY_INTERVAL_SETTING, 0, setting_type: "integer")

      expect(described_class.notify_interval_minutes)
        .to eq(described_class::DEFAULT_NOTIFY_INTERVAL_MINUTES)
    end
  end

  describe "a recovery" do
    let(:row) do
      row_for(Platform::ComponentStatus::OK, conditions: [ condition(reason: "Connected", status: true, severity: nil) ],
                                             last_notified_at: 2.minutes.ago)
    end

    it "notifies nobody" do
      described_class.run!(transition: transition_to("ok", row: row), events: [])

      expect(Notification.count).to eq(0)
    end

    # The decision, asserted: the interval must not swallow the NEXT outage.
    it "clears the claim so the next outage notifies immediately" do
      described_class.run!(transition: transition_to("ok", row: row), events: [])
      expect(row.reload.last_notified_at).to be_nil

      row.update!(verdict: Platform::ComponentStatus::DOWN,
                  conditions: [ condition(reason: "ConnectionError") ])
      described_class.run!(transition: transition_to("down", row: row), events: [])

      expect(notifications_for(operator).count).to eq(1)
    end

    it "would have swallowed it without the reset" do
      # The counterfactual, so the reset is provably load-bearing: a row whose
      # claim is still fresh does NOT notify on a down transition.
      still_claimed = row_for(Platform::ComponentStatus::DOWN,
                              conditions: [ condition(reason: "ConnectionError") ],
                              last_notified_at: 2.minutes.ago)

      described_class.run!(transition: transition_to("down", row: still_claimed), events: [])

      expect(notifications_for(operator)).to be_empty
    end
  end

  describe "transitions that must not notify" do
    it "ignores a removal, which carries no component and no verdict" do
      reaped = { component_status_id: nil, account_id: account.id, component_kind: "docker_host",
                 component_ref: "gone", from: Platform::ComponentStatus::DOWN, to: nil, at: Time.current }

      expect { described_class.run!(transition: reaped, events: []) }.not_to raise_error
      expect(Notification.count).to eq(0)
    end

    it "ignores a transition whose row has already been deleted" do
      row = row_for(Platform::ComponentStatus::DOWN, conditions: [ condition(reason: "ConnectionError") ])
      transition = transition_to("down", row: row)
      row.destroy!

      expect(described_class.run!(transition: transition, events: [])).to eq([])
      expect(Notification.count).to eq(0)
    end

    it "does not page on the transition INTO degraded — that is dwell's job" do
      row = row_for(Platform::ComponentStatus::DEGRADED, conditions: [ condition(reason: "Disconnected", severity: "degraded") ])

      described_class.run!(transition: transition_to("degraded", row: row), events: [])

      expect(Notification.count).to eq(0)
    end

    it "does not page on held, progressing or not_measured" do
      %w[held progressing not_measured].each do |verdict|
        row = row_for(verdict, conditions: [ condition(reason: "Cordoned", status: true, severity: nil) ])
        described_class.run!(transition: transition_to(verdict, row: row), events: [])
      end

      expect(Notification.count).to eq(0)
    end

    it "notifies nobody for a shared row, rather than picking a tenant" do
      shared = create(:platform_component_status, :shared, :down,
                      component_kind: "provider_circuit_breaker",
                      conditions: [ condition(reason: "BreakerOpen") ])

      described_class.run!(transition: transition_to("down", row: shared), events: [])

      expect(Notification.count).to eq(0)
      expect(shared.reload.last_notified_at).to be_nil
    end
  end

  describe ".sweep! — degraded dwell" do
    let(:threshold) { described_class.degraded_after_minutes }

    it "says nothing about a component that only just went degraded" do
      row_for(Platform::ComponentStatus::DEGRADED,
              conditions: [ condition(reason: "Disconnected", severity: "degraded",
                                      transition_at: (threshold - 2).minutes.ago) ])

      expect(described_class.sweep!(account)).to eq([])
      expect(Notification.count).to eq(0)
    end

    it "warns once a component has been degraded past the threshold" do
      row = row_for(Platform::ComponentStatus::DEGRADED,
                    conditions: [ condition(reason: "Disconnected", severity: "degraded",
                                            transition_at: (threshold + 5).minutes.ago) ])

      created = described_class.sweep!(account)

      expect(created.size).to eq(1)
      notification = notifications_for(operator).sole
      expect(notification.severity).to eq("warning")
      expect(notification.message).to include("degraded")
      expect(notification.message).to include("Disconnected")
      expect(row.reload.last_notified_at).to be_present
    end

    it "respects the same per-row interval as a down transition" do
      row_for(Platform::ComponentStatus::DEGRADED,
              conditions: [ condition(reason: "Disconnected", severity: "degraded",
                                      transition_at: (threshold + 5).minutes.ago) ])

      described_class.sweep!(account)
      described_class.sweep!(account)

      expect(notifications_for(operator).count).to eq(1)
    end

    it "reads the dwell from SiteSetting rather than a constant" do
      SiteSetting.set(described_class::DEGRADED_AFTER_SETTING, 120, setting_type: "integer")
      row_for(Platform::ComponentStatus::DEGRADED,
              conditions: [ condition(reason: "Disconnected", severity: "degraded",
                                      transition_at: 30.minutes.ago) ])

      expect(described_class.degraded_after_minutes).to eq(120)
      expect(described_class.sweep!(account)).to eq([])
    end

    it "leaves ok, down and held rows alone" do
      row_for(Platform::ComponentStatus::OK,
              conditions: [ condition(reason: "Connected", status: true, severity: nil,
                                      transition_at: 1.day.ago) ])
      row_for(Platform::ComponentStatus::DOWN,
              conditions: [ condition(reason: "ConnectionError", transition_at: 1.day.ago) ])
      row_for(Platform::ComponentStatus::HELD,
              conditions: [ condition(reason: "Maintenance", status: true, severity: nil,
                                      transition_at: 1.day.ago) ])

      expect(described_class.sweep!(account)).to eq([])
    end

    it "does not sweep another account's rows" do
      other = create(:account)
      create(:platform_component_status, :degraded, account: other, component_kind: "docker_host",
                                                    conditions: [ condition(reason: "Disconnected", severity: "degraded",
                                                                            transition_at: 1.day.ago) ])

      expect(described_class.sweep!(account)).to eq([])
    end

    # A dwell we cannot establish is not a dwell we may assume has elapsed.
    it "says nothing about a row whose conditions do not explain its verdict" do
      row_for(Platform::ComponentStatus::DEGRADED, conditions: [])

      expect(described_class.sweep!(account)).to eq([])
    end

    it "does nothing without an account" do
      expect(described_class.sweep!(nil)).to eq([])
    end
  end

  describe "the emitter wiring" do
    around do |example|
      saved = Platform::Status::Emitters.handlers.dup
      Platform::Status::Emitters.reset!
      example.run
    ensure
      Platform::Status::Emitters.reset!
      saved.each { |name, handler| Platform::Status::Emitters.register(name, handler) }
    end

    # Executed, not grepped: loading the initializer appends its `to_prepare`
    # block, and calling that block is the boot path. Both arms — no emitter
    # before, the `:escalation` emitter after.
    it "registers the escalation emitter when its to_prepare block runs" do
      blocks = Rails.application.config.to_prepare_blocks
      before_count = blocks.size

      load Rails.root.join("config/initializers/platform_status_escalation.rb").to_s
      expect(blocks.size).to eq(before_count + 1), "the initializer registered no to_prepare block"

      expect(Platform::Status::Emitters.registered?(:escalation)).to be(false)

      blocks.last.call

      expect(Platform::Status::Emitters.registered?(:escalation)).to be(true)
    ensure
      blocks.pop while blocks.size > before_count
    end

    it "reaches escalation through the seam the runner actually calls" do
      row = row_for(Platform::ComponentStatus::DOWN, conditions: [ condition(reason: "ConnectionError") ])
      Platform::Status::Emitters.register(:escalation) do |transition:, events:|
        described_class.run!(transition: transition, events: events)
      end

      Platform::Status::Emitters.notify(transition: transition_to("down", row: row), events: [])

      expect(notifications_for(operator).count).to eq(1)
    end

    it "cannot take the sweep down when the notification subsystem fails" do
      row = row_for(Platform::ComponentStatus::DOWN, conditions: [ condition(reason: "ConnectionError") ])
      allow(Notification).to receive(:create_for_user).and_raise(StandardError, "notifications are down")
      Platform::Status::Emitters.register(:escalation) do |transition:, events:|
        described_class.run!(transition: transition, events: events)
      end

      expect { Platform::Status::Emitters.notify(transition: transition_to("down", row: row), events: []) }
        .not_to raise_error
      # The claim is still staked, so a broken subsystem does not become a
      # retry loop on every sweep.
      expect(row.reload.last_notified_at).to be_present
    end
  end
end

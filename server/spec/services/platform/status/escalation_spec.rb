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

  # E8 — Escalation fans out through Monitoring::AlertingService under the
  # SAME last_notified_at claim, and the channels fire whether or not anyone in
  # the tenant holds the permission (lead ruling).
  describe "external channel fan-out (E8)" do
    let(:slack_url) { "https://hooks.slack.com/services/T0/B0/escalation-planted" }

    before { AdminSetting.where(key: Security::SecretStore::SETTING_KEY).delete_all }

    def degraded_past_dwell(target_account = account)
      create(:platform_component_status,
             account: target_account, component_kind: "docker_host", verdict: Platform::ComponentStatus::DEGRADED,
             display_name: "web-1",
             conditions: [ condition(reason: "Disconnected", severity: "degraded",
                                     transition_at: (described_class.degraded_after_minutes + 5).minutes.ago) ])
    end

    def configure_slack
      Monitoring::AlertChannels.write_secret!("slack_webhook_url", slack_url)
      stub_request(:post, slack_url).to_return(status: 200)
    end

    # The lead's oracle, on dwell: A7 pages nobody on ENTRY to degraded.
    it "a sweep past dwell sends one POST and one Notification" do
      configure_slack
      degraded_past_dwell

      described_class.sweep!(account)

      expect(a_request(:post, slack_url)).to have_been_made.once
      expect(notifications_for(operator).count).to eq(1)
    end

    it "a second sweep inside the interval sends neither" do
      configure_slack
      degraded_past_dwell

      described_class.sweep!(account)
      described_class.sweep!(account, now: Time.current + 1.minute)

      expect(a_request(:post, slack_url)).to have_been_made.once
      expect(notifications_for(operator).count).to eq(1)
    end

    it "a shared row going down POSTs with zero Notifications, and once per interval" do
      configure_slack
      shared = create(:platform_component_status, :shared, :down,
                      component_kind: "provider_circuit_breaker",
                      conditions: [ condition(reason: "BreakerOpen") ])

      described_class.run!(transition: transition_to("down", row: shared), events: [])
      described_class.run!(transition: transition_to("down", row: shared.reload), events: [])

      expect(a_request(:post, slack_url)).to have_been_made.once
      expect(Notification.count).to eq(0)
      expect(shared.reload.last_notified_at).to be_present
    end

    it "an account with no permissioned user still POSTs" do
      configure_slack
      lonely = create(:account)
      create(:user, account: lonely, permissions: [])
      degraded_past_dwell(lonely)

      described_class.sweep!(lonely)

      expect(a_request(:post, slack_url)).to have_been_made.once
      expect(Notification.where(user_id: lonely.users.select(:id)).count).to eq(0)
    end

    it "sends row coordinates only: no display name, no account" do
      configure_slack
      row = degraded_past_dwell

      described_class.sweep!(account)

      expect(a_request(:post, slack_url).with { |req|
        body = req.body
        body.include?(row.component_ref) && !body.include?("web-1") && !body.include?(account.id.to_s)
      }).to have_been_made.once
    end

    # Asserted through WebMock's request registry, which records every request
    # whether or not it was stubbed — so "no POST" is a fact about the wire,
    # not about a double someone forgot to set up.
    it "with no channel configured, writes only the Notification and POSTs nothing" do
      degraded_past_dwell

      described_class.sweep!(account)

      expect(notifications_for(operator).count).to eq(1)
      expect(a_request(:post, /.*/)).not_to have_been_made
    end

    it "a deliverer that raises costs neither the Notification nor the claim" do
      row = degraded_past_dwell
      allow_any_instance_of(Monitoring::AlertingService).to receive(:send_alert).and_raise("channel exploded")

      created = described_class.sweep!(account)

      expect(created.size).to eq(1)
      expect(notifications_for(operator).count).to eq(1)
      # Without the claim, a broken channel becomes a retry on every sweep.
      expect(row.reload.last_notified_at).to be_present
    end

    # Lead ruling: the claim is staked on ANY attempt, a raising deliverer
    # included. A shared row has nobody to notify in-app, so the claim rests on
    # the attempt alone. This is the example that can see that; the one above
    # stakes the claim through its recipient whatever the deliverer does.
    it "a deliverer that raises on a shared row still stakes the one claim, and logs no message" do
      shared = create(:platform_component_status, :shared, :down,
                      component_kind: "provider_circuit_breaker",
                      conditions: [ condition(reason: "BreakerOpen") ])
      attempts = 0
      allow_any_instance_of(Monitoring::AlertingService).to receive(:send_alert) do
        attempts += 1
        raise "channel exploded at #{slack_url}"
      end
      io = StringIO.new
      capture = ActiveSupport::Logger.new(io)
      Rails.logger.broadcast_to(capture)

      described_class.run!(transition: transition_to("down", row: shared), events: [])
      described_class.run!(transition: transition_to("down", row: shared.reload), events: [])

      expect(attempts).to eq(1)
      expect(shared.reload.last_notified_at).to be_present
      expect(Notification.count).to eq(0)
      expect(io.string).to include("channel delivery failed: RuntimeError")
      expect(io.string).not_to include("escalation-planted")
    ensure
      Rails.logger.stop_broadcasting_to(capture) if capture
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

    # A7 review F2. The load-bearing line is the verdict filter in
    # `degraded_since`: without it an OLD, healthy condition drags the dwell
    # backwards and pages about an outage that started two minutes ago. Every
    # other example here carries exactly one condition, so none of them can
    # tell the filtered implementation from the unfiltered one.
    describe "the dwell counts only conditions that argue for the CURRENT verdict" do
      let(:threshold) { described_class.degraded_after_minutes }

      it "stays silent when the degrading condition is recent and an old one is healthy" do
        row_for(Platform::ComponentStatus::DEGRADED, conditions: [
          condition(reason: "Reachable", status: true, severity: nil,
                    transition_at: (threshold + 60).minutes.ago),
          condition(reason: "SyncStale", severity: "degraded",
                    transition_at: (threshold - 2).minutes.ago)
        ])

        expect(described_class.sweep!(account)).to eq([])
      end

      # Swap the two timestamps and nothing else. If the filter were removed
      # both examples would notify, so the pair is what makes either mean
      # anything.
      it "notifies when the degrading condition is the old one" do
        row_for(Platform::ComponentStatus::DEGRADED, conditions: [
          condition(reason: "Reachable", status: true, severity: nil,
                    transition_at: (threshold - 2).minutes.ago),
          condition(reason: "SyncStale", severity: "degraded",
                    transition_at: (threshold + 60).minutes.ago)
        ])

        expect(described_class.sweep!(account).size).to eq(1)
        expect(notifications_for(operator).sole.message).to include("SyncStale")
      end
    end

    # A7 review F5. `Condition.build` inherits `last_transition_at` while a
    # condition's STATUS is unchanged and never looks at severity, so a
    # condition that was `false` at severity `down` and softened to `degraded`
    # keeps its original timestamp. Reading dwell off that alone reports a
    # component that has been degraded for one minute as degraded for hours.
    describe "dwell after an improvement from down to degraded" do
      let(:threshold) { described_class.degraded_after_minutes }

      def softened_row
        row_for(Platform::ComponentStatus::DEGRADED, conditions: [
          condition(reason: "Disconnected", severity: "degraded",
                    transition_at: (threshold + 180).minutes.ago)
        ])
      end

      it "counts from the entry INTO degraded, not from the older down" do
        row = softened_row
        create(:platform_status_event, account: account,
                                       component_kind: row.component_kind,
                                       component_ref: row.component_ref,
                                       component_status: row,
                                       from_verdict: Platform::ComponentStatus::DOWN,
                                       to_verdict: Platform::ComponentStatus::DEGRADED,
                                       occurred_at: 1.minute.ago)

        expect(described_class.sweep!(account)).to eq([])
      end

      # The other arm: the same row with the entry event far enough back still
      # notifies, and the message states the shorter, true dwell rather than
      # the inherited one.
      it "still notifies once the entry itself is past the dwell" do
        row = softened_row
        create(:platform_status_event, account: account,
                                       component_kind: row.component_kind,
                                       component_ref: row.component_ref,
                                       component_status: row,
                                       from_verdict: Platform::ComponentStatus::DOWN,
                                       to_verdict: Platform::ComponentStatus::DEGRADED,
                                       occurred_at: (threshold + 5).minutes.ago)

        expect(described_class.sweep!(account).size).to eq(1)
        expect(notifications_for(operator).sole.message)
          .to include("for #{threshold + 5} minutes")
      end

      # And the fallback: events are pruned on a retention window, so with no
      # entry event the conditions are all there is. That answer is
      # pessimistic, not silent — a long-degraded component must not go
      # unnoticed because its entry event aged out.
      it "falls back to the conditions when no entry event survives" do
        softened_row

        expect(described_class.sweep!(account).size).to eq(1)
      end
    end
  end

  # A7 review F4. Design §5.4: fleet kinds keep their own lane's escalation, so
  # A7 must not page a second time about an outage that lane already claimed.
  describe "kinds that decline core escalation" do
    let(:kind) { "fleet_thing" }

    def register(escalates:)
      contributor = Class.new(Platform::Status::Contributor) do
        define_method(:kind) { "fleet_thing" }
        define_method(:escalates?) { escalates }
      end.new
      Platform::Status::Registry.register(kind, contributor)
    end

    after { Platform::Status::Registry.unregister(kind) }

    def fleet_row(verdict, conditions:)
      create(:platform_component_status, account: account, component_kind: kind,
                                         verdict: verdict, display_name: "node-7",
                                         conditions: conditions)
    end

    it "notifies nobody and stakes NO claim when the contributor says false" do
      register(escalates: false)
      row = fleet_row(Platform::ComponentStatus::DOWN, conditions: [ condition(reason: "ConnectionError") ])

      expect(described_class.run!(transition: transition_to("down", row: row), events: [])).to eq([])
      expect(notifications_for(operator).count).to eq(0)
      # The claim matters as much as the notification: staking one here would
      # silently suppress the owning lane's own escalation.
      expect(row.reload.last_notified_at).to be_nil
    end

    it "skips the same kind in the degraded sweep too" do
      register(escalates: false)
      fleet_row(Platform::ComponentStatus::DEGRADED, conditions: [
        condition(reason: "Disconnected", severity: "degraded", transition_at: 1.day.ago)
      ])

      expect(described_class.sweep!(account)).to eq([])
    end

    # The other arm, twice over: a contributor answering true escalates, and so
    # does a kind with no contributor registered at all. The default has to
    # fail OPEN — the opposite is a component that breaks and pages nobody.
    it "escalates when the contributor says true" do
      register(escalates: true)
      row = fleet_row(Platform::ComponentStatus::DOWN, conditions: [ condition(reason: "ConnectionError") ])

      expect(described_class.run!(transition: transition_to("down", row: row), events: []).size).to eq(1)
    end

    it "escalates an unregistered kind" do
      expect(Platform::Status::Registry.registered?(kind)).to be(false)
      row = fleet_row(Platform::ComponentStatus::DOWN, conditions: [ condition(reason: "ConnectionError") ])

      expect(described_class.run!(transition: transition_to("down", row: row), events: []).size).to eq(1)
    end

    it "escalates when the predicate itself raises" do
      contributor = Class.new(Platform::Status::Contributor) do
        define_method(:kind) { "fleet_thing" }
        define_method(:escalates?) { raise "contributor exploded" }
      end.new
      Platform::Status::Registry.register(kind, contributor)
      row = fleet_row(Platform::ComponentStatus::DOWN, conditions: [ condition(reason: "ConnectionError") ])

      expect(described_class.run!(transition: transition_to("down", row: row), events: []).size).to eq(1)
    end

    it "escalates a contributor that predates the predicate" do
      legacy = Object.new
      def legacy.each_component(_account) = nil
      Platform::Status::Registry.register(kind, legacy)
      row = fleet_row(Platform::ComponentStatus::DOWN, conditions: [ condition(reason: "ConnectionError") ])

      expect(described_class.run!(transition: transition_to("down", row: row), events: []).size).to eq(1)
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

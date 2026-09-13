# frozen_string_literal: true

require "rails_helper"

# Component status plane, increment A3 — the `docker_host` core contributor.
RSpec.describe Platform::Status::Contributors::DockerHost do
  subject(:contributor) { described_class.new }

  let(:account) { create(:account) }
  let(:unknown_reason) { Platform::Status::Contributors::EnumConditions::UNKNOWN_REASON }

  def only_condition(host) = contributor.conditions_for(host).first

  def enumerate(for_account)
    [].tap { |acc| contributor.each_component(for_account) { |record| acc << record } }
  end

  describe "the contract" do
    it "answers the registry key and is account scoped" do
      expect(described_class::KIND).to eq("docker_host")
      expect(contributor.kind).to eq("docker_host")
      expect(contributor.account_scoped?).to be(true)
    end

    it "presents a string icon name, a label and a group order" do
      expect(contributor.presentation).to eq(
        "icon" => "Container", "label" => "Docker Host", "group_order" => 30
      )
    end

    it "links to the host dashboard and declares no A3 actions" do
      host = create(:devops_docker_host, account: account)

      expect(contributor.links_for(host))
        .to eq([ { "label" => "Docker host", "path" => "/app/devops/docker/#{host.id}" } ])
      expect(contributor.actions_for(host)).to eq([])
    end

    it "reports the docker daemon version as the observed generation" do
      host = build(:devops_docker_host, docker_version: "27.1.2")

      expect(contributor.observed_generation_for(host)).to eq("27.1.2")
    end
  end

  describe "status coverage" do
    it "maps every value of Devops::DockerHost::STATUSES" do
      expect(contributor.mapped_values(described_class::STATUS_CONDITIONS))
        .to eq(::Devops::DockerHost::STATUSES.sort)
    end

    it "gives every status a reason that is not UnknownStatus" do
      host = build(:devops_docker_host, account: account)

      ::Devops::DockerHost::STATUSES.each do |status|
        host.status = status
        condition = only_condition(host)

        expect(condition).not_to be_nil, "no condition for #{status}"
        expect(condition["reason"]).not_to eq(unknown_reason), "#{status} fell through to UnknownStatus"
      end
    end

    it "reports an out-of-band status as unknown/UnknownStatus, never ok" do
      host = build(:devops_docker_host, account: account, status: "connected")
      host.status = "quarantined"

      condition = only_condition(host)

      expect(condition["type"]).to eq("Connected")
      expect(condition["status"]).to eq(Platform::Status::Condition::UNKNOWN)
      expect(condition["reason"]).to eq(unknown_reason)
      expect(condition["evidence"]["unmapped_value"]).to eq("quarantined")
      expect(Platform::Status::Condition.verdict_for_set([ condition ]))
        .to eq(Platform::ComponentStatus::NOT_MEASURED)
    end

    it "derives the whole ladder from the status column" do
      # Freshly synced, so the freshness condition is `ok` and the status
      # column is the only thing moving the verdict.
      host = build(:devops_docker_host, account: account, last_synced_at: Time.current)

      {
        "connected" => Platform::ComponentStatus::OK,
        "maintenance" => Platform::ComponentStatus::HELD,
        "pending" => Platform::ComponentStatus::PROGRESSING,
        "disconnected" => Platform::ComponentStatus::DEGRADED,
        "error" => Platform::ComponentStatus::DOWN
      }.each do |status, verdict|
        host.status = status

        expect(Platform::Status::Condition.verdict_for_set(contributor.conditions_for(host)))
          .to eq(verdict), "status=#{status}"
      end
    end

    it "carries the raw fields the reason came from as evidence" do
      host = build(:devops_docker_host, account: account, status: "error",
                                        consecutive_failures: 5, container_count: 12,
                                        environment: "production")

      evidence = only_condition(host)["evidence"]

      expect(evidence).to include(
        "status" => "error",
        "consecutive_failures" => 5,
        "container_count" => 12,
        "environment" => "production"
      )
    end
  end

  describe "freshness" do
    let(:interval) { 60 }

    def fresh_condition(host)
      contributor.conditions_for(host).find { |c| c["type"] == "Fresh" }
    end

    it "is ok inside twice the host's own sync interval and stale past it" do
      host = build(:devops_docker_host, account: account, status: "connected",
                                        auto_sync: true, sync_interval_seconds: interval,
                                        last_synced_at: (interval * 2 - 5).seconds.ago)

      expect(fresh_condition(host)["status"]).to be(true)
      expect(fresh_condition(host)["reason"]).to eq("SyncFresh")

      host.last_synced_at = (interval * 2 + 5).seconds.ago

      expect(fresh_condition(host)["status"]).to be(false)
      expect(fresh_condition(host)["reason"]).to eq("SyncStale")
      expect(fresh_condition(host)["evidence"]).to include(
        "sync_interval_seconds" => interval, "stale_after_seconds" => interval * 2
      )
    end

    it "derives the window from THIS host's interval, not a constant" do
      slow = build(:devops_docker_host, account: account, status: "connected",
                                        auto_sync: true, sync_interval_seconds: 600,
                                        last_synced_at: 5.minutes.ago)
      quick = build(:devops_docker_host, account: account, status: "connected",
                                         auto_sync: true, sync_interval_seconds: 60,
                                         last_synced_at: 5.minutes.ago)

      expect(fresh_condition(slow)["reason"]).to eq("SyncFresh")
      expect(fresh_condition(quick)["reason"]).to eq("SyncStale")
    end

    it "turns a connected-but-unheard-from host amber, which the status column cannot" do
      host = build(:devops_docker_host, account: account, status: "connected",
                                        auto_sync: true, sync_interval_seconds: interval,
                                        last_synced_at: 1.hour.ago)

      expect(Platform::Status::Condition.verdict_for_set(contributor.conditions_for(host)))
        .to eq(Platform::ComponentStatus::DEGRADED)
    end

    it "reports NeverSynced when auto-sync is on and nothing has ever synced" do
      host = build(:devops_docker_host, account: account, status: "connected",
                                        auto_sync: true, last_synced_at: nil)

      expect(fresh_condition(host)["status"]).to eq(Platform::Status::Condition::UNKNOWN)
      expect(fresh_condition(host)["reason"]).to eq("NeverSynced")
    end

    it "makes no freshness claim at all when auto-sync is off" do
      host = build(:devops_docker_host, account: account, status: "connected",
                                        auto_sync: false, last_synced_at: 1.hour.ago)

      expect(fresh_condition(host)).to be_nil
      expect(Platform::Status::Condition.verdict_for_set(contributor.conditions_for(host)))
        .to eq(Platform::ComponentStatus::OK)
    end

    # A7 review F7. `devops_docker_hosts.auto_sync` is `default: true` and
    # NULLABLE with no model validation, and `auto_sync?` answers false for
    # NULL — which would skip the check on a host nobody is syncing. That
    # failure is BLIND: the host just looks fine.
    describe "auto_sync IS NULL" do
      it "is read as the column default, not as a deliberate opt-out" do
        expect(Devops::DockerHost.column_defaults["auto_sync"]).to be(true),
                                                                  "the column default moved; this rule follows it"

        host = build(:devops_docker_host, account: account, status: "connected",
                                          auto_sync: nil, sync_interval_seconds: interval,
                                          last_synced_at: 1.hour.ago)

        expect(fresh_condition(host)).not_to be_nil
        expect(fresh_condition(host)["reason"]).to eq("SyncStale")
      end

      # The other arm, and the distinction the whole rule turns on: an explicit
      # false is still an operator's choice and still produces no claim.
      it "does not swallow an explicit false" do
        host = build(:devops_docker_host, account: account, status: "connected",
                                          auto_sync: false, sync_interval_seconds: interval,
                                          last_synced_at: 1.hour.ago)

        expect(fresh_condition(host)).to be_nil
      end
    end

    # A7 review F6. `nil.to_i` is 0, so a missing interval made `stale_after`
    # zero and `age <= 0` false for any positive age: permanently SyncStale,
    # i.e. permanently degraded, for a reason no operator can act on.
    describe "a missing or non-positive sync interval" do
      it "is unknown/NoSyncInterval, never permanently stale" do
        host = build(:devops_docker_host, account: account, status: "connected",
                                          auto_sync: true, sync_interval_seconds: nil,
                                          last_synced_at: 1.minute.ago)

        expect(fresh_condition(host)["status"]).to eq(Platform::Status::Condition::UNKNOWN)
        expect(fresh_condition(host)["reason"]).to eq("NoSyncInterval")
        expect(Platform::Status::Condition.verdict_for_set(contributor.conditions_for(host)))
          .to eq(Platform::ComponentStatus::NOT_MEASURED)
      end

      it "treats an explicit zero the same way" do
        host = build(:devops_docker_host, account: account, status: "connected",
                                          auto_sync: true, sync_interval_seconds: 0,
                                          last_synced_at: 1.minute.ago)

        expect(fresh_condition(host)["reason"]).to eq("NoSyncInterval")
      end

      # The other arm: a real interval still measures, and a stale host is
      # still stale. Without this the rule above could be satisfied by never
      # reporting SyncStale at all.
      it "still reports SyncStale when the interval is real" do
        host = build(:devops_docker_host, account: account, status: "connected",
                                          auto_sync: true, sync_interval_seconds: interval,
                                          last_synced_at: 1.hour.ago)

        expect(fresh_condition(host)["reason"]).to eq("SyncStale")
      end
    end
  end

  describe "#dependencies_for" do
    # Built, never saved: `dependencies_for` reads the FK column only, and a
    # persisted managed host would need a System::NodeInstance, which does not
    # exist in core mode. A core spec must not require an extension.
    it "declares the backing node instance for a managed host" do
      node_instance_id = SecureRandom.uuid
      host = build(:devops_docker_host, provisioning_state: "managed", node_instance_id: node_instance_id)

      expect(contributor.dependencies_for(host))
        .to eq([ { "kind" => "node_instance", "ref" => node_instance_id, "relation" => "hosts" } ])
    end

    it "declares nothing for an external host" do
      host = build(:devops_docker_host, provisioning_state: "external", node_instance_id: nil)

      expect(contributor.dependencies_for(host)).to eq([])
    end
  end

  describe "#each_component" do
    it "yields only this account's hosts" do
      mine = create(:devops_docker_host, account: account)
      theirs = create(:devops_docker_host, account: create(:account))

      ids = enumerate(account).map(&:id)

      expect(ids).to eq([ mine.id ])
      expect(ids).not_to include(theirs.id)
    end

    it "keeps a host under maintenance — held is intent, not deletion" do
      held = create(:devops_docker_host, account: account, status: "maintenance")

      expect(enumerate(account).map(&:id)).to include(held.id)
    end

    it "yields nothing without an account" do
      create(:devops_docker_host, account: account)

      expect(enumerate(nil)).to eq([])
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe Devops::RunnerHealthService do
  let(:account) { create(:account) }
  let(:provider) { create(:git_provider, provider_type: "gitea") }
  let(:credential) { create(:git_provider_credential, account: account, provider: provider) }
  let(:service) { described_class.new(account: account) }

  describe "#check_health" do
    context "with stale runners" do
      let!(:stale_runner) do
        create(:git_runner, :online, credential: credential, account: account,
               last_seen_at: 10.minutes.ago)
      end

      let!(:healthy_runner) do
        create(:git_runner, :online, credential: credential, account: account,
               last_seen_at: 1.minute.ago)
      end

      it "marks stale runners as offline" do
        result = service.check_health

        expect(result[:marked_offline]).to eq(1)
        expect(stale_runner.reload.status).to eq("offline")
        expect(healthy_runner.reload.status).to eq("online")
      end
    end

    context "with runners that have never been seen" do
      let!(:unseen_runner) do
        create(:git_runner, :online, credential: credential, account: account,
               last_seen_at: nil)
      end

      it "marks unseen runners as offline" do
        result = service.check_health

        expect(result[:marked_offline]).to eq(1)
        expect(unseen_runner.reload.status).to eq("offline")
      end
    end

    context "with no stale runners" do
      let!(:healthy_runner) do
        create(:git_runner, :online, credential: credential, account: account,
               last_seen_at: 1.minute.ago)
      end

      it "marks no runners offline" do
        result = service.check_health

        expect(result[:marked_offline]).to eq(0)
        expect(healthy_runner.reload.status).to eq("online")
      end
    end

    context "with offline runners" do
      let!(:offline_runner) do
        create(:git_runner, :offline, credential: credential, account: account,
               last_seen_at: 30.minutes.ago)
      end

      it "does not re-process already offline runners" do
        result = service.check_health

        expect(result[:marked_offline]).to eq(0)
      end
    end
  end

  describe "#capacity_summary" do
    before do
      create(:git_runner, :online, credential: credential, account: account)
      create(:git_runner, :online, credential: credential, account: account)
      create(:git_runner, :busy, credential: credential, account: account)
      create(:git_runner, :offline, credential: credential, account: account)
    end

    it "returns correct capacity breakdown" do
      summary = service.capacity_summary

      expect(summary[:total]).to eq(4)
      expect(summary[:online]).to eq(2)
      expect(summary[:busy]).to eq(1)
      expect(summary[:offline]).to eq(1)
      expect(summary[:available]).to eq(2)
      expect(summary[:utilization_pct]).to be_a(Float)
    end
  end

  describe "#reconcile_runner_statuses" do
    # Provider (Gitea) is the authoritative liveness source. The local
    # last_seen_at only reflects when we last polled the provider — it is NOT a
    # runner heartbeat — so it must never be used to mark a healthy runner offline.
    let(:mock_client) { instance_double(Devops::Git::GiteaApiClient, supports_runners?: true) }

    before do
      allow(Devops::Git::ApiClient).to receive(:for).with(credential).and_return(mock_client)
    end

    context "with a healthy idle runner that has gone stale locally" do
      let!(:idle_runner) do
        create(:git_runner, :online, credential: credential, account: account,
               external_id: "100", last_seen_at: 10.minutes.ago)
      end

      before do
        # The provider reports it as online/idle — it is alive.
        allow(mock_client).to receive(:list_runners).and_return([
          { "id" => "100", "name" => idle_runner.name, "status" => "online", "busy" => false,
            "labels" => ["self-hosted"], "os" => "Linux", "architecture" => "x64", "version" => "2.0" }
        ])
      end

      it "keeps it online and refreshes last_seen_at (no false offline)" do
        result = service.reconcile_runner_statuses

        expect(idle_runner.reload.status).to eq("online")
        expect(idle_runner.last_seen_at).to be > 1.minute.ago
        expect(result[:marked_offline]).to eq(0)
      end
    end

    context "with a runner the provider no longer reports" do
      let!(:present_runner) do
        create(:git_runner, :online, credential: credential, account: account,
               external_id: "200", last_seen_at: 10.minutes.ago)
      end
      let!(:gone_runner) do
        create(:git_runner, :online, credential: credential, account: account,
               external_id: "201", last_seen_at: 10.minutes.ago)
      end

      before do
        # Provider returns only runner 200; 201 has been deregistered.
        allow(mock_client).to receive(:list_runners).and_return([
          { "id" => "200", "name" => present_runner.name, "status" => "online", "busy" => false,
            "labels" => [], "os" => "Linux", "architecture" => "x64", "version" => "2.0" }
        ])
      end

      it "marks only the absent runner offline" do
        result = service.reconcile_runner_statuses

        expect(present_runner.reload.status).to eq("online")
        expect(gone_runner.reload.status).to eq("offline")
        expect(result[:marked_offline]).to eq(1)
      end
    end

    context "when the provider returns nothing (transient error or empty)" do
      let!(:runner) do
        create(:git_runner, :online, credential: credential, account: account,
               external_id: "300", last_seen_at: 10.minutes.ago)
      end

      before { allow(mock_client).to receive(:list_runners).and_return([]) }

      it "leaves online runners untouched (no outage storm)" do
        result = service.reconcile_runner_statuses

        expect(runner.reload.status).to eq("online")
        expect(result[:marked_offline]).to eq(0)
      end
    end
  end
end

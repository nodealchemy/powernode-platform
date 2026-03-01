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
end

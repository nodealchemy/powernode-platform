# frozen_string_literal: true

require "rails_helper"

# Audit F5-13 — InstancePoolReplenisherJob is the LIVE 60s reaping path
# (cron in sidekiq.yml), API-only: per active/draining pool it POSTs
# recycle_stale then replenish. It previously had no spec (its dead direct-DB
# twin System::InstancePoolReaperService was removed). This locks the
# surviving implementation's per-pool 2-phase contract.
RSpec.describe System::InstancePoolReplenisherJob, type: :job do
  subject { described_class }

  it_behaves_like "a base job", described_class

  let(:job) { described_class.new }
  let(:api_client) { instance_double(BackendApiClient) }

  before { allow(job).to receive(:api_client).and_return(api_client) }

  describe "#execute" do
    context "with two active pools" do
      let(:pools) { [ { "id" => "pool-a" }, { "id" => "pool-b" } ] }

      before do
        allow(api_client).to receive(:get)
          .with("/api/v1/system/instance_pools", params: { status: "active,draining" })
          .and_return({ success: true, data: { pools: pools } })

        allow(api_client).to receive(:post)
          .with("/api/v1/system/instance_pools/pool-a/recycle_stale")
          .and_return({ success: true, data: { recycle_result: { "ready_to_draining" => 1 } } })
        allow(api_client).to receive(:post)
          .with("/api/v1/system/instance_pools/pool-b/recycle_stale")
          .and_return({ success: true, data: { recycle_result: {} } })

        allow(api_client).to receive(:post)
          .with("/api/v1/system/instance_pools/pool-a/replenish")
          .and_return({ success: true, data: { replenish_result: { provisioned: 2 } } })
        allow(api_client).to receive(:post)
          .with("/api/v1/system/instance_pools/pool-b/replenish")
          .and_return({ success: true, data: { replenish_result: { provisioned: 1 } } })
      end

      it "recycles then replenishes every pool and sums provisioned counts" do
        result = job.execute

        expect(result).to eq(processed: 2, total_provisioned: 3)
        expect(api_client).to have_received(:post).with("/api/v1/system/instance_pools/pool-a/recycle_stale")
        expect(api_client).to have_received(:post).with("/api/v1/system/instance_pools/pool-a/replenish")
      end
    end

    context "when listing pools fails" do
      before do
        allow(api_client).to receive(:get).and_raise(StandardError.new("backend down"))
      end

      it "processes zero pools without raising" do
        expect { @result = job.execute }.not_to raise_error
        expect(@result).to eq(processed: 0, total_provisioned: 0)
      end
    end

    context "when a pool's recycle fails" do
      let(:pools) { [ { "id" => "pool-x" } ] }

      before do
        allow(api_client).to receive(:get).and_return({ success: true, data: { pools: pools } })
        allow(api_client).to receive(:post)
          .with("/api/v1/system/instance_pools/pool-x/recycle_stale")
          .and_return({ success: false, error: "recycle boom" })
        allow(api_client).to receive(:post)
          .with("/api/v1/system/instance_pools/pool-x/replenish")
          .and_return({ success: true, data: { replenish_result: { provisioned: 4 } } })
      end

      it "still replenishes the pool (recycle failure does not block phase 2)" do
        result = job.execute

        expect(result).to eq(processed: 1, total_provisioned: 4)
        expect(api_client).to have_received(:post).with("/api/v1/system/instance_pools/pool-x/replenish")
      end
    end
  end
end

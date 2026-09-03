# frozen_string_literal: true

require "rails_helper"

# Audit F5-13 — InstancePoolReplenisherJob is the LIVE 60s reaping path
# (cron in sidekiq.yml), API-only: it LISTS active + draining pools and POSTs
# recycle_stale for each, then replenish for the ACTIVE ones only
# (IMP-cb2da06a384b). This locks the surviving implementation's per-pool
# 2-phase contract.
#
# Regression guard (improvement 019f5b93): BackendApiClient returns
# STRING-keyed JSON and get(path, params) takes the query hash POSITIONALLY.
# The stubs below therefore use string keys and a positional query hash — an
# earlier revision stubbed symbol keys + `params: {...}`, which matched the
# job's (buggy) symbol reads so the tests passed while the real reaper read
# nil off every response and "processed 0 pools" forever. Keep these stubs
# shaped like the real client so that class of bug can't hide again.
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
        # Positional query hash → serializes as ?status=... (NOT params[status]).
        allow(api_client).to receive(:get)
          .with("/api/v1/system/instance_pools", { status: "active,draining" })
          .and_return({ "success" => true, "data" => { "pools" => pools } })

        allow(api_client).to receive(:post)
          .with("/api/v1/system/instance_pools/pool-a/recycle_stale")
          .and_return({ "success" => true, "data" => { "recycle_result" => { "ready_to_draining" => 1 } } })
        allow(api_client).to receive(:post)
          .with("/api/v1/system/instance_pools/pool-b/recycle_stale")
          .and_return({ "success" => true, "data" => { "recycle_result" => {} } })

        allow(api_client).to receive(:post)
          .with("/api/v1/system/instance_pools/pool-a/replenish")
          .and_return({ "success" => true, "data" => { "replenish_result" => { "provisioned" => 2 } } })
        allow(api_client).to receive(:post)
          .with("/api/v1/system/instance_pools/pool-b/replenish")
          .and_return({ "success" => true, "data" => { "replenish_result" => { "provisioned" => 1 } } })
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

    # Audit F5-05 — per-pool failure isolation: one pool's replenish blowing
    # up (timeout, connection refused) must not abort the remaining pools'
    # tick, or a single bad pool starves every other pool of replenishment.
    context "when one pool's replenish raises" do
      let(:pools) { [ { "id" => "pool-bad" }, { "id" => "pool-good" } ] }

      before do
        allow(api_client).to receive(:get).and_return({ "success" => true, "data" => { "pools" => pools } })
        allow(api_client).to receive(:post)
          .with(%r{/instance_pools/pool-(bad|good)/recycle_stale})
          .and_return({ "success" => true, "data" => { "recycle_result" => {} } })
        allow(api_client).to receive(:post)
          .with("/api/v1/system/instance_pools/pool-bad/replenish")
          .and_raise(StandardError.new("connection refused"))
        allow(api_client).to receive(:post)
          .with("/api/v1/system/instance_pools/pool-good/replenish")
          .and_return({ "success" => true, "data" => { "replenish_result" => { "provisioned" => 2 } } })
      end

      it "still replenishes the remaining pools and reports their counts" do
        expect { @result = job.execute }.not_to raise_error

        expect(@result).to eq(processed: 2, total_provisioned: 2)
        expect(api_client).to have_received(:post)
          .with("/api/v1/system/instance_pools/pool-good/replenish")
      end
    end

    context "when one pool's replenish returns an error response" do
      let(:pools) { [ { "id" => "pool-err" }, { "id" => "pool-ok" } ] }

      before do
        allow(api_client).to receive(:get).and_return({ "success" => true, "data" => { "pools" => pools } })
        allow(api_client).to receive(:post)
          .with(%r{/instance_pools/pool-(err|ok)/recycle_stale})
          .and_return({ "success" => true, "data" => { "recycle_result" => {} } })
        allow(api_client).to receive(:post)
          .with("/api/v1/system/instance_pools/pool-err/replenish")
          .and_return({ "success" => false, "error" => "pool is paused" })
        allow(api_client).to receive(:post)
          .with("/api/v1/system/instance_pools/pool-ok/replenish")
          .and_return({ "success" => true, "data" => { "replenish_result" => { "provisioned" => 1 } } })
      end

      it "records the error for that pool and continues with the rest" do
        result = job.execute

        expect(result).to eq(processed: 2, total_provisioned: 1)
        expect(api_client).to have_received(:post)
          .with("/api/v1/system/instance_pools/pool-ok/replenish")
      end
    end

    # IMP-cb2da06a384b — drain means STOP TOPPING UP.
    #
    # The list call deliberately still asks for draining pools: recycling is
    # what EMPTIES a draining pool (stale-warming, ready-TTL and the errored
    # terminate ladder all run from the recycle phase), so phase 1 must keep
    # visiting them. Phase 2 must not. Before this guard, drain! terminated
    # the ready members and this job provisioned them straight back on the
    # next 60 s tick, because target_size is deliberately left standing so a
    # re-activated pool warms again.
    #
    # The server-side guard in InstancePoolService#replenish! is the
    # authority; this filter exists so the reaper does not spend a tick
    # asking for a top-up it knows will be refused.
    context "with a draining pool alongside an active one" do
      let(:pools) do
        [ { "id" => "pool-active", "status" => "active" },
          { "id" => "pool-draining", "status" => "draining" } ]
      end

      before do
        allow(api_client).to receive(:get).and_return({ "success" => true, "data" => { "pools" => pools } })
        allow(api_client).to receive(:post)
          .with(%r{/instance_pools/pool-(active|draining)/recycle_stale})
          .and_return({ "success" => true, "data" => { "recycle_result" => {} } })
        allow(api_client).to receive(:post)
          .with("/api/v1/system/instance_pools/pool-active/replenish")
          .and_return({ "success" => true, "data" => { "replenish_result" => { "provisioned" => 2 } } })
        # Stubbed to a NON-ZERO count on purpose: if the job ever posts this,
        # the total below moves and the example fails on the number as well as
        # on the message expectation.
        allow(api_client).to receive(:post)
          .with("/api/v1/system/instance_pools/pool-draining/replenish")
          .and_return({ "success" => true, "data" => { "replenish_result" => { "provisioned" => 3 } } })
      end

      it "recycles both pools but replenishes only the active one" do
        result = job.execute

        expect(api_client).to have_received(:post)
          .with("/api/v1/system/instance_pools/pool-draining/recycle_stale")
        expect(api_client).not_to have_received(:post)
          .with("/api/v1/system/instance_pools/pool-draining/replenish")
        expect(api_client).to have_received(:post)
          .with("/api/v1/system/instance_pools/pool-active/replenish")
        expect(result).to eq(processed: 2, total_provisioned: 2)
      end
    end

    # Non-vacuity for the filter above: it must key on the status the API
    # actually reports, not skip everything. A pool whose summary carries no
    # status at all is still handed to the server, which is the authority on
    # whether it may be replenished — a serializer that stopped emitting
    # `status` must not silently halt replenishment fleet-wide.
    context "when a listed pool carries no status field" do
      let(:pools) { [ { "id" => "pool-nostatus" } ] }

      before do
        allow(api_client).to receive(:get).and_return({ "success" => true, "data" => { "pools" => pools } })
        allow(api_client).to receive(:post)
          .with("/api/v1/system/instance_pools/pool-nostatus/recycle_stale")
          .and_return({ "success" => true, "data" => { "recycle_result" => {} } })
        allow(api_client).to receive(:post)
          .with("/api/v1/system/instance_pools/pool-nostatus/replenish")
          .and_return({ "success" => true, "data" => { "replenish_result" => { "provisioned" => 1 } } })
      end

      it "still replenishes it and lets the server decide" do
        result = job.execute

        expect(api_client).to have_received(:post)
          .with("/api/v1/system/instance_pools/pool-nostatus/replenish")
        expect(result).to eq(processed: 1, total_provisioned: 1)
      end
    end

    context "when a pool's recycle fails" do
      let(:pools) { [ { "id" => "pool-x" } ] }

      before do
        allow(api_client).to receive(:get).and_return({ "success" => true, "data" => { "pools" => pools } })
        allow(api_client).to receive(:post)
          .with("/api/v1/system/instance_pools/pool-x/recycle_stale")
          .and_return({ "success" => false, "error" => "recycle boom" })
        allow(api_client).to receive(:post)
          .with("/api/v1/system/instance_pools/pool-x/replenish")
          .and_return({ "success" => true, "data" => { "replenish_result" => { "provisioned" => 4 } } })
      end

      it "still replenishes the pool (recycle failure does not block phase 2)" do
        result = job.execute

        expect(result).to eq(processed: 1, total_provisioned: 4)
        expect(api_client).to have_received(:post).with("/api/v1/system/instance_pools/pool-x/replenish")
      end
    end
  end
end

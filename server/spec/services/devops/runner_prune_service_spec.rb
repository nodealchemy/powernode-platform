# frozen_string_literal: true

require "rails_helper"

# IMP-5df6d59aaa5c — stale-GitRunner pruning as a service, wrapping the
# semantics of scripts/prune-stale-git-runners.rb. Deliberately derives
# staleness from LOCAL signals only — the reconciliation-against-upstream
# approach was reverted (be18ecebc) because unpaginated/partial provider
# listings make it delete live runners; this service never lists upstream.
#
# Protections (all pinned below):
#   1. Only "fleet-" prefixed rows are candidates (permanent runners immune).
#   2. A runner named by a non-terminal CiRunnerLease is never pruned.
#   3. A runner referenced by a non-terminal Ai::RunnerDispatch is never pruned.
#   4. A runner referenced BY ID from any lease row is retained (FK safety).
#   5. Account-scoped; dry-run (preview) never writes.
RSpec.describe Devops::RunnerPruneService do
  let(:account) { create(:account) }
  let(:service) { described_class.new(account: account) }

  def fleet_runner(name_suffix, account: self.account, **attrs)
    create(:git_runner, account: account, name: "fleet-#{name_suffix}",
           status: "offline", **attrs)
  end

  def lease_for(runner_name, status:)
    node = create(:system_node, account: account)
    instance = create(:system_node_instance, node: node, name: "ni-#{SecureRandom.hex(3)}",
                      variety: "cloud", status: "running")
    System::CiRunnerLease.create!(account: account, node_instance: instance,
                                  status: status, runner_name: runner_name)
  end

  def dispatch_for(runner, status:)
    session = create(:ai_worktree_session, account: account)
    worktree = create(:ai_worktree, account: account)
    create(:ai_runner_dispatch, account: account, git_runner: runner, status: status,
           worktree_session: session, worktree: worktree)
  end

  describe "#preview" do
    it "selects only stale fleet-prefixed rows (permanent runners immune)" do
      stale = fleet_runner("a1")
      permanent = create(:git_runner, account: account, name: "runner1", status: "offline")

      result = service.preview

      expect(result.candidates.map(&:id)).to contain_exactly(stale.id)
      expect(Devops::GitRunner.exists?(permanent.id)).to be(true)
    end

    it "never selects a runner named by a non-terminal lease" do
      busy = fleet_runner("busy")
      idle = fleet_runner("idle")
      lease_for(busy.name, status: "busy")

      result = service.preview

      expect(result.candidates.map(&:id)).to contain_exactly(idle.id)
      expect(result.retained[:live_lease_names]).to include(busy.name)
    end

    it "treats a terminal lease's runner name as prunable" do
      done = fleet_runner("done")
      lease_for(done.name, status: "released")

      expect(service.preview.candidates.map(&:id)).to include(done.id)
    end

    it "never selects a runner with a non-terminal dispatch (refuses live dispatch FKs)" do
      dispatched = fleet_runner("dispatched")
      idle = fleet_runner("idle")
      dispatch_for(dispatched, status: "running")

      result = service.preview

      expect(result.candidates.map(&:id)).to contain_exactly(idle.id)
      expect(result.retained[:active_dispatch_runner_ids]).to include(dispatched.id)
    end

    it "retains a runner referenced BY ID from any lease row (FK safety over history)" do
      referenced = fleet_runner("ref")
      lease = lease_for("some-other-name", status: "released")
      lease.update_columns(git_runner_id: referenced.id)

      result = service.preview

      expect(result.candidates.map(&:id)).not_to include(referenced.id)
      expect(result.retained[:lease_referenced_runner_ids]).to include(referenced.id)
    end

    it "is account-scoped and read-only" do
      mine = fleet_runner("mine")
      other = create(:git_runner, name: "fleet-other", status: "offline") # other account

      expect { service.preview }.not_to change(Devops::GitRunner, :count)
      expect(service.preview.candidates.map(&:id)).to contain_exactly(mine.id)
      expect(Devops::GitRunner.exists?(other.id)).to be(true)
    end
  end

  describe "#apply!" do
    it "deletes the candidates and nulls terminal dispatch pointers (history kept)" do
      doomed = fleet_runner("doomed")
      dispatch = dispatch_for(doomed, status: "completed")

      result = service.apply!

      expect(result.applied).to be(true)
      expect(result.deleted_count).to eq(1)
      expect(Devops::GitRunner.exists?(doomed.id)).to be(false)
      expect(dispatch.reload.git_runner_id).to be_nil
      expect(dispatch.reload.status).to eq("completed") # row preserved
    end

    it "deletes nothing when everything is protected" do
      protected_runner = fleet_runner("protected")
      lease_for(protected_runner.name, status: "busy")

      result = service.apply!

      expect(result.deleted_count).to eq(0)
      expect(Devops::GitRunner.exists?(protected_runner.id)).to be(true)
    end
  end
end

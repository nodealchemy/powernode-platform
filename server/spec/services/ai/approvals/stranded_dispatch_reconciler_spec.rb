# frozen_string_literal: true

require "rails_helper"

# IMP-0213523480d1 — IMP-9ce0ed39c557 moved the approved-arm dispatch in
# Ai::ApprovalRequest#notify_source_of_decision to
# ActiveRecord.after_all_transactions_commit, so the flip to "approved" now
# commits BEFORE the dispatch runs. A process that dies in between (OOM, a
# deploy restart, SIGKILL), or a non-StandardError escaping the block, left the
# request approved with execution_status nil and its operation pending — a
# state nothing repaired and that read as a clean no-op.
#
# Every stranded or interrupted row in this file is produced the way production
# produces it: the decision commits through record_decision!, and the
# post-commit dispatch dies with a non-StandardError — before its first line
# (stranded) or inside the executor (interrupted). No column is written by hand.
RSpec.describe Ai::Approvals::StrandedDispatchReconciler do
  # Stands in for SIGKILL / NoMemoryError: not a StandardError, so no rescue in
  # the dispatch path catches it.
  class StrandedDispatchSimulatedCrash < Exception; end # rubocop:disable Lint/InheritException

  PAST_GRACE = 40.minutes
  INSIDE_GRACE = 20.minutes

  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:chain) do
    Ai::ApprovalChain.create!(
      account: account, name: "chain-#{SecureRandom.hex(4)}",
      trigger_type: "autonomy_action", status: "active",
      is_sequential: true, timeout_hours: 4, timeout_action: "reject",
      steps: [ { "name" => "s", "approvers" => [ "*" ], "required_approvals" => 1 } ]
    )
  end

  before do
    stub_const("ReconcilerSpecPerformer", Class.new do
      def self.execute(params, deferred_operation:)
        { performed: true, params: params }
      end
    end)
    allow(ReconcilerSpecPerformer).to receive(:execute).and_call_original
  end

  def gated_operation(category)
    Ai::DeferredOperation.create!(
      account: account, action_category: category,
      executor_class: "ReconcilerSpecPerformer", params: { "k" => "v" }
    )
  end

  def request_for(op, request_data: {})
    chain.create_request!(
      source_type: "Ai::DeferredOperation", source_id: op.id, description: "d",
      request_data: { "action_category" => op.action_category }.merge(request_data)
    )
  end

  def approve!(req)
    req.record_decision!(approver: user, decision: "approved", origin: Ai::ApprovalDecision::REST_SESSION)
  end

  # Approve for real, from a person's own session so a human-only request is
  # decidable too; the post-commit dispatch dies before it starts.
  def strand!(req)
    allow(req).to receive(:dispatch_to_source!).and_raise(StrandedDispatchSimulatedCrash)
    expect { approve!(req) }.to raise_error(StrandedDispatchSimulatedCrash)
    Ai::ApprovalRequest.find(req.id)
  end

  def stranded_request(category, request_data: {})
    op = gated_operation(category)
    req = strand!(request_for(op, request_data: request_data))
    [ req, op ]
  end

  # Approve for real; the dispatch claims its start and then dies inside the
  # executor.
  def interrupted_request(category = "test.act")
    op = gated_operation(category)
    req = request_for(op)
    allow(ReconcilerSpecPerformer).to receive(:execute).and_raise(StrandedDispatchSimulatedCrash)
    expect { approve!(req) }.to raise_error(StrandedDispatchSimulatedCrash)
    allow(ReconcilerSpecPerformer).to receive(:execute).and_call_original
    [ Ai::ApprovalRequest.find(req.id), op ]
  end

  def reconcile
    described_class.new(account: account).call
  end

  def allowlist!(*categories)
    SiteSetting.set(described_class::REDISPATCH_ALLOWLIST_SETTING, categories, setting_type: "json")
  end

  def mark!(category, value)
    Ai::InterventionPolicy.create!(account: account, action_category: category, scope: "action_type",
                                   policy: "require_approval", priority: 1, is_active: true,
                                   conditions: { "requires_human_session" => value })
  end

  def audits_for(req)
    AuditLog.where(resource_type: "Ai::ApprovalRequest", resource_id: req.id)
  end

  describe "the stranded state itself" do
    it "is what a dispatch that died after commit leaves behind: approved, scheduled, never started" do
      req, op = stranded_request("test.act")

      expect(req.status).to eq("approved")
      expect(req.execution_status).to be_nil
      expect(req.dispatch_scheduled_at).to be_present
      expect(req.dispatch_started_at).to be_nil
      expect(req.dispatch_finished_at).to be_nil
      expect(op.reload.status).to eq("pending")
      expect(ReconcilerSpecPerformer).not_to have_received(:execute)
    end
  end

  describe "a stranded request past the grace window" do
    it "is failed, with the operation failed, an audit row and an operator-visible event" do
      req, op = stranded_request("test.act")

      travel_to(PAST_GRACE.from_now) do
        expect(reconcile).to include(failed: 1, redispatched: 0, errored: 0)
      end

      req.reload
      expect(req.status).to eq("approved")
      expect(req.execution_status).to eq("failed")
      expect(req.execution_error).to include("Ai::ApprovalRequest::DispatchAbandoned")
      expect(req.dispatch_started_at).to be_nil

      expect(op.reload.status).to eq("failed")
      expect(op.error_message).to include("never started")
      expect(ReconcilerSpecPerformer).not_to have_received(:execute)

      event = Ai::ExecutionEvent.find_by(source_type: "Ai::ApprovalRequest", source_id: req.id)
      expect(event).to be_present
      expect(event.status).to eq("failed")
      expect(event.error_class).to eq("Ai::ApprovalRequest::DispatchAbandoned")
      expect(event.metadata).to include("action_category" => "test.act", "reconciled" => "failed")

      audit = audits_for(req).sole
      expect(audit.action).to eq("ai.approvals.dispatch_abandoned")
      expect(audit.account_id).to eq(account.id)
      expect(audit.metadata).to include("action_category" => "test.act", "reason" => a_string_including("never started"))
    end

    it "fails a stranded request whose source is not a deferred operation (no source hook)" do
      probe = Class.new do
        attr_reader :calls

        def on_approval_decision(_request)
          (@calls ||= []) << :decision
          Ai::ApprovalRequest::DISPATCH_EXECUTED
        end
      end.new
      stub_const("ReconcilerSpecSource", probe)
      probe.singleton_class.define_method(:find_by) { |id:| probe }

      req = strand!(chain.create_request!(source_type: "ReconcilerSpecSource", source_id: SecureRandom.uuid,
                                          description: "d", request_data: { "action_category" => "test.other" }))

      travel_to(PAST_GRACE.from_now) { expect(reconcile).to include(failed: 1) }

      expect(req.reload.execution_status).to eq("failed")
      expect(probe.calls).to be_nil
    end

    it "releases a parked plan step only after the settlement commits" do
      allow(Ai::Provisioning::SkillCompositionRunner).to receive(:resume_parked_step)
      _req, op = stranded_request("test.act")

      travel_to(PAST_GRACE.from_now) { reconcile }

      expect(Ai::Provisioning::SkillCompositionRunner).to have_received(:resume_parked_step)
        .with(deferred_operation: have_attributes(id: op.id, status: "failed"))
    end

    it "rolls the whole settlement back, release included, when its audit cannot be written" do
      allow(Ai::Provisioning::SkillCompositionRunner).to receive(:resume_parked_step)
      req, op = stranded_request("test.act")
      allow(AuditLog).to receive(:log_action).and_raise(RuntimeError, "audit sink down")

      travel_to(PAST_GRACE.from_now) do
        expect(reconcile).to include(failed: 0, redispatched: 0, errored: 1)
      end

      expect(Ai::Provisioning::SkillCompositionRunner).not_to have_received(:resume_parked_step)
      req.reload
      expect(req.execution_status).to be_nil
      expect(Ai::ApprovalRequest.owed_dispatch).to include(req)
      expect(op.reload.status).to eq("pending")
      expect(Ai::ExecutionEvent.where(source_type: "Ai::ApprovalRequest", source_id: req.id)).to be_empty
    end
  end

  describe "the grace window" do
    it "leaves a stranded request inside the default window untouched" do
      req, op = stranded_request("test.act")

      travel_to(INSIDE_GRACE.from_now) { expect(reconcile).to include(failed: 0, redispatched: 0) }

      expect(req.reload.execution_status).to be_nil
      expect(op.reload.status).to eq("pending")
    end

    it "defaults to 30 minutes" do
      expect(described_class.grace_window).to eq(30.minutes)
    end

    it "is read from the config seam, not ENV" do
      SiteSetting.set(described_class::GRACE_MINUTES_SETTING, 60, setting_type: "integer")
      req, = stranded_request("test.act")

      travel_to(PAST_GRACE.from_now) { reconcile }
      expect(req.reload.execution_status).to be_nil

      travel_to(61.minutes.from_now) { reconcile }
      expect(req.reload.execution_status).to eq("failed")
    end

    it "falls back to the default when the setting is not a positive integer" do
      SiteSetting.set(described_class::GRACE_MINUTES_SETTING, "soon")
      expect(described_class.grace_window).to eq(described_class::DEFAULT_GRACE_MINUTES.minutes)
    end
  end

  describe "the finished stamp" do
    it "is set when the dispatch executes" do
      op = gated_operation("test.act")
      req = request_for(op)
      approve!(req)

      expect(req.reload.dispatch_finished_at).to be_present
      expect(req.execution_status).to eq("succeeded")
    end

    it "is set when the source reports a no-op" do
      op = gated_operation("test.act")
      req = request_for(op)
      op.update_columns(status: "completed")
      approve!(req)

      expect(req.reload.dispatch_finished_at).to be_present
      expect(req.execution_status).to be_nil
    end

    it "is set when the dispatch raises" do
      op = gated_operation("test.act")
      req = request_for(op)
      allow(ReconcilerSpecPerformer).to receive(:execute).and_raise("executor kaboom")
      approve!(req)

      expect(req.reload.dispatch_finished_at).to be_present
      expect(req.execution_status).to eq("failed")
    end

    it "is set when there is no longer a source to dispatch to" do
      allowlist!("test.idempotent")
      req, op = stranded_request("test.idempotent")
      op.destroy!

      travel_to(PAST_GRACE.from_now) { expect(reconcile).to include(redispatched: 1) }

      req.reload
      expect(req.dispatch_started_at).to be_present
      expect(req.dispatch_finished_at).to be_present
    end

    it "is NOT set when the dispatch dies inside the executor" do
      req, op = interrupted_request

      expect(req.dispatch_started_at).to be_present
      expect(req.dispatch_finished_at).to be_nil
      expect(op.reload.status).to eq("executing")
    end
  end

  describe "a request whose dispatch started" do
    it "is never failed or re-run, even with no declared outcome" do
      allowlist!("test.act")
      req, = interrupted_request

      travel_to(PAST_GRACE.from_now) { expect(reconcile).to include(failed: 0, redispatched: 0) }

      expect(req.reload.execution_status).to be_nil
      expect(ReconcilerSpecPerformer).to have_received(:execute).once
      expect(audits_for(req)).to be_empty
    end

    it "is untouched after a normal dispatch completes, however old" do
      op = gated_operation("test.act")
      req = request_for(op)
      approve!(req)

      travel_to(7.hours.from_now) { expect(reconcile).to include(failed: 0, redispatched: 0, interrupted: 0) }

      expect(req.reload.execution_status).to eq("succeeded")
      expect(op.reload.status).to eq("completed")
      expect(ReconcilerSpecPerformer).to have_received(:execute).once
    end
  end

  describe "an interrupted dispatch (started, never finished)" do
    it "is signalled once past the interrupt window: audit, event and count, and nothing re-run or failed" do
      req, op = interrupted_request

      travel_to(7.hours.from_now) do
        expect(reconcile).to include(interrupted: 1, failed: 0, redispatched: 0)
        expect(reconcile).to include(interrupted: 0)
      end

      req.reload
      expect(req.execution_status).to be_nil
      expect(req.dispatch_interrupt_signalled_at).to be_present
      expect(op.reload.status).to eq("executing")
      expect(ReconcilerSpecPerformer).to have_received(:execute).once

      audit = audits_for(req).sole
      expect(audit.action).to eq("ai.approvals.dispatch_interrupted")
      expect(audit.metadata).to include("reason" => a_string_including("never finished"))

      event = Ai::ExecutionEvent.where(source_type: "Ai::ApprovalRequest", source_id: req.id).sole
      expect(event.event_type).to eq("approval_execution")
      expect(event.status).to eq("interrupted")
      expect(event.error_class).to eq("Ai::ApprovalRequest::DispatchInterrupted")
      expect(event.metadata).to include("reconciled" => "interrupted")
    end

    it "is left alone inside the interrupt window" do
      req, = interrupted_request

      travel_to(5.hours.from_now) { expect(reconcile).to include(interrupted: 0) }

      expect(req.reload.dispatch_interrupt_signalled_at).to be_nil
    end

    it "reads its window from the config seam" do
      SiteSetting.set(described_class::INTERRUPT_HOURS_SETTING, 1, setting_type: "integer")
      req, = interrupted_request

      travel_to(2.hours.from_now) { expect(reconcile).to include(interrupted: 1) }
      expect(req.reload.dispatch_interrupt_signalled_at).to be_present
    end

    it "is not signalled when the stamp is rolled back with a failed audit" do
      req, = interrupted_request
      allow(AuditLog).to receive(:log_action).and_raise(RuntimeError, "audit sink down")

      travel_to(7.hours.from_now) { expect(reconcile).to include(interrupted: 0, errored: 1) }

      expect(req.reload.dispatch_interrupt_signalled_at).to be_nil
    end
  end

  describe "re-dispatch" do
    it "re-dispatches an allowlisted category exactly once" do
      allowlist!("test.idempotent")
      req, op = stranded_request("test.idempotent")

      travel_to(PAST_GRACE.from_now) do
        expect(reconcile).to include(redispatched: 1, failed: 0)
        expect(reconcile).to include(redispatched: 0, failed: 0)
      end

      expect(ReconcilerSpecPerformer).to have_received(:execute).once
      req.reload
      expect(req.execution_status).to eq("succeeded")
      expect(req.dispatch_started_at).to be_present
      expect(op.reload.status).to eq("completed")
      expect(audits_for(req).sole.action).to eq("ai.approvals.dispatch_redispatched")
    end

    it "audits the re-dispatch before it runs, so one that dies mid-run is still on record" do
      allowlist!("test.idempotent")
      req, = stranded_request("test.idempotent")
      allow(ReconcilerSpecPerformer).to receive(:execute).and_raise(StrandedDispatchSimulatedCrash)

      travel_to(PAST_GRACE.from_now) do
        expect { reconcile }.to raise_error(StrandedDispatchSimulatedCrash)
      end

      expect(audits_for(req).sole.action).to eq("ai.approvals.dispatch_redispatched")
      expect(req.reload.dispatch_started_at).to be_present
    end

    it "fails a category that is not allowlisted (the default allowlist is empty)" do
      req, = stranded_request("test.idempotent")

      travel_to(PAST_GRACE.from_now) { expect(reconcile).to include(failed: 1, redispatched: 0) }

      expect(ReconcilerSpecPerformer).not_to have_received(:execute)
      expect(req.reload.execution_status).to eq("failed")
    end

    it "ignores an allowlist setting that is not a list of strings (fail closed)" do
      SiteSetting.set(described_class::REDISPATCH_ALLOWLIST_SETTING, { "test.idempotent" => true }, setting_type: "json")
      req, = stranded_request("test.idempotent")

      travel_to(PAST_GRACE.from_now) { reconcile }

      expect(ReconcilerSpecPerformer).not_to have_received(:execute)
      expect(req.reload.execution_status).to eq("failed")
    end

    {
      "out-of-band exec" => [ "system.instance.out_of_band_exec", {} ],
      "a unit drop-in" => [ "system.instance.unit_dropin", {} ],
      "a destructive category" => [ "test.resource_delete", {} ],
      "a reap" => [ "system.instance_reap", {} ],
      "a reprovision" => [ "system.instance_reprovision", {} ],
      "a replace" => [ "test.node_replace", {} ],
      "a rollback" => [ "test.release_rollback", {} ],
      "a human-only request" => [ "test.idempotent_human", { "requires_human_session" => true } ]
    }.each do |label, (category, request_data)|
      it "always fails #{label}, even when allowlisted" do
        allowlist!(category)
        req, op = stranded_request(category, request_data: request_data)

        travel_to(PAST_GRACE.from_now) { expect(reconcile).to include(failed: 1, redispatched: 0) }

        expect(ReconcilerSpecPerformer).not_to have_received(:execute)
        expect(req.reload.execution_status).to eq("failed")
        expect(op.reload.status).to eq("failed")
      end
    end

    # The account's intervention mark decides who may APPROVE a request, not
    # whether it is safe to run twice: a mark of false must not lift the
    # never-list.
    context "when the account marks the category as not needing a person" do
      it "still fails an allowlisted reap" do
        mark!("*", false)
        allowlist!("system.pool_guest_reap")
        req, = stranded_request("system.pool_guest_reap")

        travel_to(PAST_GRACE.from_now) { expect(reconcile).to include(failed: 1, redispatched: 0) }

        expect(ReconcilerSpecPerformer).not_to have_received(:execute)
        expect(req.reload.execution_status).to eq("failed")
      end

      it "still fails an allowlisted request on a protected environment" do
        mark!("test.idempotent", false)
        allowlist!("test.idempotent")
        req, = stranded_request("test.idempotent",
                                request_data: { "environment" => { "id" => SecureRandom.uuid, "slug" => "prod",
                                                                    "is_protected" => true } })

        travel_to(PAST_GRACE.from_now) { expect(reconcile).to include(failed: 1, redispatched: 0) }

        expect(ReconcilerSpecPerformer).not_to have_received(:execute)
        expect(req.reload.execution_status).to eq("failed")
      end

      it "still re-dispatches an allowlisted, unprotected, non-destructive category (positive twin)" do
        mark!("test.idempotent", false)
        allowlist!("test.idempotent")
        req, = stranded_request("test.idempotent")

        travel_to(PAST_GRACE.from_now) { expect(reconcile).to include(redispatched: 1) }

        expect(req.reload.execution_status).to eq("succeeded")
      end
    end
  end

  describe "the race between the reconciler and a late dispatch" do
    it "refuses a late dispatch once the reconciler has failed the request, and says so" do
      req, op = stranded_request("test.act")
      # Loaded BEFORE the reconciler runs, so nothing in memory tells it the
      # row has moved: only the database's conditional update can refuse it.
      late = Ai::ApprovalRequest.find(req.id)
      allow(Rails.logger).to receive(:warn).and_call_original

      travel_to(PAST_GRACE.from_now) { reconcile }
      late.send(:dispatch_to_source!)

      expect(Rails.logger).to have_received(:warn).with(a_string_including(req.id, "claim refused"))
      expect(ReconcilerSpecPerformer).not_to have_received(:execute)
      expect(req.reload.execution_status).to eq("failed")
      expect(req.dispatch_started_at).to be_nil
      expect(op.reload.status).to eq("failed")
    end

    # The deferred operation's own `pending?` guard would also stop the late
    # dispatch above, so this twin uses a source with no guard of its own:
    # only the request-row claim stands between it and a second action.
    it "refuses a late dispatch through the request claim alone, for a source with no guard" do
      probe = Class.new do
        attr_reader :calls

        def on_approval_decision(_request)
          @calls = @calls.to_i + 1
          Ai::ApprovalRequest::DISPATCH_EXECUTED
        end
      end.new
      stub_const("ReconcilerSpecUnguardedSource", probe)
      probe.singleton_class.define_method(:find_by) { |id:| probe }

      req = strand!(chain.create_request!(source_type: "ReconcilerSpecUnguardedSource", source_id: SecureRandom.uuid,
                                          description: "d", request_data: { "action_category" => "test.other" }))
      late = Ai::ApprovalRequest.find(req.id)

      travel_to(PAST_GRACE.from_now) { reconcile }
      late.send(:dispatch_to_source!)

      expect(probe.calls).to be_nil
      expect(req.reload.execution_status).to eq("failed")
    end

    it "leaves a request alone once a late dispatch has claimed it" do
      req, op = stranded_request("test.act")
      Ai::ApprovalRequest.find(req.id).send(:dispatch_to_source!)

      travel_to(PAST_GRACE.from_now) { expect(reconcile).to include(failed: 0, redispatched: 0) }

      expect(ReconcilerSpecPerformer).to have_received(:execute).once
      expect(req.reload.execution_status).to eq("succeeded")
      expect(op.reload.status).to eq("completed")
    end

    it "lets exactly one of two stale claimants act" do
      allowlist!("test.idempotent")
      req, = stranded_request("test.idempotent")
      first = Ai::ApprovalRequest.find(req.id)
      second = Ai::ApprovalRequest.find(req.id)

      results = [ first.redispatch_stranded!, second.abandon_stranded_dispatch!("late") ]

      expect(results).to eq([ true, false ])
      expect(ReconcilerSpecPerformer).to have_received(:execute).once
      expect(req.reload.execution_status).to eq("succeeded")
    end
  end

  it "counts a row it could not settle as errored and leaves it owed" do
    req, = stranded_request("test.act")
    allow_any_instance_of(Ai::DeferredOperation).to receive(:on_dispatch_abandoned).and_raise("legacy row") # rubocop:disable RSpec/AnyInstance

    travel_to(PAST_GRACE.from_now) { expect(reconcile).to include(failed: 0, errored: 1) }

    expect(Ai::ApprovalRequest.owed_dispatch).to include(req.reload)
  end

  it "only reconciles the account it was built for" do
    req, = stranded_request("test.act")

    travel_to(PAST_GRACE.from_now) do
      expect(described_class.new(account: create(:account)).call).to include(failed: 0)
    end
    expect(req.reload.execution_status).to be_nil
  end
end

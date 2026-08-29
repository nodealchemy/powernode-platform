# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Tools::RalphLoopTool do
  let(:account) { create(:account) }
  # NOT the account's first user — the ralph-loop factory creates one first, so
  # this actor gets the `member` role rather than `owner`. These examples
  # exercise the tool's BEHAVIOUR, so the actor is given the permissions the
  # REST twin requires for those actions (RalphLoopsController: update ->
  # ai.loops.update, destroy -> ai.loops.delete, pause/resume -> ai.loops.execute).
  # Authorization itself is pinned separately in
  # read_gated_tools_action_permission_spec.rb.
  let(:user) do
    create(:user, account: account,
                  permissions: %w[ai.agents.update ai.loops.read ai.loops.update
                                  ai.loops.delete ai.loops.execute])
  end
  let(:tool) { described_class.new(account: account, user: user) }
  let(:ralph_loop) { create(:ai_ralph_loop, account: account, name: "spec-loop") }

  # The parallel-claim machinery already existed in DevLoopTool — cap, plus a
  # file-collision guard that only engages above 1 — but nothing could TURN IT
  # ON: update_ralph_loop exposed name/agent/cadence/caps and never
  # `configuration`. A capability with no way to reach it is the same shape as
  # an inert gate: present, described, and unusable. These examples pin the
  # switch, not the machinery (DevLoopTool's own spec covers the claiming).
  describe "update_ralph_loop max_concurrent_claims" do
    it "writes the cap into configuration where DevLoopTool reads it" do
      result = tool.execute(params: { action: "update_ralph_loop", loop_id: ralph_loop.id,
                                      max_concurrent_claims: 3 })

      expect(result[:success]).to be true
      expect(ralph_loop.reload.configuration["max_concurrent_claims"]).to eq(3)
      expect(result[:loop][:max_concurrent_claims]).to eq(3)
    end

    it "reports 1 when the loop has never set a cap, matching the claim path's default" do
      result = tool.execute(params: { action: "get_ralph_loop", loop_id: ralph_loop.id })

      expect(result[:loop][:max_concurrent_claims]).to eq(1)
    end

    # The whole point of a targeted merge: `configuration` is shared, and this
    # action owns exactly one key in it.
    it "preserves unrelated configuration keys rather than rewriting the column" do
      ralph_loop.update!(configuration: { "kept_by_another_writer" => "value" })

      tool.execute(params: { action: "update_ralph_loop", loop_id: ralph_loop.id,
                             max_concurrent_claims: 2 })

      config = ralph_loop.reload.configuration
      expect(config["kept_by_another_writer"]).to eq("value")
      expect(config["max_concurrent_claims"]).to eq(2)
    end

    it "refuses a cap above the ceiling instead of writing it" do
      result = tool.execute(params: { action: "update_ralph_loop", loop_id: ralph_loop.id,
                                      max_concurrent_claims: described_class::MAX_CONCURRENT_CLAIMS_CEILING + 1 })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/between 1 and/)
      expect(ralph_loop.reload.configuration["max_concurrent_claims"]).to be_nil
    end

    it "refuses a cap below 1 instead of writing it" do
      result = tool.execute(params: { action: "update_ralph_loop", loop_id: ralph_loop.id,
                                      max_concurrent_claims: 0 })

      expect(result[:success]).to be false
      expect(ralph_loop.reload.configuration["max_concurrent_claims"]).to be_nil
    end

    it "is advertised, so an operator can discover the switch" do
      params = described_class.action_definitions["update_ralph_loop"][:parameters]

      expect(params).to have_key(:max_concurrent_claims)
    end
  end

  describe "get_ralph_loop" do
    it "returns loop details for a loop with iterations" do
      task = create(:ai_ralph_task, ralph_loop: ralph_loop)
      create(:ai_ralph_iteration, ralph_loop: ralph_loop, ralph_task: task, iteration_number: 1)

      result = tool.execute(params: { action: "get_ralph_loop", loop_id: ralph_loop.name })

      expect(result[:success]).to be true
      expect(result[:loop][:name]).to eq("spec-loop")
      expect(result[:loop][:recent_iterations].length).to eq(1)
    end

    it "returns an error for an unknown loop" do
      result = tool.execute(params: { action: "get_ralph_loop", loop_id: "missing" })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/not found/)
    end
  end

  describe "get_ralph_loop_statistics" do
    it "includes the Tier-2(c) improvement scoreboard" do
      result = tool.execute(params: { action: "get_ralph_loop_statistics" })

      expect(result[:success]).to be true
      expect(result[:improvement]).to include(:net_improvement_velocity, :per_kind)
    end

    it "includes the loop convergence metric (empty state when nothing surfaced)" do
      result = tool.execute(params: { action: "get_ralph_loop_statistics" })

      expect(result[:success]).to be true
      expect(result[:convergence]).to include(
        window_days: 30, improvements_scanned: 0, surfaced_classes: 0,
        recurrent_classes: 0, recurrence_rate: nil, classes: []
      )
    end

    it "reports recurrence of an already-learned bug class" do
      create(:ai_compound_learning, account: account, tags: ["class:jobseam"], created_at: 5.days.ago)
      create(:ai_improvement_recommendation,
             account: account, recommendation_type: "convention_adherence",
             target_type: "Account", target_id: account.id,
             evidence: { "fingerprint" => "class:jobseam|server/app/foo.rb|detail" })

      result = tool.execute(params: { action: "get_ralph_loop_statistics" })

      expect(result[:convergence]).to include(surfaced_classes: 1, recurrent_classes: 1, recurrence_rate: 1.0)
    end
  end

  describe "list_ralph_loops" do
    it "lists loops for the account" do
      ralph_loop

      result = tool.execute(params: { action: "list_ralph_loops" })

      expect(result[:success]).to be true
      expect(result[:count]).to eq(1)
      expect(result[:loops].first[:name]).to eq("spec-loop")
    end
  end

  describe "pause and resume" do
    it "pauses and resumes loop scheduling" do
      pause = tool.execute(params: { action: "pause_ralph_loop", loop_id: ralph_loop.id, reason: "spec" })
      expect(pause[:success]).to be true
      expect(ralph_loop.reload.schedule_paused).to be true

      resume = tool.execute(params: { action: "resume_ralph_loop", loop_id: ralph_loop.id })
      expect(resume[:success]).to be true
      expect(ralph_loop.reload.schedule_paused).to be false
    end
  end

  describe "update_ralph_loop" do
    it "updates the loop's lifetime max_iterations cap" do
      ralph_loop.update!(max_iterations: 500)

      result = tool.execute(params: { action: "update_ralph_loop", loop_id: ralph_loop.id, max_iterations: 5000 })

      expect(result[:success]).to be true
      expect(ralph_loop.reload.max_iterations).to eq(5000)
      expect(result[:loop][:max_iterations]).to eq(5000)
    end

    it "leaves max_iterations untouched when not provided" do
      ralph_loop.update!(max_iterations: 500)

      result = tool.execute(params: { action: "update_ralph_loop", loop_id: ralph_loop.id, name: "renamed-loop" })

      expect(result[:success]).to be true
      expect(ralph_loop.reload.max_iterations).to eq(500)
    end
  end

  describe "serialize_loop iteration headroom" do
    it "surfaces current_iteration and max_iterations via get_ralph_loop" do
      ralph_loop.update!(current_iteration: 466, max_iterations: 500)

      result = tool.execute(params: { action: "get_ralph_loop", loop_id: ralph_loop.id })

      expect(result[:loop][:current_iteration]).to eq(466)
      expect(result[:loop][:max_iterations]).to eq(500)
    end
  end

  # IMP-957902bf8474: reset_ralph_loop's destructive reset! was the only
  # terminal-legal transition reachable via this tool — reopen_ralph_loop
  # exposes the non-destructive RalphLoop#reopen! escape hatch without a
  # direct DB write.
  describe "reopen_ralph_loop" do
    it "reopens a completed loop to running without touching iterations" do
      ralph_loop.update!(status: "completed", completed_at: Time.current)
      create(:ai_ralph_iteration, ralph_loop: ralph_loop, iteration_number: 1)

      result = tool.execute(params: { action: "reopen_ralph_loop", loop_id: ralph_loop.id })

      expect(result[:success]).to be true
      expect(ralph_loop.reload.status).to eq("running")
      expect(ralph_loop.ralph_iterations.count).to eq(1)
    end

    it "refuses to reopen a non-terminal loop" do
      result = tool.execute(params: { action: "reopen_ralph_loop", loop_id: ralph_loop.id }) # default status: pending

      expect(result[:success]).to be false
      expect(result[:error]).to match(/not terminal|nothing to reopen/i)
    end

    it "returns an error for an unknown loop" do
      result = tool.execute(params: { action: "reopen_ralph_loop", loop_id: "missing" })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/not found/)
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Tools::RalphLoopTool do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:tool) { described_class.new(account: account, user: user) }
  let(:ralph_loop) { create(:ai_ralph_loop, account: account, name: "spec-loop") }

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

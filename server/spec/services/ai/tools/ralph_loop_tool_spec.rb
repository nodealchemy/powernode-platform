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
end

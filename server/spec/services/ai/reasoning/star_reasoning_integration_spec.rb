# frozen_string_literal: true

require "rails_helper"

RSpec.describe "STAR reasoning integration with AgentToolBridgeService" do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:provider) { create(:ai_provider, account: account, is_active: true) }
  let(:agent) do
    create(:ai_agent, account: account, provider: provider, creator: user,
           mcp_metadata: { "reasoning" => { "mode" => "star" } })
  end
  let(:bridge) { Ai::AgentToolBridgeService.new(agent: agent, account: account) }
  let(:llm_client) { instance_double(Ai::Llm::Client) }
  let(:model) { "gpt-4.1" }

  let(:star_json) do
    {
      situation: { analysis: "Test situation", constraints: ["c1"], context_factors: ["f1"] },
      task: { goal: "Test goal", implicit_constraints: ["ic1"], success_criteria: ["sc1"] },
      action: { steps: ["s1"], rationale: "Test rationale", alternatives_considered: ["a1"] },
      result: { expected_outcome: "Test outcome", risks: ["r1"], verification_approach: "Test verification" },
      confidence: 0.9
    }.to_json
  end

  let(:star_response) { Ai::Llm::Response.new(content: star_json) }

  let(:tool_loop_response) do
    Ai::Llm::Response.new(
      content: "Task completed based on STAR analysis",
      finish_reason: "stop",
      usage: { prompt_tokens: 100, completion_tokens: 50, total_tokens: 150 }
    )
  end

  before do
    # Stub tool loop — return text response without tool calls
    allow(llm_client).to receive(:complete_with_tools).and_return(tool_loop_response)
  end

  describe "execute_with_reasoning with reasoning_mode: :star" do
    it "invokes StarReasoningService" do
      allow(llm_client).to receive(:complete_structured).and_return(star_response)

      expect_any_instance_of(Ai::Reasoning::StarReasoningService)
        .to receive(:reason).and_call_original

      bridge.execute_with_reasoning(
        llm_client: llm_client,
        messages: [{ role: "user", content: "Build auth module" }],
        model: model,
        reasoning_mode: :star
      )
    end

    it "injects STAR reasoning into messages before tool loop" do
      allow(llm_client).to receive(:complete_structured).and_return(star_response)

      messages = [{ role: "user", content: "Build auth module" }]
      bridge.execute_with_reasoning(
        llm_client: llm_client,
        messages: messages,
        model: model,
        reasoning_mode: :star
      )

      # Messages should have the STAR reasoning injected
      assistant_msgs = messages.select { |m| m[:role] == "assistant" }
      expect(assistant_msgs.any? { |m| m[:content].include?("## Task (Goal Articulation)") }).to be true

      # Follow-up instruction should reference STAR
      user_msgs = messages.select { |m| m[:role] == "user" }
      expect(user_msgs.any? { |m| m[:content].include?("STAR analysis") }).to be true
    end

    it "includes reasoning result in return value" do
      allow(llm_client).to receive(:complete_structured).and_return(star_response)

      result = bridge.execute_with_reasoning(
        llm_client: llm_client,
        messages: [{ role: "user", content: "Build auth module" }],
        model: model,
        reasoning_mode: :star
      )

      expect(result[:reasoning]).to be_present
      expect(result[:reasoning][:task][:goal]).to eq("Test goal")
      expect(result[:reasoning][:confidence]).to eq(0.9)
    end

    it "skips STAR injection when confidence is 0.0" do
      failed_json = {
        situation: { analysis: "", constraints: [], context_factors: [] },
        task: { goal: "", implicit_constraints: [], success_criteria: [] },
        action: { steps: [], rationale: "", alternatives_considered: [] },
        result: { expected_outcome: "", risks: [], verification_approach: "" },
        confidence: 0.0
      }.to_json
      failed_response = Ai::Llm::Response.new(content: failed_json)
      allow(llm_client).to receive(:complete_structured).and_return(failed_response)

      messages = [{ role: "user", content: "Build auth module" }]
      bridge.execute_with_reasoning(
        llm_client: llm_client,
        messages: messages,
        model: model,
        reasoning_mode: :star
      )

      # No STAR content injected
      assistant_msgs = messages.select { |m| m[:role] == "assistant" }
      expect(assistant_msgs.none? { |m| m[:content]&.include?("STAR") }).to be true
    end

    context "with reflection_enabled: true" do
      let(:reflection_json) do
        {
          quality_score: 0.82,
          issues: [],
          improvements: ["Add error handling"],
          should_retry: false
        }
      end

      it "runs both STAR reasoning and reflection" do
        allow(llm_client).to receive(:complete_structured).and_return(star_response)

        reflection_response = Ai::Llm::Response.new(content: reflection_json.to_json)
        star_service = instance_double(Ai::Reasoning::StarReasoningService)
        allow(Ai::Reasoning::StarReasoningService).to receive(:new).and_return(star_service)
        allow(star_service).to receive(:reason).and_return(JSON.parse(star_json, symbolize_names: true))
        allow(star_service).to receive(:format_reasoning_for_injection).and_return("## STAR output")

        reflection_service = instance_double(Ai::Reasoning::ReflectionService)
        allow(Ai::Reasoning::ReflectionService).to receive(:new).and_return(reflection_service)
        allow(reflection_service).to receive(:reflect).and_return(reflection_json)

        result = bridge.execute_with_reasoning(
          llm_client: llm_client,
          messages: [{ role: "user", content: "Build auth module" }],
          model: model,
          reasoning_mode: :star,
          reflection_enabled: true
        )

        expect(result[:reasoning]).to be_present
        expect(result[:reflection]).to be_present
        expect(result[:reflection][:quality_score]).to eq(0.82)
      end
    end
  end

  describe "extract_context_from_messages" do
    it "extracts system messages as context" do
      messages = [
        { role: "system", content: "You are a helpful assistant with domain knowledge." },
        { role: "user", content: "Build auth" }
      ]

      context = bridge.send(:extract_context_from_messages, messages)
      expect(context).to include("helpful assistant with domain knowledge")
    end

    it "returns nil when no context is available" do
      messages = [{ role: "user", content: "Hello" }]

      context = bridge.send(:extract_context_from_messages, messages)
      expect(context).to be_nil
    end
  end
end

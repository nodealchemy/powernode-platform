# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Reasoning::StarReasoningService do
  let(:account) { create(:account) }
  let(:service) { described_class.new(account: account) }
  let(:llm_client) { instance_double(Ai::Llm::Client) }
  let(:model) { "gpt-4.1" }

  let(:valid_star_json) do
    {
      situation: {
        analysis: "We need to build a user auth module for a Rails API",
        constraints: ["Must use JWT tokens", "Must support token refresh"],
        context_factors: ["Existing Devise setup", "PostgreSQL database"]
      },
      task: {
        goal: "Implement complete JWT authentication with login, logout, and token refresh",
        implicit_constraints: [
          "Must handle token expiry gracefully",
          "Must prevent token replay attacks",
          "Must support concurrent sessions"
        ],
        success_criteria: [
          "Users can authenticate and receive JWT",
          "Expired tokens return 401",
          "Token refresh works without re-login"
        ]
      },
      action: {
        steps: [
          "Create auth service with JWT encode/decode",
          "Add login endpoint with credential validation",
          "Implement token refresh endpoint",
          "Add authentication middleware"
        ],
        rationale: "Service-first approach keeps controllers thin and logic testable",
        alternatives_considered: [
          "Devise JWT gem — too opinionated for our needs",
          "Session-based auth — doesn't fit API-only architecture"
        ]
      },
      result: {
        expected_outcome: "Fully functional JWT auth with login, logout, and refresh",
        risks: ["Token storage on client side", "Clock skew affecting expiry"],
        verification_approach: "Integration tests covering all auth flows plus edge cases"
      },
      confidence: 0.87
    }.to_json
  end

  let(:llm_response) do
    Ai::Llm::Response.new(content: valid_star_json)
  end

  describe "#reason" do
    context "with valid LLM response" do
      before do
        allow(llm_client).to receive(:complete_structured).and_return(llm_response)
      end

      it "returns structured STAR result" do
        result = service.reason(task: "Build user auth", llm_client: llm_client, model: model)

        expect(result[:situation][:analysis]).to include("user auth module")
        expect(result[:situation][:constraints]).to include("Must use JWT tokens")
        expect(result[:situation][:context_factors]).to be_an(Array)
      end

      it "returns the task section with goal and implicit constraints" do
        result = service.reason(task: "Build user auth", llm_client: llm_client, model: model)

        expect(result[:task][:goal]).to include("JWT authentication")
        expect(result[:task][:implicit_constraints]).to include("Must handle token expiry gracefully")
        expect(result[:task][:success_criteria]).to be_present
      end

      it "returns the action section with steps and rationale" do
        result = service.reason(task: "Build user auth", llm_client: llm_client, model: model)

        expect(result[:action][:steps]).to include("Create auth service with JWT encode/decode")
        expect(result[:action][:rationale]).to be_present
        expect(result[:action][:alternatives_considered]).to be_an(Array)
      end

      it "returns the result section with outcome and risks" do
        result = service.reason(task: "Build user auth", llm_client: llm_client, model: model)

        expect(result[:result][:expected_outcome]).to be_present
        expect(result[:result][:risks]).to include("Clock skew affecting expiry")
        expect(result[:result][:verification_approach]).to be_present
      end

      it "returns confidence clamped between 0.0 and 1.0" do
        result = service.reason(task: "Build user auth", llm_client: llm_client, model: model)
        expect(result[:confidence]).to eq(0.87)
      end

      it "passes context to the LLM when provided" do
        allow(llm_client).to receive(:complete_structured).and_return(llm_response)

        service.reason(
          task: "Build user auth",
          context: "Rails 8 API with PostgreSQL",
          llm_client: llm_client,
          model: model
        )

        expect(llm_client).to have_received(:complete_structured).with(
          messages: [{ role: "user", content: "Context: Rails 8 API with PostgreSQL\n\nTask: Build user auth" }],
          schema: described_class::STAR_SCHEMA,
          model: model,
          system_prompt: described_class::SYSTEM_PROMPT
        )
      end

      it "builds messages without context when none provided" do
        allow(llm_client).to receive(:complete_structured).and_return(llm_response)

        service.reason(task: "Build user auth", llm_client: llm_client, model: model)

        expect(llm_client).to have_received(:complete_structured).with(
          messages: [{ role: "user", content: "Task: Build user auth" }],
          schema: described_class::STAR_SCHEMA,
          model: model,
          system_prompt: described_class::SYSTEM_PROMPT
        )
      end
    end

    context "with malformed response" do
      it "returns fallback result when keys are missing" do
        partial_json = { situation: { analysis: "test" }, confidence: 0.5 }.to_json
        response = Ai::Llm::Response.new(content: partial_json)
        allow(llm_client).to receive(:complete_structured).and_return(response)

        result = service.reason(task: "test", llm_client: llm_client, model: model)

        # Missing nested keys cause NoMethodError, caught by rescue → fallback
        expect(result[:confidence]).to eq(0.0)
      end
    end

    context "when LLM raises an error" do
      before do
        allow(llm_client).to receive(:complete_structured)
          .and_raise(StandardError, "Connection timeout")
      end

      it "returns fallback result with zero confidence" do
        result = service.reason(task: "Build user auth", llm_client: llm_client, model: model)

        expect(result[:confidence]).to eq(0.0)
        expect(result[:situation][:analysis]).to eq("")
        expect(result[:task][:goal]).to eq("")
        expect(result[:action][:steps]).to eq([])
        expect(result[:result][:expected_outcome]).to eq("")
      end
    end

    context "with confidence out of range" do
      it "clamps confidence above 1.0 to 1.0" do
        json = { situation: { analysis: "x", constraints: [], context_factors: [] },
                 task: { goal: "x", implicit_constraints: [], success_criteria: [] },
                 action: { steps: [], rationale: "x", alternatives_considered: [] },
                 result: { expected_outcome: "x", risks: [], verification_approach: "x" },
                 confidence: 1.5 }.to_json
        response = Ai::Llm::Response.new(content: json)
        allow(llm_client).to receive(:complete_structured).and_return(response)

        result = service.reason(task: "test", llm_client: llm_client, model: model)
        expect(result[:confidence]).to eq(1.0)
      end

      it "clamps negative confidence to 0.0" do
        json = { situation: { analysis: "x", constraints: [], context_factors: [] },
                 task: { goal: "x", implicit_constraints: [], success_criteria: [] },
                 action: { steps: [], rationale: "x", alternatives_considered: [] },
                 result: { expected_outcome: "x", risks: [], verification_approach: "x" },
                 confidence: -0.5 }.to_json
        response = Ai::Llm::Response.new(content: json)
        allow(llm_client).to receive(:complete_structured).and_return(response)

        result = service.reason(task: "test", llm_client: llm_client, model: model)
        expect(result[:confidence]).to eq(0.0)
      end
    end
  end

  describe "#format_reasoning_for_injection" do
    let(:star_result) do
      {
        situation: {
          analysis: "Current system lacks authentication",
          constraints: ["JWT required"],
          context_factors: ["Rails API"]
        },
        task: {
          goal: "Implement JWT auth",
          implicit_constraints: ["Handle token expiry"],
          success_criteria: ["Users can login"]
        },
        action: {
          steps: ["Create service", "Add endpoint"],
          rationale: "Service-first approach",
          alternatives_considered: ["Devise gem"]
        },
        result: {
          expected_outcome: "Working auth system",
          risks: ["Token storage"],
          verification_approach: "Integration tests"
        },
        confidence: 0.85
      }
    end

    it "produces readable output with all four STAR sections" do
      text = service.format_reasoning_for_injection(star_result)

      expect(text).to include("## Situation")
      expect(text).to include("Current system lacks authentication")
      expect(text).to include("## Task (Goal Articulation)")
      expect(text).to include("Goal: Implement JWT auth")
      expect(text).to include("## Action")
      expect(text).to include("1. Create service")
      expect(text).to include("2. Add endpoint")
      expect(text).to include("## Expected Result")
      expect(text).to include("Working auth system")
      expect(text).to include("Confidence: 0.85")
    end

    it "includes implicit constraints in the task section" do
      text = service.format_reasoning_for_injection(star_result)
      expect(text).to include("Implicit constraints: Handle token expiry")
    end

    it "includes success criteria in the task section" do
      text = service.format_reasoning_for_injection(star_result)
      expect(text).to include("Success criteria: Users can login")
    end

    it "includes risks and verification in the result section" do
      text = service.format_reasoning_for_injection(star_result)
      expect(text).to include("Risks: Token storage")
      expect(text).to include("Verification: Integration tests")
    end
  end

  describe "STAR_SCHEMA" do
    it "has all required top-level keys" do
      required = described_class::STAR_SCHEMA[:schema][:required]
      expect(required).to contain_exactly("situation", "task", "action", "result", "confidence")
    end

    it "has required keys in the task sub-schema" do
      task_required = described_class::STAR_SCHEMA[:schema][:properties][:task][:required]
      expect(task_required).to contain_exactly("goal", "implicit_constraints", "success_criteria")
    end
  end
end

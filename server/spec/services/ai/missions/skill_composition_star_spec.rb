# frozen_string_literal: true

require "rails_helper"

RSpec.describe "STAR-enhanced skill composition", type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:mission) do
    create(:ai_mission,
      account: account,
      created_by: user,
      objective: "Build user authentication with JWT tokens",
      configuration: configuration
    )
  end
  let(:llm_client) { instance_double(Ai::Llm::Client) }
  let(:model) { "gpt-4.1" }

  let(:star_json) do
    {
      situation: {
        analysis: "Authentication phase for a Rails API",
        constraints: ["Must use JWT"],
        context_factors: ["Rails 8 API"]
      },
      task: {
        goal: "Validate authentication flows including login, logout, token refresh, and session expiry",
        implicit_constraints: [
          "Must test both success and failure paths",
          "Must verify JWT token handling"
        ],
        success_criteria: [
          "All auth endpoints tested",
          "Edge cases covered"
        ]
      },
      action: {
        steps: [
          "Unit test auth service",
          "Integration test login endpoint",
          "Test token expiry edge cases"
        ],
        rationale: "Comprehensive coverage ensures reliability",
        alternatives_considered: ["Manual testing only"]
      },
      result: {
        expected_outcome: "Complete test coverage for auth module",
        risks: ["Flaky tests on CI"],
        verification_approach: "Run full suite in CI"
      },
      confidence: 0.85
    }.to_json
  end

  let(:star_response) { Ai::Llm::Response.new(content: star_json) }

  before do
    allow(WorkerJobService).to receive(:enqueue_job).and_return(true)
  end

  describe "compose! with STAR enabled" do
    let(:configuration) { { "reasoning" => { "mode" => "star" } } }

    before do
      allow(llm_client).to receive(:complete_structured).and_return(star_response)
    end

    context "when SemanticToolDiscoveryService is available" do
      let(:discovery_service) { instance_double(Ai::Tools::SemanticToolDiscoveryService) }

      before do
        allow(Ai::Tools::SemanticToolDiscoveryService).to receive(:new).and_return(discovery_service)
        allow(discovery_service).to receive(:discover).and_return([])
      end

      it "uses STAR-refined queries for skill discovery" do
        service = Ai::Missions::SkillCompositionService.new(
          mission: mission, llm_client: llm_client, model: model
        )

        service.compose!

        # Verify discovery was called with a richer query than the simple phase label
        expect(discovery_service).to have_received(:discover).at_least(:once) do |args|
          query = args[:query]
          # STAR-refined queries should contain articulated goals
          expect(query).to include("Validate authentication flows").or include(mission.objective)
        end
      end

      it "stores STAR reasoning in mission metadata" do
        service = Ai::Missions::SkillCompositionService.new(
          mission: mission, llm_client: llm_client, model: model
        )

        service.compose!

        mission.reload
        star_reasoning = mission.metadata&.dig("star_reasoning")
        expect(star_reasoning).to be_present
        # At least one phase should have STAR reasoning stored
        expect(star_reasoning.values.any? { |v| v["goal"].present? }).to be true
      end

      it "includes implicit constraints in task metadata" do
        service = Ai::Missions::SkillCompositionService.new(
          mission: mission, llm_client: llm_client, model: model
        )

        service.compose!

        mission.reload
        star_reasoning = mission.metadata&.dig("star_reasoning")
        constraints = star_reasoning&.values&.flat_map { |v| v["implicit_constraints"] || [] }
        expect(constraints).to be_present
      end
    end
  end

  describe "compose! without STAR (default behavior)" do
    let(:configuration) { {} }

    context "when SemanticToolDiscoveryService is available" do
      let(:discovery_service) { instance_double(Ai::Tools::SemanticToolDiscoveryService) }

      before do
        allow(Ai::Tools::SemanticToolDiscoveryService).to receive(:new).and_return(discovery_service)
        allow(discovery_service).to receive(:discover).and_return([])
      end

      it "uses simple query without LLM call" do
        service = Ai::Missions::SkillCompositionService.new(mission: mission)
        service.compose!

        # Should NOT call complete_structured since no LLM client provided
        expect(discovery_service).to have_received(:discover).at_least(:once)
      end

      it "does not require llm_client parameter" do
        service = Ai::Missions::SkillCompositionService.new(mission: mission)
        expect { service.compose! }.not_to raise_error
      end
    end
  end

  describe "compose! with STAR fallback on LLM error" do
    let(:configuration) { { "reasoning" => { "mode" => "star" } } }

    context "when SemanticToolDiscoveryService is available" do
      let(:discovery_service) { instance_double(Ai::Tools::SemanticToolDiscoveryService) }

      before do
        allow(Ai::Tools::SemanticToolDiscoveryService).to receive(:new).and_return(discovery_service)
        allow(discovery_service).to receive(:discover).and_return([])
        allow(llm_client).to receive(:complete_structured)
          .and_raise(StandardError, "LLM connection failed")
      end

      it "falls back to simple query on LLM error" do
        service = Ai::Missions::SkillCompositionService.new(
          mission: mission, llm_client: llm_client, model: model
        )

        expect { service.compose! }.not_to raise_error

        # Discovery should still be called with the simple fallback query
        expect(discovery_service).to have_received(:discover).at_least(:once)
      end
    end
  end

  describe "compose! with STAR but zero confidence" do
    let(:configuration) { { "reasoning" => { "mode" => "star" } } }

    context "when SemanticToolDiscoveryService is available" do
      let(:discovery_service) { instance_double(Ai::Tools::SemanticToolDiscoveryService) }
      let(:zero_confidence_json) do
        {
          situation: { analysis: "", constraints: [], context_factors: [] },
          task: { goal: "", implicit_constraints: [], success_criteria: [] },
          action: { steps: [], rationale: "", alternatives_considered: [] },
          result: { expected_outcome: "", risks: [], verification_approach: "" },
          confidence: 0.0
        }.to_json
      end

      before do
        allow(Ai::Tools::SemanticToolDiscoveryService).to receive(:new).and_return(discovery_service)
        allow(discovery_service).to receive(:discover).and_return([])
        allow(llm_client).to receive(:complete_structured)
          .and_return(Ai::Llm::Response.new(content: zero_confidence_json))
      end

      it "falls back to simple query when STAR returns zero confidence" do
        service = Ai::Missions::SkillCompositionService.new(
          mission: mission, llm_client: llm_client, model: model
        )

        service.compose!

        # Should use simple query as fallback
        expect(discovery_service).to have_received(:discover).at_least(:once) do |args|
          # Simple queries contain the humanized phase key
          expect(args[:query]).to be_present
        end
      end
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

# Phase integrity for infrastructure missions (F-c 019fe5d0-d68f,
# F-d 019fe5d0-ed2d, F6 019fe4c5-03a4 — observed across dryrun runs a–d):
#
#   - capture_intent, compose_plan and execute completed their work and then
#     SAT there until someone called /advance by hand (verify was the only
#     phase advancing itself);
#   - a manual /advance out of compose_plan succeeded with NO plan in
#     existence, handing review_plan nothing to review;
#   - the composer returning nil rendered SUCCESS with plan_id: null and the
#     mission died silently.
#
# New contract: phase endpoints auto-advance when their completion criteria
# hold (brief complete / plan stamped), record why when they don't, and the
# orchestrator REFUSES to advance an infrastructure mission out of a phase
# whose artifact is missing.
RSpec.describe "Internal AI provisioning phase integrity", type: :request do
  include_context "internal api auth"

  let(:mission_account) { create(:account) }
  let(:mission_user) { create(:user, account: mission_account) }

  def make_mission(phase:, configuration: {})
    create(
      :ai_mission,
      account: mission_account, created_by: mission_user,
      mission_type: "infrastructure", status: "active", current_phase: phase,
      custom_phases: [
        { "key" => "capture_intent", "label" => "Capture", "order" => 0 },
        { "key" => "compose_plan", "label" => "Compose", "order" => 1 },
        { "key" => "review_plan", "label" => "Review", "order" => 2, "requires_approval" => true }
      ],
      configuration: configuration
    )
  end

  describe "capture_intent auto-advance (F6)" do
    let(:complete_brief) do
      { "intent" => "provision a stack", "use_case" => "validation",
        "scale" => { "initial" => 1, "target" => 1 }, "regions" => %w[dna],
        "budget_cap_usd_monthly" => 5 }
    end

    it "advances to compose_plan when the captured brief is complete" do
      mission = make_mission(phase: "capture_intent")
      allow_any_instance_of(Ai::Provisioning::IntentCaptureService)
        .to receive(:capture).and_return(brief: complete_brief, missing_fields: [])

      post "/api/v1/internal/ai/provisioning/missions/#{mission.id}/capture_intent",
           headers: service_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(mission.reload.current_phase).to eq("compose_plan")
    end

    it "stays in capture_intent — and records what is missing — when fields are absent" do
      mission = make_mission(phase: "capture_intent")
      allow_any_instance_of(Ai::Provisioning::IntentCaptureService)
        .to receive(:capture).and_return(brief: complete_brief.merge("use_case" => nil),
                                         missing_fields: [ :use_case ])

      post "/api/v1/internal/ai/provisioning/missions/#{mission.id}/capture_intent",
           headers: service_headers, as: :json

      expect(response).to have_http_status(:ok)
      mission.reload
      expect(mission.current_phase).to eq("capture_intent")
      expect(mission.configuration["brief_missing_fields"]).to eq([ "use_case" ])
    end
  end

  describe "compose_plan (F-c + F6)" do
    let(:brief_config) do
      { "brief" => { "intent" => "provision", "use_case" => "validation",
                     "scale" => { "initial" => 1, "target" => 1 }, "regions" => %w[dna],
                     "budget_cap_usd_monthly" => 5 } }
    end

    def stub_composer(result)
      composer = double("composer", compose!: result)
      allow_any_instance_of(Ai::Missions::ComposerRouter).to receive(:select).and_return(composer)
      allow(composer).to receive(:cap_exceeded_payload).and_return(nil)
      composer
    end

    it "advances to review_plan when a plan was composed and stamped" do
      mission = make_mission(phase: "compose_plan", configuration: brief_config)
      agent = create(:ai_agent, account: mission_account, creator: mission_user, status: "active")
      goal = Ai::AgentGoal.create!(account: mission_account, agent: agent, title: "G",
                                   goal_type: "creation", status: "pending", priority: 3,
                                   progress: 0.0, success_criteria: {})
      plan = Ai::GoalPlan.create!(account: mission_account, goal: goal, agent: agent,
                                  status: "draft", version: 1, plan_data: {})
      stub_composer(plan)

      post "/api/v1/internal/ai/provisioning/missions/#{mission.id}/compose_plan",
           headers: service_headers, as: :json

      expect(response).to have_http_status(:ok)
      mission.reload
      expect(mission.configuration.dig("plan", "plan_id")).to eq(plan.id)
      expect(mission.current_phase).to eq("review_plan")
    end

    it "FAILS loudly — no advance, error recorded, 422 — when the composer returns nil" do
      mission = make_mission(phase: "compose_plan", configuration: brief_config)
      stub_composer(nil)

      post "/api/v1/internal/ai/provisioning/missions/#{mission.id}/compose_plan",
           headers: service_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      mission.reload
      expect(mission.current_phase).to eq("compose_plan")
      expect(mission.error_message.to_s).to match(/no plan/i)
    end
  end

  describe "orchestrator artifact preconditions (F-d)" do
    def orchestrator_for(mission)
      Ai::Missions::OrchestratorService.new(mission: mission)
    end

    it "refuses to advance out of compose_plan with no composed plan" do
      mission = make_mission(phase: "compose_plan", configuration: { "brief" => { "intent" => "x" } })

      expect { orchestrator_for(mission).advance! }
        .to raise_error(Ai::Missions::OrchestratorService::OrchestrationError, /no composed plan|plan_id/i)
      expect(mission.reload.current_phase).to eq("compose_plan")
    end

    it "refuses to advance out of capture_intent with an incomplete brief" do
      mission = make_mission(phase: "capture_intent",
                             configuration: { "brief" => { "intent" => "x" },
                                              "brief_missing_fields" => %w[use_case] })

      expect { orchestrator_for(mission).advance! }
        .to raise_error(Ai::Missions::OrchestratorService::OrchestrationError, /missing|use_case/i)
      expect(mission.reload.current_phase).to eq("capture_intent")
    end

    it "refuses to advance out of capture_intent with no brief at all" do
      mission = make_mission(phase: "capture_intent")

      expect { orchestrator_for(mission).advance! }
        .to raise_error(Ai::Missions::OrchestratorService::OrchestrationError, /no brief/i)
    end

    it "advances out of compose_plan normally once the plan pointer exists" do
      mission = make_mission(phase: "compose_plan",
                             configuration: { "brief" => { "intent" => "x" },
                                              "plan" => { "plan_id" => SecureRandom.uuid } })

      orchestrator_for(mission).advance!
      expect(mission.reload.current_phase).to eq("review_plan")
    end

    it "does not gate non-infrastructure missions" do
      mission = create(:ai_mission, account: mission_account, created_by: mission_user,
                                    mission_type: "development", status: "active",
                                    current_phase: "compose_plan",
                                    custom_phases: [
                                      { "key" => "compose_plan", "label" => "Compose", "order" => 0 },
                                      { "key" => "review_plan", "label" => "Review", "order" => 1 }
                                    ])
      expect { orchestrator_for(mission).advance! }.not_to raise_error
    end
  end
end

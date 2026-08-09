# frozen_string_literal: true

require "rails_helper"

# Coverage for the HYBRID COMPOSER ROUTING in the internal compose_plan
# endpoint. The controller picks ONE composer via a side-effect-free predicate
# BEFORE composing (PlanComposerService persists on success, so a discarded
# probe would leak a real plan):
#
#   * recognized provisioning brief  -> ::Ai::Provisioning::PlanComposerService
#   * novel / general intent         -> ::Ai::Missions::MissionComposer
#
# These specs assert WHICH composer class is instantiated + used, with compose!
# stubbed so the real LLM / DAG synthesis never runs.
RSpec.describe "Internal AI provisioning compose_plan routing", type: :request do
  include_context "internal api auth"

  # The mission's own account (distinct from the worker's account — load_mission
  # resolves by id without account-scoping, mirroring production).
  let(:mission_account) { create(:account) }
  let(:mission_user) { create(:user, account: mission_account) }

  def create_mission(brief)
    create(
      :ai_mission,
      account: mission_account,
      created_by: mission_user,
      mission_type: "infrastructure",
      custom_phases: [{ "key" => "compose_plan", "label" => "Compose plan", "order" => 0 }],
      configuration: { "brief" => brief }
    )
  end

  def post_compose(mission)
    post "/api/v1/internal/ai/provisioning/missions/#{mission.id}/compose_plan",
         headers: service_headers
  end

  # A persisted-looking plan stand-in. compose! is stubbed to return this so we
  # never invoke the LLM or touch GoalDecompositionService.
  let(:fake_plan) { instance_double(::Ai::GoalPlan, id: "plan-#{SecureRandom.uuid}") }

  describe "(a) recognized provisioning brief -> PlanComposerService" do
    # use_case "database" is a key in PlanComposerService::ROLE_MODULE_FOR_USE_CASE,
    # so the predicate recognizes it as a provisioning scenario.
    let(:provisioning_brief) do
      {
        "intent" => "Spin up a 3-node Postgres cluster",
        "use_case" => "database",
        "scale" => { "initial" => 3, "target" => 5, "growth_profile" => "linear" },
        "regions" => ["us-east-1"],
        "budget_cap_usd_monthly" => 200.0,
        "preferred_provider" => nil
      }
    end
    let(:mission) { create_mission(provisioning_brief) }

    it "instantiates and uses the PROVISIONING composer (not MissionComposer)" do
      composer = instance_double(::Ai::Provisioning::PlanComposerService)
      expect(::Ai::Provisioning::PlanComposerService).to receive(:new)
        .with(account: mission.account, mission: mission)
        .and_return(composer)
      expect(composer).to receive(:compose!).and_return(fake_plan)
      expect(::Ai::Missions::MissionComposer).not_to receive(:new)

      post_compose(mission)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["success"]).to be true
      expect(body["data"]["plan_id"]).to eq(fake_plan.id)
      expect(body["data"]["mission_id"]).to eq(mission.id)
    end

    # Provisioning-shaped fields (preferred_provider) without a recognized
    # use_case still route to PlanComposerService.
    context "when use_case is unknown but provisioning fields are present" do
      let(:provisioning_brief) do
        {
          "intent" => "give me a box",
          "use_case" => "something_bespoke",
          "preferred_provider" => "aws",
          "regions" => []
        }
      end

      it "routes to the PROVISIONING composer on the provisioning-shaped signal" do
        composer = instance_double(::Ai::Provisioning::PlanComposerService)
        expect(::Ai::Provisioning::PlanComposerService).to receive(:new).and_return(composer)
        expect(composer).to receive(:compose!).and_return(fake_plan)
        expect(::Ai::Missions::MissionComposer).not_to receive(:new)

        post_compose(mission)

        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "(b) novel / general intent -> MissionComposer" do
    # No recognized use_case, no regions, no preferred_provider, no runtime
    # module hint, no positive scale.initial — a general intent.
    let(:novel_brief) do
      {
        "intent" => "orchestrate a federated multi-cluster mesh with public ingress",
        "use_case" => "bespoke_platform_topology",
        "regions" => [],
        "preferred_provider" => nil,
        "runtime_hint" => "none"
      }
    end
    let(:mission) { create_mission(novel_brief) }

    it "instantiates and uses the GENERAL composer (not PlanComposerService)" do
      composer = instance_double(::Ai::Missions::MissionComposer)
      expect(::Ai::Missions::MissionComposer).to receive(:new)
        .with(account: mission.account, mission: mission, intent: novel_brief["intent"])
        .and_return(composer)
      expect(composer).to receive(:compose!).and_return(fake_plan)
      expect(::Ai::Provisioning::PlanComposerService).not_to receive(:new)

      post_compose(mission)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["success"]).to be true
      expect(body["data"]["plan_id"]).to eq(fake_plan.id)
      expect(body["data"]["mission_id"]).to eq(mission.id)
    end
  end

  describe "(c) over-budget (compose! -> nil) -> LOUD 422 with the cap payload" do
    # Cost-cap path: the chosen composer returns nil. This used to render
    # SUCCESS with plan_id: null — the F-c silent-death shape (IMP
    # 019fe5d0-d68f). It is now a 422 carrying requires_upgrade + the cap
    # payload, the mission records why, and we still never fall back to the
    # other composer (both are cost-capped).
    let(:provisioning_brief) do
      {
        "intent" => "Spin up a cache tier",
        "use_case" => "cache",
        "scale" => { "initial" => 2, "target" => 2 },
        "regions" => ["us-east-1"]
      }
    end
    let(:mission) { create_mission(provisioning_brief) }

    it "returns 422 with the cap details, records the reason, and never tries the other composer" do
      composer = instance_double(::Ai::Provisioning::PlanComposerService)
      expect(::Ai::Provisioning::PlanComposerService).to receive(:new).and_return(composer)
      expect(composer).to receive(:compose!).and_return(nil)
      allow(composer).to receive(:cap_exceeded_payload).and_return({ spent: 0.5, cap: 0.5, remaining: 0.0 })
      expect(::Ai::Missions::MissionComposer).not_to receive(:new)

      post_compose(mission)

      expect(response).to have_http_status(:unprocessable_content)
      body = JSON.parse(response.body)
      expect(body["success"]).to be false
      expect(body["error"]).to match(/cost cap/i)
      expect(mission.reload.error_message.to_s).to match(/cost cap/i)
      expect(mission.current_phase).not_to eq("review_plan")
    end
  end

  # Predicate-unit coverage (deterministic_provisioning?) lives in
  # spec/services/ai/missions/composer_router_spec.rb — the predicate now resides
  # in Ai::Missions::ComposerRouter (the single source of truth shared by all
  # compose entry points). The (a)/(b)/(c) request specs above exercise it
  # through the controller's real routing path.
end

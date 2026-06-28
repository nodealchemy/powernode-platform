# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Mission, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:created_by).class_name("User") }
    it { is_expected.to belong_to(:repository).class_name("Devops::GitRepository").optional }
    it { is_expected.to belong_to(:team).class_name("Ai::AgentTeam").optional }
    it { is_expected.to belong_to(:conversation).class_name("Ai::Conversation").optional }
    it { is_expected.to belong_to(:mission_template).class_name("Ai::MissionTemplate").optional }
    it { is_expected.to have_many(:approvals).class_name("Ai::MissionApproval") }

    # Self-Serve Hardening M4 Slice A — optional pointer at an
    # `Account::TeamDelegation` (per-team isolation). That class ships in the
    # business extension (private), so it is NOT loadable in core mode. The
    # shoulda `class_name` matcher constantizes both sides, which fails when
    # the target class is absent — assert the declared reflection options
    # directly instead (same core-safe pattern as the supply_chain file
    # association specs). Verifies macro, optionality, class_name, and FK
    # without forcing constant resolution.
    it "declares an optional delegation belongs_to backed by Account::TeamDelegation" do
      reflection = described_class.reflect_on_association(:delegation)
      expect(reflection).to be_present
      expect(reflection.macro).to eq(:belongs_to)
      expect(reflection.options[:optional]).to be(true)
      expect(reflection.options[:class_name]).to eq("::Account::TeamDelegation")
      expect(reflection.options[:foreign_key]).to eq("delegation_id")
    end
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:mission_type) }
    it { is_expected.to validate_inclusion_of(:mission_type).in_array(Ai::Mission::MISSION_TYPES) }
    it { is_expected.to validate_inclusion_of(:status).in_array(Ai::Mission::STATUSES) }

    it "includes content_production as a supported mission_type" do
      expect(Ai::Mission::MISSION_TYPES).to include("content_production")
    end

    it "is valid as a content_production mission (no repository required)" do
      mission = build(:ai_mission, :content_production)
      expect(mission).to be_valid
    end

    # Regression: OrchestratorService#complete_mission! writes the terminal
    # sentinel current_phase="completed" for EVERY mission type, even when a
    # template's own phase pipeline ends earlier (e.g. reap, adapting). Before
    # this guard no mission could ever complete — the inclusion validation
    # rejected "completed" for those types. See audit 2026-06-09 finding F1-02.
    it "accepts current_phase='completed' even when the template pipeline ends earlier" do
      mission = build(:ai_mission)
      mission.mission_template = nil
      mission.custom_phases = [ { "key" => "reap", "order" => 0 } ]
      mission.current_phase = "completed"
      expect(mission).to be_valid
    end

    it "still rejects a current_phase that is neither a template phase nor the terminal sentinel" do
      mission = build(:ai_mission)
      mission.mission_template = nil
      mission.custom_phases = [ { "key" => "reap", "order" => 0 } ]
      mission.current_phase = "not_a_real_phase"
      expect(mission).not_to be_valid
      expect(mission.errors[:current_phase]).to be_present
    end
  end

  describe "repository validation for development type" do
    it "requires repository for development missions" do
      mission = build(:ai_mission, mission_type: "development")
      mission.repository = nil
      expect(mission).not_to be_valid
      expect(mission.errors[:repository]).to include("is required for development missions")
    end

    it "does not require repository for research missions" do
      mission = build(:ai_mission, :research)
      expect(mission).to be_valid
    end
  end

  describe "#phases_for_type" do
    it "returns phases from template for development type" do
      mission = build(:ai_mission, :development)
      expect(mission.phases_for_type).to include("analyzing", "executing", "completed")
      expect(mission.phases_for_type.length).to eq(12)
    end

    it "returns phases from template for research type" do
      mission = build(:ai_mission, :research)
      expect(mission.phases_for_type).to include("researching", "analyzing", "reporting", "completed")
      expect(mission.phases_for_type.length).to eq(4)
    end

    it "returns phases from template for operations type" do
      mission = build(:ai_mission, :operations)
      expect(mission.phases_for_type).to include("configuring", "executing", "verifying", "completed")
      expect(mission.phases_for_type.length).to eq(4)
    end

    it "returns phases from template for content_production type" do
      mission = build(:ai_mission, :content_production)
      expect(mission.phases_for_type).to eq(
        %w[brief script asset_generation composition render deliver completed]
      )
    end

    it "returns empty array without template or custom phases" do
      mission = build(:ai_mission)
      mission.mission_template = nil
      mission.custom_phases = nil
      expect(mission.phases_for_type).to eq([])
    end

    it "uses custom_phases when present" do
      custom = [
        { "key" => "step_one", "order" => 0 },
        { "key" => "step_two", "order" => 1 }
      ]
      mission = build(:ai_mission)
      mission.custom_phases = custom
      expect(mission.phases_for_type).to eq(%w[step_one step_two])
    end
  end

  describe "#terminal?" do
    it "returns true for completed missions" do
      mission = build(:ai_mission, status: "completed")
      expect(mission.terminal?).to be true
    end

    it "returns false for active missions" do
      mission = build(:ai_mission, status: "active")
      expect(mission.terminal?).to be false
    end
  end

  describe "#awaiting_approval?" do
    it "returns true when in approval gate phase" do
      mission = build(:ai_mission, current_phase: "awaiting_feature_approval")
      expect(mission.awaiting_approval?).to be true
    end

    it "returns false when in non-approval phase" do
      mission = build(:ai_mission, current_phase: "analyzing")
      expect(mission.awaiting_approval?).to be false
    end
  end

  describe "#approval_gate_phases" do
    it "returns gates from template" do
      mission = build(:ai_mission, :development)
      expect(mission.approval_gate_phases).to include("awaiting_feature_approval", "awaiting_prd_approval")
    end

    it "returns gates from custom_phases" do
      custom = [
        { "key" => "work", "order" => 0, "requires_approval" => false },
        { "key" => "review", "order" => 1, "requires_approval" => true }
      ]
      mission = build(:ai_mission)
      mission.custom_phases = custom
      expect(mission.approval_gate_phases).to eq(["review"])
    end
  end

  describe "#phase_progress" do
    it "returns 0 for first phase" do
      mission = build(:ai_mission, :development, current_phase: "analyzing")
      expect(mission.phase_progress).to eq(0)
    end

    it "returns 100 for completed phase" do
      mission = build(:ai_mission, :development, current_phase: "completed")
      expect(mission.phase_progress).to eq(100)
    end
  end

  describe "#save_as_template!" do
    it "creates an account template from the mission" do
      mission = create(:ai_mission, :development)
      template = mission.save_as_template!(name: "My Template")
      expect(template).to be_persisted
      expect(template.template_type).to eq("account")
      expect(template.mission_type).to eq("development")
      expect(template.name).to eq("My Template")
    end
  end

  describe "#requires_second_signature?" do
    let(:account) { create(:account) }
    let(:mission) do
      build(:ai_mission, account: account, custom_phases: [
        { "key" => "handoff", "label" => "Handoff", "order" => 0, "requires_approval" => true, "gate_name" => "handoff" },
        { "key" => "adapting", "label" => "Adapting", "order" => 1, "requires_approval" => false }
      ])
    end

    def stub_plan_features(features_hash)
      plan = double("Plan", features: features_hash)
      sub  = double("Subscription", plan: plan)
      allow(account).to receive(:active_subscription).and_return(sub)
    end

    it "returns false when not at the handoff phase" do
      mission.current_phase = "adapting"
      stub_plan_features("second_signature_required" => true)
      expect(mission.requires_second_signature?).to be false
    end

    it "returns false on Free/Pro tier (feature flag absent or false)" do
      mission.current_phase = "handoff"
      stub_plan_features("second_signature_required" => false)
      expect(mission.requires_second_signature?).to be false
    end

    it "returns false when features hash lacks the flag entirely" do
      mission.current_phase = "handoff"
      stub_plan_features({})
      expect(mission.requires_second_signature?).to be false
    end

    it "returns true on Business+ tier when the flag is enabled and at handoff" do
      mission.current_phase = "handoff"
      stub_plan_features("second_signature_required" => true)
      expect(mission.requires_second_signature?).to be true
    end

    it "returns false when active_subscription is missing (graceful chain)" do
      mission.current_phase = "handoff"
      allow(account).to receive(:active_subscription).and_return(nil)
      expect(mission.requires_second_signature?).to be false
    end

    it "returns false when account itself is nil (defensive)" do
      mission.current_phase = "handoff"
      allow(mission).to receive(:account).and_return(nil)
      expect(mission.requires_second_signature?).to be false
    end
  end

  describe "#distinct_approver_count" do
    let(:account) { create(:account) }
    let(:user_a) { create(:user, account: account) }
    let(:user_b) { create(:user, account: account) }
    let(:mission) { create(:ai_mission, account: account) }

    it "counts distinct approved approvers at the gate" do
      create(:ai_mission_approval, mission: mission, account: account, user: user_a, gate: "handoff", decision: "approved")
      create(:ai_mission_approval, mission: mission, account: account, user: user_b, gate: "handoff", decision: "approved")
      expect(mission.distinct_approver_count("handoff")).to eq(2)
    end

    it "counts the same user twice as one" do
      create(:ai_mission_approval, mission: mission, account: account, user: user_a, gate: "handoff", decision: "approved")
      create(:ai_mission_approval, mission: mission, account: account, user: user_a, gate: "handoff", decision: "approved")
      expect(mission.distinct_approver_count("handoff")).to eq(1)
    end

    it "ignores rejected approvals" do
      create(:ai_mission_approval, mission: mission, account: account, user: user_a, gate: "handoff", decision: "rejected", comment: "no")
      expect(mission.distinct_approver_count("handoff")).to eq(0)
    end

    it "scopes to the requested gate" do
      create(:ai_mission_approval, mission: mission, account: account, user: user_a, gate: "feature_selection", decision: "approved")
      expect(mission.distinct_approver_count("handoff")).to eq(0)
    end
  end

  describe "scopes" do
    let!(:active_mission) { create(:ai_mission, :active) }
    let!(:completed_mission) { create(:ai_mission, :completed) }
    let!(:draft_mission) { create(:ai_mission) }

    it "filters active missions" do
      expect(Ai::Mission.active).to include(active_mission)
      expect(Ai::Mission.active).not_to include(completed_mission)
    end

    it "filters completed missions" do
      expect(Ai::Mission.completed).to include(completed_mission)
      expect(Ai::Mission.completed).not_to include(active_mission)
    end

    it "filters draft missions" do
      expect(Ai::Mission.draft).to include(draft_mission)
    end
  end

  # ai_missions.ralph_loop_id and ai_ralph_loops.mission_id form a circular
  # FK (the two-way link is written by Missions::SkillCompositionService).
  # Both constraints are ON DELETE SET NULL so a linked pair is destroyable
  # from either side — without it, both destroy endpoints 500'd with
  # PG::ForeignKeyViolation and the account-termination dependent: :destroy
  # chain (loops before missions) failed for any account with a linked pair.
  describe "destroying linked mission <-> ralph loop pairs" do
    let(:account) { create(:account) }
    let(:mission) { create(:ai_mission, account: account) }
    let(:ralph_loop) { create(:ai_ralph_loop, account: account, mission: mission) }

    before { mission.update!(ralph_loop_id: ralph_loop.id) }

    it "destroys the mission and nullifies the loop's back-reference" do
      expect { mission.destroy! }.not_to raise_error
      expect(ralph_loop.reload.mission_id).to be_nil
    end

    it "destroys the loop and nullifies the mission's forward reference" do
      expect { ralph_loop.destroy! }.not_to raise_error
      expect(mission.reload.ralph_loop_id).to be_nil
    end
  end
end

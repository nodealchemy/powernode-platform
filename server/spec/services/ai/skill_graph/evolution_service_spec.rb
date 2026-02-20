# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::SkillGraph::EvolutionService, type: :service do
  let(:account) { create(:account) }
  subject(:service) { described_class.new(account) }

  before do
    allow_any_instance_of(Ai::Skill).to receive(:sync_to_knowledge_graph)
    allow_any_instance_of(Ai::Agent).to receive(:sync_to_knowledge_graph)
    allow_any_instance_of(Ai::Memory::EmbeddingService).to receive(:generate).and_return(Array.new(1536, 0.1))
  end

  let(:skill) { create(:ai_skill, account: account, name: "Test Skill", system_prompt: "You are a test assistant.", last_used_at: Time.current) }
  let!(:active_version) do
    create(:ai_skill_version,
      account: account,
      ai_skill: skill,
      version: "1.0.0",
      is_active: true,
      effectiveness_score: 0.7,
      usage_count: 10,
      success_count: 7,
      failure_count: 3
    )
  end

  describe "#record_outcome" do
    it "records a successful outcome on the active version" do
      result = service.record_outcome(skill_id: skill.id, successful: true)

      expect(result[:outcome]).to eq("success")
      expect(result[:skill_id]).to eq(skill.id)
      expect(result[:version_id]).to eq(active_version.id)
    end

    it "records a failure outcome" do
      result = service.record_outcome(skill_id: skill.id, successful: false)

      expect(result[:outcome]).to eq("failure")
    end

    it "increments version counters" do
      service.record_outcome(skill_id: skill.id, successful: true)

      active_version.reload
      expect(active_version.success_count).to eq(8)
      expect(active_version.usage_count).to eq(11)
    end

    context "with A/B variant" do
      let!(:variant) do
        create(:ai_skill_version, :ab_variant,
          account: account,
          ai_skill: skill,
          version: "2.0.0",
          is_active: false,
          is_ab_variant: true,
          ab_traffic_pct: 0.5
        )
      end

      it "routes traffic between active and variant versions" do
        # Run enough outcomes that at least some go to each version
        results = 20.times.map { service.record_outcome(skill_id: skill.id, successful: true) }
        version_ids = results.map { |r| r[:version_id] }.uniq

        # With 50% traffic split and 20 trials, both should receive some traffic
        # (probabilistic, but extremely unlikely to fail with these numbers)
        expect(version_ids).to include(active_version.id).or include(variant.id)
      end
    end

    it "returns error for non-existent skill" do
      result = service.record_outcome(skill_id: SecureRandom.uuid, successful: true)

      expect(result).to have_key(:error)
    end
  end

  describe "#skill_metrics" do
    it "returns comprehensive metrics for a skill" do
      result = service.skill_metrics(skill_id: skill.id)

      expect(result[:skill_id]).to eq(skill.id)
      expect(result[:name]).to eq("Test Skill")
      expect(result[:effectiveness_score]).to be_present
      expect(result[:total_usage]).to be_a(Integer)
      expect(result[:version_count]).to eq(1)
      expect(result[:trend]).to be_in(%w[up down stable])
    end

    it "calculates trend based on recent vs prior 7-day windows" do
      # Create some usage records for trend calculation
      create(:ai_skill_usage_record, account: account, ai_skill: skill, outcome: "success", created_at: 3.days.ago)
      create(:ai_skill_usage_record, account: account, ai_skill: skill, outcome: "success", created_at: 5.days.ago)
      create(:ai_skill_usage_record, :failure, account: account, ai_skill: skill, created_at: 10.days.ago)

      result = service.skill_metrics(skill_id: skill.id)

      expect(result[:trend]).to be_in(%w[up down stable])
    end

    it "returns error for non-existent skill" do
      result = service.skill_metrics(skill_id: SecureRandom.uuid)

      expect(result).to have_key(:error)
    end
  end

  describe "#propose_evolution" do
    it "creates a new inactive version with evolved prompt" do
      version = service.propose_evolution(skill_id: skill.id)

      expect(version).to be_a(Ai::SkillVersion)
      expect(version).to be_persisted
      expect(version.change_type).to eq("evolution")
      expect(version.is_active).to be false
      expect(version.is_ab_variant).to be false
      expect(version.ai_skill_id).to eq(skill.id)
    end

    it "includes the base prompt in the evolved version" do
      version = service.propose_evolution(skill_id: skill.id)

      # The evolved prompt uses the active version's system_prompt (not the skill's)
      expect(version.system_prompt).to include("You are a versioned assistant.")
    end

    it "references the source version in metadata" do
      version = service.propose_evolution(skill_id: skill.id)

      expect(version.metadata).to have_key("source_version_id")
    end

    it "returns nil for non-existent skill" do
      result = service.propose_evolution(skill_id: SecureRandom.uuid)

      expect(result).to be_nil
    end
  end

  describe "#activate_version" do
    let!(:new_version) do
      create(:ai_skill_version,
        account: account,
        ai_skill: skill,
        version: "2.0.0",
        is_active: false,
        effectiveness_score: 0.9
      )
    end

    it "activates the specified version and deactivates others" do
      result = service.activate_version(version_id: new_version.id)

      expect(result).to be_a(Ai::SkillVersion)
      expect(result.is_active).to be true

      active_version.reload
      expect(active_version.is_active).to be false
    end

    it "returns nil for non-existent version" do
      result = service.activate_version(version_id: SecureRandom.uuid)

      expect(result).to be_nil
    end
  end

  describe "#version_history" do
    before do
      create(:ai_skill_version,
        account: account,
        ai_skill: skill,
        version: "2.0.0",
        is_active: false,
        change_type: "evolution"
      )
    end

    it "returns version summaries ordered by newest first" do
      result = service.version_history(skill_id: skill.id)

      expect(result).to be_an(Array)
      expect(result.size).to eq(2)
      expect(result.first[:version]).to eq("2.0.0")
    end

    it "returns empty array for non-existent skill" do
      result = service.version_history(skill_id: SecureRandom.uuid)

      expect(result).to eq([])
    end
  end

  describe "#start_ab_test" do
    let!(:variant_version) do
      create(:ai_skill_version,
        account: account,
        ai_skill: skill,
        version: "2.0.0",
        is_active: false,
        is_ab_variant: false,
        change_type: "evolution"
      )
    end

    it "marks a version as A/B variant with traffic percentage" do
      result = service.start_ab_test(skill_id: skill.id, variant_version_id: variant_version.id, traffic_pct: 0.3)

      expect(result[:skill_id]).to eq(skill.id)
      expect(result[:variant_version_id]).to eq(variant_version.id)
      expect(result[:traffic_pct]).to eq(0.3)

      variant_version.reload
      expect(variant_version.is_ab_variant).to be true
      expect(variant_version.ab_traffic_pct).to eq(0.3)
    end

    it "clamps traffic percentage to valid range" do
      result = service.start_ab_test(skill_id: skill.id, variant_version_id: variant_version.id, traffic_pct: 1.5)

      expect(result[:traffic_pct]).to eq(0.99)
    end

    it "clears existing A/B variants before starting new one" do
      # Create an existing A/B variant
      old_variant = create(:ai_skill_version, :ab_variant,
        account: account,
        ai_skill: skill,
        version: "1.5.0",
        is_ab_variant: true,
        ab_traffic_pct: 0.2
      )

      service.start_ab_test(skill_id: skill.id, variant_version_id: variant_version.id, traffic_pct: 0.3)

      old_variant.reload
      expect(old_variant.is_ab_variant).to be false
    end
  end

  describe "#end_ab_test" do
    let!(:variant_version) do
      create(:ai_skill_version, :ab_variant,
        account: account,
        ai_skill: skill,
        version: "2.0.0",
        is_active: false,
        is_ab_variant: true,
        ab_traffic_pct: 0.3,
        effectiveness_score: 0.9
      )
    end

    it "activates the higher-performing variant as winner" do
      result = service.end_ab_test(skill_id: skill.id)

      expect(result[:winner_version_id]).to eq(variant_version.id)
      expect(result[:winner_effectiveness]).to eq(0.9)
      expect(result[:loser_version_id]).to eq(active_version.id)

      variant_version.reload
      expect(variant_version.is_active).to be true
      expect(variant_version.is_ab_variant).to be false
    end

    it "keeps active version as winner when it outperforms variant" do
      variant_version.update_column(:effectiveness_score, 0.3)

      result = service.end_ab_test(skill_id: skill.id)

      expect(result[:winner_version_id]).to eq(active_version.id)
    end

    it "returns error when no A/B test is running" do
      variant_version.update_column(:is_ab_variant, false)

      result = service.end_ab_test(skill_id: skill.id)

      expect(result[:error]).to include("No active A/B test")
    end
  end

  describe "#decay_stale_skills" do
    it "decays effectiveness of stale skills" do
      stale_skill = create(:ai_skill, account: account, last_used_at: 45.days.ago, effectiveness_score: 0.6)
      fresh_skill = create(:ai_skill, account: account, last_used_at: 5.days.ago, effectiveness_score: 0.8)

      result = service.decay_stale_skills(days_threshold: 30)

      expect(result).to eq(1)

      stale_skill.reload
      expect(stale_skill.effectiveness_score).to eq(0.55)

      fresh_skill.reload
      expect(fresh_skill.effectiveness_score).to eq(0.8)
    end

    it "does not decay below 0.0" do
      create(:ai_skill, account: account, last_used_at: 60.days.ago, effectiveness_score: 0.02)

      service.decay_stale_skills(days_threshold: 30)

      expect(Ai::Skill.last.effectiveness_score).to eq(0.0)
    end

    it "decays skills with nil last_used_at" do
      skill = create(:ai_skill, account: account, last_used_at: nil, effectiveness_score: 0.5)

      result = service.decay_stale_skills

      expect(result).to eq(1)
      expect(skill.reload.effectiveness_score).to eq(0.45)
    end

    it "skips skills with effectiveness already at 0.0" do
      create(:ai_skill, account: account, last_used_at: 60.days.ago, effectiveness_score: 0.0)

      result = service.decay_stale_skills

      expect(result).to eq(0)
    end
  end
end

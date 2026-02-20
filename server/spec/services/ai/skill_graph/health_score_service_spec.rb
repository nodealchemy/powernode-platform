# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::SkillGraph::HealthScoreService, type: :service do
  let(:account) { create(:account) }
  subject(:service) { described_class.new(account) }

  before do
    allow_any_instance_of(Ai::Skill).to receive(:sync_to_knowledge_graph)
    allow_any_instance_of(Ai::Agent).to receive(:sync_to_knowledge_graph)
    allow_any_instance_of(Ai::Memory::EmbeddingService).to receive(:generate).and_return(Array.new(1536, 0.1))
  end

  describe "#calculate" do
    context "with no active skills (empty graph)" do
      it "returns grade F with zero score" do
        result = service.calculate

        expect(result[:score]).to eq(0.0)
        expect(result[:grade]).to eq("F")
        expect(result[:components]).to eq({
          coverage: 0.0,
          connectivity: 0.0,
          freshness: 0.0,
          effectiveness: 0.0,
          conflict_penalty: 0.0
        })
      end
    end

    context "with a healthy graph" do
      before do
        # Create multiple well-connected, fresh, effective skills
        5.times do |i|
          skill = create(:ai_skill, account: account,
            name: "Healthy Skill #{i}",
            effectiveness_score: 0.9,
            last_used_at: 3.days.ago
          )

          # Create KG node for each skill
          node = Ai::KnowledgeGraphNode.create!(
            account: account, name: skill.name, entity_type: "skill",
            node_type: "entity", status: "active", confidence: 1.0,
            ai_skill_id: skill.id
          )

          # Store nodes for edge creation
          @nodes ||= []
          @nodes << node
        end

        # Create edges between skills (sufficient connectivity)
        @nodes.each_cons(2) do |source, target|
          Ai::KnowledgeGraphEdge.create!(
            account: account, source_node: source, target_node: target,
            relation_type: "requires", status: "active",
            weight: 0.8, confidence: 0.9
          )
          # Add reverse edge for more connectivity
          Ai::KnowledgeGraphEdge.create!(
            account: account, source_node: target, target_node: source,
            relation_type: "enhances", status: "active",
            weight: 0.7, confidence: 0.8
          )
        end
      end

      it "returns a high health score" do
        result = service.calculate

        expect(result[:score]).to be >= 60
        expect(result[:grade]).to be_in(%w[A B C])
        expect(result[:components][:coverage]).to eq(1.0)
        expect(result[:components][:freshness]).to eq(1.0)
        expect(result[:components][:effectiveness]).to be >= 0.8
      end
    end

    context "with a degraded graph" do
      before do
        # Create skills with poor metrics
        3.times do |i|
          create(:ai_skill, account: account,
            name: "Degraded Skill #{i}",
            effectiveness_score: 0.2,
            last_used_at: 60.days.ago
          )
        end

        # No KG nodes, no edges
        # Add some active conflicts
        skill = Ai::Skill.for_account(account.id).active.first
        create(:ai_skill_conflict,
          account: account,
          skill_a: skill,
          conflict_type: "stale",
          severity: "low",
          status: "detected"
        )
      end

      it "returns a low health score with grade D or F" do
        result = service.calculate

        expect(result[:score]).to be < 50
        expect(result[:grade]).to be_in(%w[D F])
        expect(result[:components][:coverage]).to eq(0.0)
        expect(result[:components][:connectivity]).to eq(0.0)
        expect(result[:components][:freshness]).to eq(0.0)
        expect(result[:components][:effectiveness]).to be <= 0.3
        expect(result[:components][:conflict_penalty]).to be > 0
      end
    end

    it "caps conflict penalty at 1.0" do
      skill_a = create(:ai_skill, account: account, effectiveness_score: 0.5)
      skill_b = create(:ai_skill, account: account, effectiveness_score: 0.5)
      skill_c = create(:ai_skill, account: account, effectiveness_score: 0.5)

      # Create multiple distinct conflicts
      Ai::SkillConflict.create!(account: account, skill_a: skill_a, skill_b: skill_b, conflict_type: "overlapping", severity: "medium", status: "detected", detected_at: Time.current)
      Ai::SkillConflict.create!(account: account, skill_a: skill_a, skill_b: skill_c, conflict_type: "overlapping", severity: "medium", status: "detected", detected_at: Time.current)
      Ai::SkillConflict.create!(account: account, skill_a: skill_b, skill_b: skill_c, conflict_type: "stale", severity: "low", status: "detected", detected_at: Time.current)

      result = service.calculate

      expect(result[:components][:conflict_penalty]).to be <= 1.0
    end

    it "returns score between 0 and 100" do
      create(:ai_skill, account: account, effectiveness_score: 0.5)

      result = service.calculate

      expect(result[:score]).to be_between(0.0, 100.0)
    end

    describe "grade thresholds" do
      it "assigns grade A for scores 90-100" do
        # Stub components to produce high score
        allow(service).to receive(:calculate).and_call_original

        # Direct grade test via score_to_grade
        grade = service.send(:score_to_grade, 95.0)
        expect(grade).to eq("A")
      end

      it "assigns grade B for scores 80-89" do
        grade = service.send(:score_to_grade, 85.0)
        expect(grade).to eq("B")
      end

      it "assigns grade C for scores 70-79" do
        grade = service.send(:score_to_grade, 75.0)
        expect(grade).to eq("C")
      end

      it "assigns grade D for scores 60-69" do
        grade = service.send(:score_to_grade, 65.0)
        expect(grade).to eq("D")
      end

      it "assigns grade F for scores below 60" do
        grade = service.send(:score_to_grade, 45.0)
        expect(grade).to eq("F")
      end
    end
  end

  describe "#comprehensive_report" do
    let(:mock_graph_service) { instance_double(Ai::KnowledgeGraph::GraphService) }

    before do
      allow(Ai::KnowledgeGraph::GraphService).to receive(:new).and_return(mock_graph_service)
      allow(mock_graph_service).to receive(:statistics).and_return({
        total_nodes: 10,
        total_edges: 8,
        skill_nodes: 5
      })
    end

    context "with existing skills" do
      before do
        create(:ai_skill, account: account, name: "Top Skill", effectiveness_score: 0.95, last_used_at: 2.days.ago)
        create(:ai_skill, account: account, name: "Bottom Skill", effectiveness_score: 0.1, last_used_at: 60.days.ago)
      end

      it "returns a comprehensive report structure" do
        result = service.comprehensive_report

        expect(result).to have_key(:health)
        expect(result).to have_key(:kg_stats)
        expect(result).to have_key(:conflict_summary)
        expect(result).to have_key(:top_skills)
        expect(result).to have_key(:bottom_skills)
        expect(result).to have_key(:stale_skills)
        expect(result).to have_key(:orphan_skills)
      end

      it "includes KG statistics" do
        result = service.comprehensive_report

        expect(result[:kg_stats][:total_nodes]).to eq(10)
      end

      it "identifies top performing skills" do
        result = service.comprehensive_report

        expect(result[:top_skills].first[:name]).to eq("Top Skill")
      end

      it "identifies bottom performing skills" do
        result = service.comprehensive_report

        expect(result[:bottom_skills].first[:name]).to eq("Bottom Skill")
      end

      it "identifies stale skills" do
        result = service.comprehensive_report

        stale_names = result[:stale_skills].map { |s| s[:name] }
        expect(stale_names).to include("Bottom Skill")
      end

      it "includes conflict summary" do
        skill = Ai::Skill.for_account(account.id).active.first
        create(:ai_skill_conflict,
          account: account,
          skill_a: skill,
          conflict_type: "stale",
          severity: "low",
          status: "detected"
        )

        result = service.comprehensive_report

        expect(result[:conflict_summary][:total_active]).to eq(1)
        expect(result[:conflict_summary][:by_type]).to have_key("stale")
      end
    end

    context "with no skills" do
      it "returns empty report with grade F health" do
        result = service.comprehensive_report

        expect(result[:health][:grade]).to eq("F")
        expect(result[:top_skills]).to be_empty
        expect(result[:bottom_skills]).to be_empty
      end
    end

    it "handles errors gracefully" do
      allow(mock_graph_service).to receive(:statistics).and_raise(StandardError, "stats error")

      result = service.comprehensive_report

      expect(result).to have_key(:error)
      expect(result[:health][:grade]).to eq("F")
    end
  end
end

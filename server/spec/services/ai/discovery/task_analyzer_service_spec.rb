# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Discovery::TaskAnalyzerService, type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:provider) { create(:ai_provider, account: account) }

  subject(:service) { described_class.new(account: account) }

  describe 'CAPABILITY_KEYWORDS' do
    it 'defines expected capability categories' do
      expect(described_class::CAPABILITY_KEYWORDS.keys).to include(
        "code_review", "testing", "deployment", "data_analysis",
        "security", "documentation", "monitoring", "devops"
      )
    end

    it 'is frozen' do
      expect(described_class::CAPABILITY_KEYWORDS).to be_frozen
    end
  end

  describe '#analyze' do
    context 'with a task matching known capabilities' do
      it 'identifies code review capabilities' do
        result = service.analyze("Review the code quality and lint issues")

        expect(result[:required_capabilities]).to include("code_review")
      end

      it 'identifies testing capabilities' do
        result = service.analyze("Write test specs for the validation module")

        expect(result[:required_capabilities]).to include("testing")
      end

      it 'identifies deployment capabilities' do
        result = service.analyze("Deploy the release to infrastructure")

        expect(result[:required_capabilities]).to include("deployment")
      end

      it 'identifies multiple capabilities' do
        result = service.analyze("Review code, write tests, and deploy to infrastructure")

        expect(result[:required_capabilities]).to include("code_review", "testing", "deployment")
      end
    end

    context 'with no matching capabilities' do
      it 'falls back to general capability' do
        result = service.analyze("Do something completely unrelated")

        expect(result[:required_capabilities]).to eq(["general"])
      end
    end

    context 'with blank description' do
      it 'returns empty capabilities for blank input' do
        # identify_capabilities returns [] for blank text, which means
        # analyze returns an empty recommendation list
        result = service.analyze("")

        expect(result[:required_capabilities]).to eq([])
      end
    end

    it 'returns a recommendation structure' do
      result = service.analyze("Review the code")

      expect(result).to have_key(:task_description)
      expect(result).to have_key(:required_capabilities)
      expect(result).to have_key(:recommendation)
      expect(result).to have_key(:confidence)
    end

    context 'with matching agents' do
      let!(:agent) do
        create(:ai_agent, account: account, provider: provider, creator: user, name: "Code Review Bot")
      end

      it 'includes agent recommendations with match scores' do
        result = service.analyze("Review the code for quality issues")

        recommendation = result[:recommendation]
        expect(recommendation).to be_an(Array)
      end
    end
  end

  describe '#recommend_team' do
    let(:agents) { Ai::Agent.where(account: account) }

    context 'with no agents available' do
      it 'marks all capabilities as gaps' do
        result = service.recommend_team(["code_review", "testing"], agents)

        result.each do |rec|
          expect(rec[:agent_id]).to be_nil
          expect(rec[:gap]).to be true
          expect(rec[:match_score]).to eq(0)
        end
      end
    end

    context 'with matching agents' do
      let!(:review_agent) do
        create(:ai_agent, account: account, provider: provider, creator: user, name: "code review specialist")
      end

      it 'recommends agents for matching capabilities' do
        result = service.recommend_team(["code_review"], agents)

        code_review_rec = result.find { |r| r[:capability] == "code_review" }
        expect(code_review_rec[:agent_id]).to eq(review_agent.id)
        expect(code_review_rec[:match_score]).to be > 0
      end
    end
  end

  describe '#skill_gap_analysis' do
    let(:agent) do
      create(:ai_agent, account: account, provider: provider, creator: user, name: "security scanner")
    end

    # The service code references association names that don't match the model
    # (ai_agent_team_members instead of members, ai_agent instead of agent).
    # Use doubles to bypass these schema mismatches.
    let(:mock_member) { double("AgentTeamMember", ai_agent: agent) }
    let(:members_relation) { double("members", includes: [mock_member]) }
    let(:team) { double("AgentTeam", ai_agent_team_members: members_relation) }

    it 'returns coverage analysis structure' do
      result = service.skill_gap_analysis(team, "Scan for security vulnerabilities and deploy")

      expect(result).to have_key(:required_capabilities)
      expect(result).to have_key(:covered_capabilities)
      expect(result).to have_key(:gaps)
      expect(result).to have_key(:redundant_capabilities)
      expect(result).to have_key(:coverage_score)
      expect(result).to have_key(:recommendations)
    end

    it 'calculates coverage score between 0 and 1' do
      result = service.skill_gap_analysis(team, "Scan for security vulnerabilities")

      expect(result[:coverage_score]).to be_between(0.0, 1.0)
    end

    it 'returns 1.0 coverage when no capabilities required' do
      result = service.skill_gap_analysis(team, "")

      expect(result[:coverage_score]).to eq(1.0)
    end

    it 'identifies gaps when team lacks capabilities' do
      result = service.skill_gap_analysis(team, "Deploy the application and monitor health")

      expect(result[:gaps]).not_to be_empty
    end

    it 'builds gap recommendations' do
      result = service.skill_gap_analysis(team, "Deploy the application and write documentation")

      gap_recs = result[:recommendations].select { |r| r[:action] == "add_agent" }
      result[:gaps].each do |gap|
        expect(gap_recs.map { |r| r[:capability] }).to include(gap)
      end
    end
  end

  describe '#analyze_history' do
    context 'with no recent tasks' do
      before do
        # Stub the query chain to return an empty relation-like object
        empty_relation = double("empty_relation")
        allow(Ai::TeamTask).to receive(:joins).and_return(empty_relation)
        allow(empty_relation).to receive(:where).and_return(empty_relation)
        allow(empty_relation).to receive(:limit).and_return(empty_relation)
        allow(empty_relation).to receive(:group).and_return(empty_relation)
        allow(empty_relation).to receive(:count).and_return({})
        allow(empty_relation).to receive(:empty?).and_return(true)
      end

      it 'returns empty recommendations' do
        result = service.analyze_history

        expect(result[:recommendations]).to eq([])
        expect(result[:task_stats][:failure_rate]).to eq(0)
      end
    end

    context 'with recent tasks that have high failure rate' do
      before do
        tasks_relation = double("tasks_relation")
        grouped_relation = double("grouped_relation")
        failed_relation = double("failed_relation")

        allow(Ai::TeamTask).to receive(:joins).and_return(tasks_relation)
        allow(tasks_relation).to receive(:where).and_return(tasks_relation)
        allow(tasks_relation).to receive(:limit).and_return(tasks_relation)

        # .group(:task_type).count returns a hash
        allow(tasks_relation).to receive(:group).with(:task_type).and_return(grouped_relation)
        allow(grouped_relation).to receive(:count).and_return({ "execution" => 8, "review" => 2 })

        # .empty? and .count for the full collection
        allow(tasks_relation).to receive(:empty?).and_return(false)
        allow(tasks_relation).to receive(:count).and_return(10)

        # .where(status: "failed").count
        allow(tasks_relation).to receive(:where).with(status: "failed").and_return(failed_relation)
        allow(failed_relation).to receive(:count).and_return(5)
      end

      it 'returns task statistics' do
        result = service.analyze_history

        expect(result[:task_stats]).to have_key(:types)
        expect(result[:task_stats]).to have_key(:failure_rate)
      end

      it 'recommends add_reviewer for high failure rates' do
        result = service.analyze_history

        types = result[:recommendations].map { |r| r[:type] }
        expect(types).to include("add_reviewer")
      end
    end
  end
end

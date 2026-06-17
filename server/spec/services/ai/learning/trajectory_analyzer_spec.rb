# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Learning::TrajectoryAnalyzer, type: :service do
  let(:account) { create(:account) }
  let(:service) { described_class.new(account: account) }

  before do
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:warn)
    allow(Rails.logger).to receive(:error)
  end

  describe '#initialize' do
    it 'stores the account' do
      expect(service.instance_variable_get(:@account)).to eq(account)
    end
  end

  describe 'MIN_SAMPLE_SIZE' do
    it 'is set to 10' do
      expect(described_class::MIN_SAMPLE_SIZE).to eq(10)
    end
  end

  describe '#analyze' do
    context 'when feature flag is disabled' do
      before do
        allow(Shared::FeatureFlagService).to receive(:enabled?).with(:trajectory_analysis).and_return(false)
      end

      it 'returns an empty array' do
        expect(service.analyze).to eq([])
      end

      it 'does not query any models' do
        expect(Ai::Agent).not_to receive(:where)
        expect(Ai::AgentTeam).not_to receive(:where)

        service.analyze
      end
    end

    context 'when feature flag is enabled' do
      before do
        allow(Shared::FeatureFlagService).to receive(:enabled?).with(:trajectory_analysis).and_return(true)
      end

      it 'aggregates recommendations from all analysis methods' do
        allow(service).to receive(:analyze_provider_performance).and_return([{ type: 'provider' }])
        allow(service).to receive(:analyze_team_compositions).and_return([{ type: 'team' }])
        allow(service).to receive(:analyze_cost_efficiency).and_return([{ type: 'cost' }])
        allow(service).to receive(:analyze_failure_modes).and_return([{ type: 'failure' }])
        allow(service).to receive(:analyze_skill_health).and_return([{ type: 'skill' }])
        allow(service).to receive(:analyze_learning_health).and_return([{ type: 'learning' }])

        results = service.analyze
        expect(results.length).to eq(6)
      end

      it 'returns empty array when no recommendations are generated' do
        allow(service).to receive(:analyze_provider_performance).and_return([])
        allow(service).to receive(:analyze_team_compositions).and_return([])
        allow(service).to receive(:analyze_cost_efficiency).and_return([])
        allow(service).to receive(:analyze_failure_modes).and_return([])
        allow(service).to receive(:analyze_skill_health).and_return([])
        allow(service).to receive(:analyze_learning_health).and_return([])

        expect(service.analyze).to eq([])
      end
    end
  end

  describe 'analyze_provider_performance (private)' do
    let(:agent) { create(:ai_agent, account: account) }
    let(:provider_a) { create(:ai_provider) }
    let(:provider_b) { create(:ai_provider, provider_type: provider_a.provider_type) }

    before do
      allow(Shared::FeatureFlagService).to receive(:enabled?).with(:trajectory_analysis).and_return(true)
    end

    context 'when there are not enough executions' do
      before do
        allow(Ai::Agent).to receive(:where).with(account: account).and_return(Ai::Agent.where(id: agent.id))
        mock_executions = double('executions')
        allow(Ai::AgentExecution).to receive(:where).with(agent: agent).and_return(mock_executions)
        allow(mock_executions).to receive(:where).and_return(mock_executions)
        allow(mock_executions).to receive(:count).and_return(5)
      end

      it 'returns no provider_switch recommendations' do
        results = service.send(:analyze_provider_performance)
        expect(results).to be_empty
      end
    end

    context 'when current provider is already the best' do
      it 'returns no recommendations' do
        allow(Ai::Agent).to receive(:where).with(account: account).and_return(Ai::Agent.none)

        results = service.send(:analyze_provider_performance)
        expect(results).to be_empty
      end
    end

    it 'generates provider_switch recommendations with correct structure' do
      recommendation = {
        recommendation_type: 'provider_switch',
        target_type: 'Ai::Agent',
        target_id: agent.id,
        current_config: { provider_id: provider_a.id, success_rate: 60.0 },
        recommended_config: { provider_id: provider_b.id, success_rate: 90.0 },
        evidence: hash_including(:agent_name, :current_provider, :recommended_provider, :sample_size, :improvement),
        confidence_score: an_instance_of(Float)
      }

      allow(service).to receive(:analyze_provider_performance).and_return([recommendation])

      results = service.send(:analyze_provider_performance)
      expect(results.first[:recommendation_type]).to eq('provider_switch')
      expect(results.first[:target_type]).to eq('Ai::Agent')
    end
  end

  describe 'analyze_team_compositions (private)' do
    before do
      allow(Shared::FeatureFlagService).to receive(:enabled?).with(:trajectory_analysis).and_return(true)
    end

    context 'when no teams exist' do
      it 'returns an empty array' do
        results = service.send(:analyze_team_compositions)
        expect(results).to be_empty
      end
    end

    context 'when team has insufficient trajectory data' do
      let!(:team) { create(:ai_agent_team, account: account) }

      before do
        trajectories = double('trajectories')
        allow(Ai::Trajectory).to receive(:where).with(account: account).and_return(trajectories)
        allow(trajectories).to receive(:where).and_return(trajectories)
        allow(trajectories).to receive(:count).and_return(5)
      end

      it 'returns no recommendations' do
        results = service.send(:analyze_team_compositions)
        expect(results).to be_empty
      end
    end

    it 'generates team_composition recommendations for low success rate teams' do
      team = create(:ai_agent_team, account: account)
      trajectories = double('trajectories')
      allow(Ai::AgentTeam).to receive(:where).with(account: account).and_return(Ai::AgentTeam.where(id: team.id))
      allow(Ai::Trajectory).to receive(:where).with(account: account).and_return(trajectories)
      allow(trajectories).to receive(:where).and_return(trajectories)
      allow(trajectories).to receive(:count).and_return(20)

      success_scope = double('success_scope')
      allow(trajectories).to receive(:where).with(status: 'completed').and_return(success_scope)
      allow(success_scope).to receive(:count).and_return(10)

      results = service.send(:analyze_team_compositions)

      expect(results).to be_an(Array)
      results.each do |rec|
        expect(rec[:recommendation_type]).to eq('team_composition')
        expect(rec[:target_type]).to eq('Ai::AgentTeam')
        expect(rec[:confidence_score]).to eq(0.5)
      end
    end

    it 'handles exceptions gracefully' do
      allow(Ai::AgentTeam).to receive(:where).and_raise(StandardError, 'Database error')

      expect(Rails.logger).to receive(:error).with(/Team analysis failed/)

      results = service.send(:analyze_team_compositions)
      expect(results).to eq([])
    end
  end

  describe 'analyze_cost_efficiency (private)' do
    before do
      allow(Shared::FeatureFlagService).to receive(:enabled?).with(:trajectory_analysis).and_return(true)
    end

    context 'when fewer than 2 providers have data' do
      before do
        mock_query = double('query')
        allow(Ai::AgentExecution).to receive(:where).with(account: account).and_return(mock_query)
        allow(mock_query).to receive(:where).and_return(mock_query)
        allow(mock_query).to receive(:group).and_return(mock_query)
        allow(mock_query).to receive(:select).and_return(mock_query)
        allow(mock_query).to receive(:count).and_return(1)
      end

      it 'returns no recommendations' do
        results = service.send(:analyze_cost_efficiency)
        expect(results).to be_empty
      end
    end

    it 'handles exceptions gracefully' do
      allow(Ai::AgentExecution).to receive(:where).and_raise(StandardError, 'Query failed')

      expect(Rails.logger).to receive(:error).with(/Cost analysis failed/)

      results = service.send(:analyze_cost_efficiency)
      expect(results).to eq([])
    end
  end

  describe 'analyze_failure_modes (private)' do
    before do
      allow(Shared::FeatureFlagService).to receive(:enabled?).with(:trajectory_analysis).and_return(true)
    end

    context 'when no workflows exist' do
      it 'returns an empty array' do
        results = service.send(:analyze_failure_modes)
        expect(results).to be_empty
      end
    end
  end

  # Tier-2(a): data-only analyzers that run server-side in the nightly pass
  describe 'analyze_skill_health (private)' do
    before do
      allow(Shared::FeatureFlagService).to receive(:enabled?).with(:trajectory_analysis).and_return(true)
    end

    it 'flags an enabled account skill with low success over a meaningful sample' do
      skill = create(:ai_skill, account: account, is_enabled: true,
                     positive_usage_count: 3, negative_usage_count: 12)

      results = service.send(:analyze_skill_health)

      expect(results.size).to eq(1)
      rec = results.first
      expect(rec[:recommendation_type]).to eq('skill_health')
      expect(rec[:target_type]).to eq('Ai::Skill')
      expect(rec[:target_id]).to eq(skill.id)
      expect(rec[:evidence][:success_rate]).to eq(20.0)
    end

    it 'ignores skills with a healthy success rate' do
      create(:ai_skill, account: account, is_enabled: true,
             positive_usage_count: 14, negative_usage_count: 1)
      expect(service.send(:analyze_skill_health)).to be_empty
    end

    it 'ignores skills below the minimum sample size' do
      create(:ai_skill, account: account, is_enabled: true,
             positive_usage_count: 1, negative_usage_count: 2)
      expect(service.send(:analyze_skill_health)).to be_empty
    end

    it 'ignores shared system skills (nil account)' do
      create(:ai_skill, account: nil, is_enabled: true,
             positive_usage_count: 1, negative_usage_count: 20)
      expect(service.send(:analyze_skill_health)).to be_empty
    end

    it 'handles exceptions gracefully' do
      allow(Ai::Skill).to receive(:where).and_raise(StandardError, 'boom')
      expect(Rails.logger).to receive(:error).with(/Skill health analysis failed/)
      expect(service.send(:analyze_skill_health)).to eq([])
    end
  end

  describe 'analyze_learning_health (private)' do
    before do
      allow(Shared::FeatureFlagService).to receive(:enabled?).with(:trajectory_analysis).and_return(true)
    end

    it 'flags an account whose learning corpus has too many problem entries' do
      create_list(:ai_compound_learning, 7, account: account, status: 'active', importance_score: 0.8)
      create_list(:ai_compound_learning, 3, account: account, status: 'disproven')

      results = service.send(:analyze_learning_health)

      expect(results.size).to eq(1)
      rec = results.first
      expect(rec[:recommendation_type]).to eq('learning_health')
      expect(rec[:target_type]).to eq('Account')
      expect(rec[:target_id]).to eq(account.id)
      expect(rec[:current_config][:disproven]).to eq(3)
    end

    it 'stays quiet for a healthy corpus' do
      create_list(:ai_compound_learning, 12, account: account, status: 'active', importance_score: 0.8)
      expect(service.send(:analyze_learning_health)).to be_empty
    end

    it 'ignores accounts below the minimum corpus size' do
      create_list(:ai_compound_learning, 3, account: account, status: 'disproven')
      expect(service.send(:analyze_learning_health)).to be_empty
    end

    it 'handles exceptions gracefully' do
      allow(Ai::CompoundLearning).to receive(:for_account).and_raise(StandardError, 'boom')
      expect(Rails.logger).to receive(:error).with(/Learning health analysis failed/)
      expect(service.send(:analyze_learning_health)).to eq([])
    end
  end

  describe 'calculate_confidence (private)' do
    it 'returns higher confidence for larger sample sizes' do
      small_sample = service.send(:calculate_confidence, 10, 80.0, 10, 60.0)
      large_sample = service.send(:calculate_confidence, 50, 80.0, 10, 60.0)

      expect(large_sample).to be > small_sample
    end

    it 'returns higher confidence for larger improvement deltas' do
      small_delta = service.send(:calculate_confidence, 30, 70.0, 30, 65.0)
      large_delta = service.send(:calculate_confidence, 30, 90.0, 30, 60.0)

      expect(large_delta).to be > small_delta
    end

    it 'caps confidence at 0.95' do
      result = service.send(:calculate_confidence, 1000, 99.0, 1000, 10.0)
      expect(result).to be <= 0.95
    end

    it 'caps sample size factor at 1.0 (for samples >= 50)' do
      result_50 = service.send(:calculate_confidence, 50, 80.0, 50, 60.0)
      result_100 = service.send(:calculate_confidence, 100, 80.0, 50, 60.0)

      expect(result_50).to eq(result_100)
    end

    it 'rounds to 4 decimal places' do
      result = service.send(:calculate_confidence, 25, 75.0, 25, 60.0)
      decimal_places = result.to_s.split('.').last.length
      expect(decimal_places).to be <= 4
    end

    it 'returns a value between 0 and 0.95' do
      result = service.send(:calculate_confidence, 1, 51.0, 1, 50.0)
      expect(result).to be >= 0
      expect(result).to be <= 0.95
    end
  end

  describe 'recommendation structure' do
    before do
      allow(Shared::FeatureFlagService).to receive(:enabled?).with(:trajectory_analysis).and_return(true)
    end

    it 'returns recommendations with expected keys' do
      mock_recommendation = {
        recommendation_type: 'provider_switch',
        target_type: 'Ai::Agent',
        target_id: SecureRandom.uuid,
        current_config: {},
        recommended_config: {},
        evidence: {},
        confidence_score: 0.75
      }

      allow(service).to receive(:analyze_provider_performance).and_return([mock_recommendation])
      allow(service).to receive(:analyze_team_compositions).and_return([])
      allow(service).to receive(:analyze_cost_efficiency).and_return([])
      allow(service).to receive(:analyze_failure_modes).and_return([])

      results = service.analyze
      expect(results.first).to include(
        :recommendation_type,
        :target_type,
        :target_id,
        :current_config,
        :recommended_config,
        :evidence,
        :confidence_score
      )
    end
  end
end

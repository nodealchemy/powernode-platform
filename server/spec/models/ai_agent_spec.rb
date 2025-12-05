# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiAgent, type: :model do
  describe 'associations' do
    it { should belong_to(:account) }
    it { should belong_to(:ai_provider) }
    it { should have_many(:ai_agent_executions).dependent(:destroy) }
    it { should have_many(:ai_conversations).dependent(:destroy) }
    it { should have_many(:ai_messages).dependent(:destroy) }
  end

  describe 'validations' do
    subject { build(:ai_agent) }

    it { should validate_presence_of(:name) }
    it { should validate_presence_of(:agent_type) }
    it 'validates configuration is present' do
      agent = build(:ai_agent, configuration: nil)
      # Skip the set_default_configuration callback for this test
      allow(agent).to receive(:set_default_configuration)
      agent.valid?
      expect(agent.errors[:configuration]).to include("can't be blank")
    end
    it { should validate_length_of(:name).is_at_most(255) }
    it { should validate_length_of(:description).is_at_most(1000) }
    it { should validate_inclusion_of(:agent_type).in_array(%w[assistant code_assistant data_analyst content_generator image_generator workflow_optimizer]) }
    it { should validate_inclusion_of(:status).in_array(%w[active inactive error]) }

    context 'name uniqueness' do
      let!(:existing_agent) { create(:ai_agent) }

      it 'validates uniqueness of name within account scope' do
        duplicate_agent = build(:ai_agent, 
                                name: existing_agent.name, 
                                account: existing_agent.account)
        
        expect(duplicate_agent).not_to be_valid
        expect(duplicate_agent.errors[:name]).to include('has already been taken')
      end

      it 'allows same name in different accounts' do
        different_account = create(:account)
        agent_with_same_name = build(:ai_agent, 
                                    name: existing_agent.name, 
                                    account: different_account)
        
        expect(agent_with_same_name).to be_valid
      end
    end

    context 'configuration validation' do
      it 'validates configuration is a hash' do
        agent = build(:ai_agent, configuration: 'invalid')
        expect(agent).not_to be_valid
        expect(agent.errors[:configuration]).to include('must be a hash')
      end

      it 'validates required configuration keys for assistant type' do
        agent = build(:ai_agent, agent_type: 'assistant', configuration: {})
        # Skip the set_default_configuration callback for this test
        allow(agent).to receive(:set_default_configuration)
        expect(agent).not_to be_valid
        expect(agent.errors[:configuration]).to include('must include model')
      end

      it 'validates model is present in configuration' do
        agent = build(:ai_agent, configuration: { temperature: 0.7 })
        expect(agent).not_to be_valid
        expect(agent.errors[:configuration]).to include('must include model')
      end

      it 'validates temperature range' do
        agent = build(:ai_agent, configuration: { 
          model: 'gpt-3.5-turbo', 
          temperature: 2.0 
        })
        expect(agent).not_to be_valid
        expect(agent.errors[:configuration]).to include('temperature must be between 0 and 1')
      end
    end
  end

  describe 'scopes' do
    let!(:active_agent) { create(:ai_agent, status: 'active') }
    let!(:inactive_agent) { create(:ai_agent, status: 'inactive') }
    let!(:archived_agent) { create(:ai_agent, status: 'archived') }
    let!(:error_agent) { create(:ai_agent, status: 'error') }

    describe '.active' do
      it 'returns only active agents' do
        expect(AiAgent.active).to include(active_agent)
        expect(AiAgent.active).not_to include(inactive_agent)
      end
    end

    describe '.by_type' do
      let!(:assistant) { create(:ai_agent, agent_type: 'assistant') }
      let!(:code_assistant) { create(:ai_agent, :code_assistant) }

      it 'returns agents of specified type' do
        expect(AiAgent.by_type('assistant')).to include(assistant)
        expect(AiAgent.by_type('assistant')).not_to include(code_assistant)
      end
    end

    describe '.healthy' do
      it 'returns agents with active status' do
        expect(AiAgent.healthy).to include(active_agent)
        expect(AiAgent.healthy).not_to include(error_agent)
      end
    end
  end

  describe 'callbacks' do
    describe 'before_validation' do
      it 'normalizes agent_type' do
        agent = build(:ai_agent, agent_type: '  ASSISTANT  ')
        agent.valid?
        expect(agent.agent_type).to eq('assistant')
      end

      it 'sets default configuration for assistant type' do
        agent = build(:ai_agent, agent_type: 'assistant', configuration: nil)
        agent.valid?
        expect(agent.configuration).to include('model', 'temperature', 'max_tokens')
      end
    end

    describe 'after_create' do
      it 'creates audit log entry' do
        expect {
          create(:ai_agent)
        }.to change { AuditLog.count }.by(1)

        audit_log = AuditLog.last
        expect(audit_log.action).to eq('create')
        expect(audit_log.resource_type).to eq('AiAgent')
      end
    end
  end

  describe 'instance methods' do
    let(:agent) { create(:ai_agent, :with_executions) }

    describe '#can_execute?' do
      it 'returns true for active agents with active provider' do
        expect(agent.can_execute?).to be true
      end

      it 'returns false for inactive agents' do
        agent.update!(status: 'inactive')
        expect(agent.can_execute?).to be false
      end

      it 'returns false when provider is inactive' do
        agent.ai_provider.update!(is_active: false)
        expect(agent.can_execute?).to be false
      end

      it 'returns false when agent status is error' do
        agent.update!(status: 'error')
        expect(agent.can_execute?).to be false
      end
    end

    describe '#execution_stats' do
      it 'returns execution statistics' do
        stats = agent.execution_stats
        
        expect(stats).to include(:total_executions)
        expect(stats).to include(:successful_executions)
        expect(stats).to include(:failed_executions)
        expect(stats).to include(:success_rate)
        expect(stats).to include(:avg_execution_time)
        expect(stats[:total_executions]).to eq(3)
      end

      it 'calculates success rate correctly' do
        create(:ai_agent_execution, :completed, ai_agent: agent, account: agent.account)
        create(:ai_agent_execution, :failed, ai_agent: agent, account: agent.account)
        
        stats = agent.execution_stats
        expect(stats[:success_rate]).to be_a(Float)
        expect(stats[:success_rate]).to be >= 0
        expect(stats[:success_rate]).to be <= 100
      end
    end

    describe '#recent_executions' do
      it 'returns executions from last 24 hours by default' do
        old_execution = create(:ai_agent_execution, 
                             ai_agent: agent, 
                             account: agent.account,
                             created_at: 2.days.ago)
        
        recent_executions = agent.recent_executions
        expect(recent_executions).not_to include(old_execution)
      end

      it 'accepts custom time period' do
        old_execution = create(:ai_agent_execution, 
                             ai_agent: agent, 
                             account: agent.account,
                             created_at: 2.days.ago)
        
        recent_executions = agent.recent_executions(3.days)
        expect(recent_executions).to include(old_execution)
      end
    end

    describe '#update_configuration' do
      it 'updates configuration and validates' do
        new_config = { model: 'gpt-4', temperature: 0.3 }
        result = agent.update_configuration(new_config)
        
        expect(result).to be true
        expect(agent.configuration['model']).to eq('gpt-4')
        expect(agent.configuration['temperature']).to eq(0.3)
      end

      it 'returns false for invalid configuration' do
        invalid_config = { temperature: 2.0 }
        result = agent.update_configuration(invalid_config)
        
        expect(result).to be false
        expect(agent.errors).not_to be_empty
      end
    end

    describe '#average_response_time' do
      it 'calculates average response time from completed executions' do
        create(:ai_agent_execution, :completed, ai_agent: agent, account: agent.account)
        
        avg_time = agent.average_response_time
        expect(avg_time).to be_a(Numeric)
        expect(avg_time).to be >= 0
      end

      it 'returns 0 when no completed executions exist' do
        agent.ai_agent_executions.destroy_all
        expect(agent.average_response_time).to eq(0)
      end
    end

    describe '#total_tokens_used' do
      it 'sums tokens from all completed executions' do
        create(:ai_agent_execution, :completed, 
               ai_agent: agent, 
               account: agent.account,
               output_data: { metrics: { tokens_used: 100 } })
        
        create(:ai_agent_execution, :completed, 
               ai_agent: agent, 
               account: agent.account,
               output_data: { metrics: { tokens_used: 200 } })

        expect(agent.total_tokens_used).to eq(300)
      end

      it 'returns 0 when no token data available' do
        agent.ai_agent_executions.destroy_all
        expect(agent.total_tokens_used).to eq(0)
      end
    end

    describe '#estimated_total_cost' do
      it 'sums cost estimates from all completed executions' do
        create(:ai_agent_execution, :completed, 
               ai_agent: agent, 
               account: agent.account,
               output_data: { metrics: { cost_estimate: 0.005 } })
        
        create(:ai_agent_execution, :completed, 
               ai_agent: agent, 
               account: agent.account,
               output_data: { metrics: { cost_estimate: 0.012 } })

        expect(agent.estimated_total_cost).to eq(0.017)
      end
    end

    describe '#deactivate!' do
      it 'sets agent as inactive and updates status' do
        agent.deactivate!('Testing deactivation')
        
        expect(agent.reload.status).to eq('inactive')
        expect(agent.metadata['deactivated_reason']).to eq('Testing deactivation')
      end

      it 'creates audit log entry' do
        agent.deactivate!('Testing')
        
        deactivation_log = AuditLog.where(
          resource_type: 'AiAgent',
          resource_id: agent.id.to_s,
          action: 'update'
        ).where("metadata ? 'deactivation_reason'").last
        
        expect(deactivation_log).to be_present
        expect(deactivation_log.metadata['deactivation_reason']).to eq('Testing')
      end
    end

    describe '#activate!' do
      it 'sets agent as active and updates status' do
        agent.update!(status: 'inactive')
        agent.activate!
        
        expect(agent.reload.status).to eq('active')
      end
    end
  end

  describe 'class methods' do
    describe '.create_from_template' do
      let(:account) { create(:account) }
      let(:provider) { create(:ai_provider) }
      let(:template_data) do
        {
          name: 'Code Assistant',
          agent_type: 'code_assistant',
          description: 'Helps with coding tasks',
          configuration: {
            model: 'claude-3-sonnet',
            temperature: 0.2,
            system_prompt: 'You are a coding expert.'
          }
        }
      end

      it 'creates agent from template data' do
        agent = AiAgent.create_from_template(account, provider, template_data)
        
        expect(agent).to be_persisted
        expect(agent.name).to eq('Code Assistant')
        expect(agent.agent_type).to eq('code_assistant')
        expect(agent.ai_provider).to eq(provider)
        expect(agent.account).to eq(account)
      end

      it 'returns errors for invalid template data' do
        invalid_template = template_data.merge(agent_type: 'invalid_type')
        agent = AiAgent.create_from_template(account, provider, invalid_template)
        
        expect(agent).not_to be_persisted
        expect(agent.errors).not_to be_empty
      end
    end

    describe '.search' do
      let!(:code_agent) { create(:ai_agent, :code_assistant, name: 'Python Helper') }
      let!(:data_agent) { create(:ai_agent, :data_analyst, name: 'Data Analyzer') }

      it 'searches by name' do
        results = AiAgent.search('Python')
        expect(results).to include(code_agent)
        expect(results).not_to include(data_agent)
      end

      it 'searches by description' do
        data_agent.update!(description: 'Analyzes customer data trends')
        results = AiAgent.search('customer')
        expect(results).to include(data_agent)
      end

      it 'returns all agents for empty query' do
        results = AiAgent.search('')
        expect(results).to include(code_agent, data_agent)
      end
    end

    describe '.popular' do
      it 'returns agents ordered by execution count' do
        agent1 = create(:ai_agent)
        agent2 = create(:ai_agent)
        
        # Create more executions for agent2
        create_list(:ai_agent_execution, 3, ai_agent: agent1, account: agent1.account)
        create_list(:ai_agent_execution, 5, ai_agent: agent2, account: agent2.account)
        
        popular_agents = AiAgent.popular(limit: 2)
        expect(popular_agents.first).to eq(agent2)
        expect(popular_agents.second).to eq(agent1)
      end
    end
  end

  describe 'edge cases and error handling' do
    it 'handles missing configuration gracefully' do
      agent = build(:ai_agent, configuration: nil)
      agent.valid?
      expect(agent.configuration).to be_a(Hash)
    end

    it 'handles malformed JSON in metadata' do
      agent = create(:ai_agent)
      # Directly update database to simulate corrupted data
      AiAgent.where(id: agent.id).update_all(metadata: 'invalid json')
      
      expect { agent.reload.metadata }.not_to raise_error
    end

    it 'validates configuration changes atomically' do
      agent = create(:ai_agent)
      
      expect {
        agent.update!(configuration: { temperature: 2.0 })
      }.to raise_error(ActiveRecord::RecordInvalid)
      
      # Original configuration should be preserved
      expect(agent.reload.configuration['temperature']).not_to eq(2.0)
    end
  end
end
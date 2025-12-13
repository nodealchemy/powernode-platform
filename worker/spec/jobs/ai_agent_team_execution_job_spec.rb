# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiAgentTeamExecutionJob, type: :job do
  subject { described_class }

  it_behaves_like 'a base job', described_class

  before { mock_powernode_worker_config }

  let(:team_id) { SecureRandom.uuid }
  let(:user_id) { SecureRandom.uuid }
  let(:input) { { 'task' => 'Generate content' } }
  let(:context) { { 'priority' => 'high' } }

  let(:team_data) do
    {
      'id' => team_id,
      'name' => 'Content Generation Team',
      'team_type' => 'sequential',
      'status' => 'active'
    }
  end

  let(:user_data) do
    {
      'id' => user_id,
      'email' => 'user@example.com',
      'name' => 'Test User'
    }
  end

  let(:execution_result) do
    {
      'success' => true,
      'output' => 'Generated content',
      'execution_type' => 'sequential',
      'members_executed' => 3
    }
  end

  describe '#execute' do
    let(:job) { described_class.new }

    context 'successful execution' do
      before do
        stub_backend_api_success(:get, "/api/v1/ai/agent_teams/#{team_id}", {
          success: true,
          data: team_data
        })
        stub_backend_api_success(:get, "/api/v1/internal/users/#{user_id}", {
          success: true,
          data: user_data
        })
        stub_backend_api_success(:post, "/api/v1/ai/agent_teams/#{team_id}/execute", {
          success: true,
          data: execution_result
        })
        stub_backend_api_success(:post, "/api/v1/ai/agent_teams/#{team_id}/execution_complete", {
          success: true
        })
      end

      it 'fetches team data' do
        job.execute('team_id' => team_id, 'user_id' => user_id, 'input' => input, 'context' => context)

        expect_api_request(:get, "/api/v1/ai/agent_teams/#{team_id}")
      end

      it 'fetches user data' do
        job.execute('team_id' => team_id, 'user_id' => user_id, 'input' => input, 'context' => context)

        expect_api_request(:get, "/api/v1/internal/users/#{user_id}")
      end

      it 'executes team orchestration' do
        job.execute('team_id' => team_id, 'user_id' => user_id, 'input' => input, 'context' => context)

        expect_api_request(:post, "/api/v1/ai/agent_teams/#{team_id}/execute")
      end

      it 'reports execution completion' do
        job.execute('team_id' => team_id, 'user_id' => user_id, 'input' => input, 'context' => context)

        expect_api_request(:post, "/api/v1/ai/agent_teams/#{team_id}/execution_complete")
      end

      it 'returns execution result' do
        result = job.execute('team_id' => team_id, 'user_id' => user_id, 'input' => input, 'context' => context)

        expect(result).to eq(execution_result)
      end
    end

    context 'team not found' do
      before do
        stub_backend_api_success(:get, "/api/v1/ai/agent_teams/#{team_id}", {
          success: false,
          error: 'Team not found'
        })
        stub_backend_api_success(:post, "/api/v1/ai/agent_teams/#{team_id}/execution_failed", {
          success: true
        })
      end

      it 'raises an error' do
        expect {
          job.execute('team_id' => team_id, 'user_id' => user_id, 'input' => input)
        }.to raise_error(RuntimeError, /Team not found/)
      end
    end

    context 'user not found' do
      before do
        stub_backend_api_success(:get, "/api/v1/ai/agent_teams/#{team_id}", {
          success: true,
          data: team_data
        })
        stub_backend_api_success(:get, "/api/v1/internal/users/#{user_id}", {
          success: false,
          error: 'User not found'
        })
        stub_backend_api_success(:post, "/api/v1/ai/agent_teams/#{team_id}/execution_failed", {
          success: true
        })
      end

      it 'raises an error' do
        expect {
          job.execute('team_id' => team_id, 'user_id' => user_id, 'input' => input)
        }.to raise_error(RuntimeError, /User not found/)
      end
    end

    context 'execution failure' do
      before do
        stub_backend_api_success(:get, "/api/v1/ai/agent_teams/#{team_id}", {
          success: true,
          data: team_data
        })
        stub_backend_api_success(:get, "/api/v1/internal/users/#{user_id}", {
          success: true,
          data: user_data
        })
        stub_backend_api_success(:post, "/api/v1/ai/agent_teams/#{team_id}/execute", {
          success: false,
          error: 'Agent execution failed'
        })
        stub_backend_api_success(:post, "/api/v1/ai/agent_teams/#{team_id}/execution_failed", {
          success: true
        })
      end

      it 'reports execution failure and raises error' do
        expect {
          job.execute('team_id' => team_id, 'user_id' => user_id, 'input' => input)
        }.to raise_error(RuntimeError, /Team execution failed/)

        expect_api_request(:post, "/api/v1/ai/agent_teams/#{team_id}/execution_failed")
      end
    end
  end

  describe 'sidekiq options' do
    it 'has retry count of 3' do
      expect(described_class.sidekiq_options['retry']).to eq(3)
    end
  end

  describe 'job inheritance' do
    it 'inherits from BaseJob' do
      expect(described_class.superclass).to eq(BaseJob)
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mcp::NodeExecutors::CiTrigger do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:git_provider) { create(:git_provider, provider_type: 'github') }
  let(:credential) { create(:git_provider_credential, git_provider: git_provider, account: account) }
  let(:repository) { create(:git_repository, git_provider_credential: credential, account: account, owner: 'myorg', name: 'myrepo') }

  let(:workflow) { create(:ai_workflow, :active, account: account, creator: user) }
  let(:workflow_run) { create(:ai_workflow_run, workflow: workflow, account: account) }

  let(:node) do
    create(:ai_workflow_node, :ci_trigger, workflow: workflow, configuration: configuration)
  end

  let(:node_execution) do
    create(:ai_workflow_node_execution,
           workflow_run: workflow_run,
           node: node,
           status: 'running')
  end

  let(:node_context) do
    instance_double(
      Mcp::NodeExecutionContext,
      input_data: {},
      get_variable: nil,
      previous_results: [],
      scoped_variables: {},
      workflow_run: workflow_run
    )
  end

  let(:orchestrator) do
    instance_double(
      Mcp::AiWorkflowOrchestrator,
      set_variable: nil
    )
  end

  let(:configuration) do
    {
      'repository_id' => repository.id,
      'workflow_id' => 'ci.yml',
      'ref' => 'main',
      'trigger_action' => 'workflow_dispatch',
      'inputs' => { 'environment' => 'staging' }
    }
  end

  let(:executor) do
    described_class.new(
      node: node,
      node_execution: node_execution,
      node_context: node_context,
      orchestrator: orchestrator
    )
  end

  describe '#execute' do
    context 'with valid configuration' do
      let(:api_client) { instance_double(Git::GithubApiClient, respond_to?: false) }
      let(:api_response) { { success: true, run_id: 12345, url: 'https://github.com/myorg/myrepo/actions/runs/12345' } }

      before do
        allow(Git::ApiClient).to receive(:for).and_return(api_client)
        allow(api_client).to receive(:trigger_workflow).and_return(api_response)
      end

      it 'triggers the CI workflow successfully' do
        result = executor.execute

        expect(result[:success]).to be true
        expect(result[:output][:triggered]).to be true
        expect(result[:output][:workflow_id]).to eq('ci.yml')
        expect(result[:output][:ref]).to eq('main')
      end

      it 'calls the API client with correct parameters' do
        expect(api_client).to receive(:trigger_workflow).with(
          'myorg',
          'myrepo',
          'ci.yml',
          'main',
          { 'environment' => 'staging' }
        ).and_return(api_response)

        executor.execute
      end

      it 'includes run data in response' do
        result = executor.execute

        expect(result[:data][:repository_id]).to eq(repository.id)
        expect(result[:data][:repository_name]).to eq('myorg/myrepo')
        expect(result[:data][:run_id]).to eq(12345)
      end
    end

    context 'with repository_dispatch action' do
      let(:api_client) { double('api_client') }

      let(:configuration) do
        {
          'repository_id' => repository.id,
          'workflow_id' => 'ci.yml',
          'ref' => 'main',
          'trigger_action' => 'repository_dispatch',
          'inputs' => { 'event_type' => 'custom_event', 'data' => 'value' }
        }
      end

      before do
        allow(Git::ApiClient).to receive(:for).and_return(api_client)
        allow(api_client).to receive(:respond_to?).with(:create_repository_dispatch).and_return(true)
        allow(api_client).to receive(:create_repository_dispatch).and_return({ success: true })
      end

      it 'dispatches a repository event' do
        result = executor.execute
        expect(result[:success]).to be true
        expect(result[:output][:trigger_action]).to eq('repository_dispatch')
      end

      it 'calls create_repository_dispatch with correct parameters' do
        expect(api_client).to receive(:create_repository_dispatch).with(
          'myorg',
          'myrepo',
          'custom_event',
          { 'data' => 'value' }
        ).and_return({ success: true })

        executor.execute
      end
    end

    context 'with repository_dispatch on unsupported provider' do
      let(:api_client) { double('api_client') }

      let(:configuration) do
        {
          'repository_id' => repository.id,
          'workflow_id' => 'ci.yml',
          'ref' => 'main',
          'trigger_action' => 'repository_dispatch',
          'inputs' => { 'event_type' => 'test' }
        }
      end

      before do
        allow(Git::ApiClient).to receive(:for).and_return(api_client)
        allow(api_client).to receive(:respond_to?).with(:create_repository_dispatch).and_return(false)
      end

      it 'returns error for unsupported provider' do
        result = executor.execute
        expect(result[:success]).to be true # The outer call succeeds, but output has failure
        expect(result[:output][:triggered]).to be false
        expect(result[:output][:error]).to include('not supported')
      end
    end

    context 'when API call fails' do
      before do
        allow(Git::ApiClient).to receive(:for).and_raise(StandardError.new('API Error'))
      end

      it 'raises NodeExecutionError' do
        expect { executor.execute }.to raise_error(
          Mcp::AiWorkflowOrchestrator::NodeExecutionError,
          /ci_trigger execution failed.*API Error/
        )
      end
    end

    context 'with missing repository' do
      let(:configuration) do
        {
          'repository_id' => SecureRandom.uuid,
          'workflow_id' => 'ci.yml',
          'ref' => 'main',
          'trigger_action' => 'workflow_dispatch'
        }
      end

      it 'raises error for missing repository' do
        expect { executor.execute }.to raise_error(
          Mcp::AiWorkflowOrchestrator::NodeExecutionError,
          /Repository not found/
        )
      end
    end
  end

  describe 'configuration validation' do
    context 'when repository_id is missing' do
      let(:configuration) do
        {
          'workflow_id' => 'ci.yml',
          'ref' => 'main'
        }
      end

      it 'raises error for missing repository_id' do
        expect { executor.execute }.to raise_error(
          Mcp::AiWorkflowOrchestrator::NodeExecutionError,
          /repository_id is required/
        )
      end
    end

    context 'when workflow_id is missing' do
      let(:configuration) do
        {
          'repository_id' => repository.id,
          'ref' => 'main'
        }
      end

      it 'raises error for missing workflow_id' do
        expect { executor.execute }.to raise_error(
          Mcp::AiWorkflowOrchestrator::NodeExecutionError,
          /workflow_id is required/
        )
      end
    end
  end
end

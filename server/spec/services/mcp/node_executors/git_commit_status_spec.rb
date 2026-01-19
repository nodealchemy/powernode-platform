# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mcp::NodeExecutors::GitCommitStatus do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:git_provider) { create(:git_provider, provider_type: 'github') }
  let(:credential) { create(:git_provider_credential, provider: git_provider, account: account) }
  let(:repository) { create(:git_repository, credential: credential, account: account, owner: 'myorg', name: 'myrepo') }

  let(:workflow) { create(:ai_workflow, :active, account: account, creator: user) }
  let(:workflow_run) { create(:ai_workflow_run, workflow: workflow, account: account) }

  let(:node) do
    create(:ai_workflow_node, :git_commit_status, workflow: workflow, configuration: configuration)
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
    double(
      'orchestrator',
      set_variable: nil,
      workflow: workflow
    )
  end

  let(:configuration) do
    {
      'repository_id' => repository.id,
      'sha' => 'abc123def456',
      'state' => 'success',
      'context' => 'ai-workflow/build',
      'description' => 'Build passed'
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
      let(:api_client) { instance_double(Devops::Git::GithubApiClient) }
      let(:api_response) { { success: true, id: 1, url: 'https://github.com/myorg/myrepo/statuses/abc123' } }

      before do
        allow(Devops::Git::ApiClient).to receive(:for).and_return(api_client)
        allow(api_client).to receive(:create_commit_status).and_return(api_response)
      end

      it 'creates the commit status' do
        result = executor.execute

        expect(result[:success]).to be true
        expect(result[:output][:updated]).to be true
        expect(result[:output][:state]).to eq('success')
      end

      it 'calls the API with correct parameters' do
        expect(api_client).to receive(:create_commit_status).with(
          'myorg',
          'myrepo',
          'abc123def456',
          'success',
          hash_including(context: 'ai-workflow/build', description: 'Build passed')
        ).and_return(api_response)

        executor.execute
      end

      it 'includes data in response' do
        result = executor.execute

        expect(result[:data][:repository_id]).to eq(repository.id)
        expect(result[:data][:sha]).to eq('abc123def456')
        expect(result[:data][:state]).to eq('success')
      end
    end

    context 'with target_url' do
      let(:api_client) { instance_double(Devops::Git::GithubApiClient) }

      let(:configuration) do
        {
          'repository_id' => repository.id,
          'sha' => 'abc123def456',
          'state' => 'pending',
          'context' => 'ai-workflow/build',
          'description' => 'Build in progress',
          'target_url' => 'https://example.com/builds/123'
        }
      end

      before do
        allow(Devops::Git::ApiClient).to receive(:for).and_return(api_client)
        allow(api_client).to receive(:create_commit_status).and_return({ success: true, id: 1 })
      end

      it 'includes target_url in the request' do
        expect(api_client).to receive(:create_commit_status).with(
          'myorg',
          'myrepo',
          'abc123def456',
          'pending',
          hash_including(target_url: 'https://example.com/builds/123')
        ).and_return({ success: true, id: 1 })

        executor.execute
      end
    end

    context 'with different states' do
      let(:api_client) { instance_double(Devops::Git::GithubApiClient) }

      before do
        allow(Devops::Git::ApiClient).to receive(:for).and_return(api_client)
        allow(api_client).to receive(:create_commit_status).and_return({ success: true, id: 1 })
      end

      %w[pending success failure error].each do |state|
        it "supports #{state} state" do
          node.update!(configuration: configuration.merge('state' => state))

          expect(api_client).to receive(:create_commit_status).with(
            anything,
            anything,
            anything,
            state,
            anything
          ).and_return({ success: true, id: 1 })

          executor.execute
        end
      end
    end

    context 'when API call fails' do
      before do
        allow(Devops::Git::ApiClient).to receive(:for).and_raise(StandardError.new('API Error'))
      end

      it 'raises NodeExecutionError' do
        expect { executor.execute }.to raise_error(
          Mcp::AiWorkflowOrchestrator::NodeExecutionError,
          /git_commit_status execution failed.*API Error/
        )
      end
    end

    context 'with missing repository' do
      let(:configuration) do
        {
          'repository_id' => SecureRandom.uuid,
          'sha' => 'abc123',
          'state' => 'success'
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
          'sha' => 'abc123',
          'state' => 'success'
        }
      end

      it 'raises error for missing repository_id' do
        expect { executor.execute }.to raise_error(
          Mcp::AiWorkflowOrchestrator::NodeExecutionError,
          /repository_id is required/
        )
      end
    end

    context 'when sha is missing' do
      let(:configuration) do
        {
          'repository_id' => repository.id,
          'state' => 'success'
        }
      end

      it 'raises error for missing sha' do
        expect { executor.execute }.to raise_error(
          Mcp::AiWorkflowOrchestrator::NodeExecutionError,
          /sha is required/
        )
      end
    end

    context 'when state is invalid' do
      let(:configuration) do
        {
          'repository_id' => repository.id,
          'sha' => 'abc123',
          'state' => 'invalid'
        }
      end

      it 'raises error for invalid state' do
        expect { executor.execute }.to raise_error(
          Mcp::AiWorkflowOrchestrator::NodeExecutionError,
          /state must be one of/
        )
      end
    end
  end
end

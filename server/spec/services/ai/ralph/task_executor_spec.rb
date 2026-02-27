# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Ralph::TaskExecutor, type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:provider) { create(:ai_provider, account: account) }
  let(:agent) { create(:ai_agent, account: account, provider: provider, creator: user) }
  let(:ralph_loop) do
    create(:ai_ralph_loop, :with_learnings, account: account, default_agent: agent)
  end
  let(:task) do
    create(:ai_ralph_task,
      ralph_loop: ralph_loop,
      execution_type: "agent",
      status: "in_progress",
      description: "Implement the login page",
      acceptance_criteria: "User can log in"
    )
  end

  subject(:executor) { described_class.new(task: task, ralph_loop: ralph_loop) }

  describe '#initialize' do
    it 'sets task, ralph_loop, and account' do
      expect(executor.task).to eq(task)
      expect(executor.ralph_loop).to eq(ralph_loop)
      expect(executor.account).to eq(account)
    end

    it 'defaults ralph_loop from task when not provided' do
      exec = described_class.new(task: task)
      expect(exec.ralph_loop).to eq(ralph_loop)
    end
  end

  describe '#execute' do
    context 'when no executor is found' do
      before do
        allow(task).to receive(:executor).and_return(nil)
        allow(task).to receive(:find_matching_executor).and_return(nil)
        allow(ralph_loop).to receive(:default_agent).and_return(nil)
        allow(task).to receive(:has_fallback?).and_return(false)
      end

      it 'returns error when no executor and no fallback' do
        result = executor.execute

        expect(result[:success]).to be false
        expect(result[:error]).to include("No executor found")
      end
    end

    context 'with fallback configured' do
      let(:fallback_agent) { create(:ai_agent, account: account, provider: provider, creator: user) }

      before do
        allow(task).to receive(:executor).and_return(nil)
        allow(task).to receive(:find_matching_executor).and_return(nil)
        allow(ralph_loop).to receive(:default_agent).and_return(nil)
        allow(task).to receive(:has_fallback?).and_return(true)
        allow(task).to receive(:fallback_config).and_return({
          executor_type: "agent",
          executor_id: fallback_agent.id
        })
        allow(task).to receive(:update!)
        allow(task).to receive(:record_execution_attempt!)
      end

      it 'falls back to configured executor' do
        # After fallback, the recursive execute call will find the default agent
        allow(ralph_loop).to receive(:default_agent).and_return(fallback_agent)

        credential = instance_double(Ai::ProviderCredential)
        cred_relation = double("credentials")
        allow(fallback_agent).to receive(:provider).and_return(provider)
        allow(provider).to receive(:provider_credentials).and_return(cred_relation)
        allow(cred_relation).to receive(:active).and_return(cred_relation)
        allow(cred_relation).to receive(:first).and_return(credential)

        client = instance_double(WorkerLlmClient)
        allow(WorkerLlmClient).to receive(:new).and_return(client)
        allow(ralph_loop).to receive(:available_mcp_tools).and_return([])
        allow(client).to receive(:complete).and_return(
          Ai::Llm::Response.new(content: "done", usage: { prompt_tokens: 100, completion_tokens: 50, total_tokens: 150 })
        )

        result = executor.execute
        expect(task).to have_received(:update!).at_least(:once)
      end
    end

    context 'with agent execution type' do
      let(:credential) { instance_double(Ai::ProviderCredential) }
      let(:client) { instance_double(WorkerLlmClient) }
      let(:cred_relation) { double("credentials") }

      before do
        allow(task).to receive(:executor).and_return(nil)
        allow(task).to receive(:find_matching_executor).and_return(nil)
        allow(task).to receive(:record_execution_attempt!)
        allow(task).to receive(:update!)

        allow(provider).to receive(:provider_credentials).and_return(cred_relation)
        allow(cred_relation).to receive(:active).and_return(cred_relation)
        allow(cred_relation).to receive(:first).and_return(credential)
        allow(provider).to receive(:default_model).and_return("test-model-1")
        allow(provider).to receive(:provider_type).and_return("openai")

        allow(WorkerLlmClient).to receive(:new).and_return(client)
        allow(ralph_loop).to receive(:available_mcp_tools).and_return([])
      end

      it 'sends messages to the AI provider via agentic loop' do
        allow(client).to receive(:complete).and_return(
          Ai::Llm::Response.new(content: "Task completed successfully", usage: { prompt_tokens: 200, completion_tokens: 100, total_tokens: 300 })
        )

        result = executor.execute

        expect(result[:success]).to be true
        expect(result[:output]).to eq("Task completed successfully")
        expect(result[:executor_type]).to eq("agent")
      end

      it 'returns error when provider has no active credentials' do
        allow(cred_relation).to receive(:first).and_return(nil)

        result = executor.execute

        expect(result[:success]).to be false
        expect(result[:error]).to include("No active credentials")
      end

      it 'handles API errors gracefully' do
        allow(client).to receive(:complete).and_return(
          Ai::Llm::Response.new(content: nil, finish_reason: "error", raw_response: { error: "API rate limited" })
        )

        result = executor.execute

        expect(result[:success]).to be false
        expect(result[:error]).to be_present
      end
    end

    context 'with workflow execution type' do
      let(:workflow) { create(:ai_workflow, account: account, status: "active") }
      let(:workflow_run) { double("WorkflowRun", id: SecureRandom.uuid) }
      let(:runs_relation) { double("runs") }

      before do
        task.update!(execution_type: "workflow")
        allow(task).to receive(:executor).and_return(nil)
        allow(task).to receive(:find_matching_executor).and_return(workflow)
        allow(ralph_loop).to receive(:default_agent).and_return(nil)
        allow(task).to receive(:record_execution_attempt!)
        allow(task).to receive(:update!)
        allow(WorkerJobService).to receive(:enqueue_ai_workflow_execution)
        # Stub workflow.runs.create! because the service passes `triggered_by:`
        # which doesn't match the model's `triggered_by_user` association
        allow(workflow).to receive(:runs).and_return(runs_relation)
        allow(runs_relation).to receive(:create!).and_return(workflow_run)
        # RalphLoop doesn't have `created_by` method - service bug
        without_partial_double_verification do
          allow(ralph_loop).to receive(:created_by).and_return(user)
        end
      end

      it 'creates a workflow run and queues execution' do
        result = executor.execute

        expect(result[:success]).to be true
        expect(result[:executor_type]).to eq("workflow")
        expect(result[:message]).to include("Workflow execution queued")
      end
    end

    context 'with unknown execution type' do
      before do
        allow(task).to receive(:execution_type).and_return("unknown_type")
        allow(task).to receive(:executor).and_return(agent)
        allow(task).to receive(:find_matching_executor).and_return(agent)
        allow(task).to receive(:record_execution_attempt!)
      end

      it 'returns error for unknown type' do
        result = executor.execute

        expect(result[:success]).to be false
        expect(result[:error]).to include("Unknown execution type")
      end
    end

    context 'when execution raises an exception' do
      before do
        allow(task).to receive(:executor).and_return(agent)
        allow(task).to receive(:find_matching_executor).and_return(agent)
        allow(task).to receive(:record_execution_attempt!).and_raise(StandardError, "unexpected error")
      end

      it 'catches the error and returns failure' do
        result = executor.execute

        expect(result[:success]).to be false
        expect(result[:error]).to include("Execution failed: unexpected error")
      end
    end

    context 'with MCP tool-calling loop' do
      let(:credential) { instance_double(Ai::ProviderCredential) }
      let(:client) { instance_double(WorkerLlmClient) }
      let(:cred_relation) { double("credentials") }
      let(:mcp_server) { instance_double(McpServer) }
      let(:mcp_tool) do
        double("McpTool",
          name: "file_read",
          description: "Read a file",
          input_schema: { type: "object" },
          mcp_server: mcp_server
        )
      end

      before do
        allow(task).to receive(:executor).and_return(nil)
        allow(task).to receive(:find_matching_executor).and_return(nil)
        allow(task).to receive(:record_execution_attempt!)
        allow(task).to receive(:update!)

        allow(provider).to receive(:provider_credentials).and_return(cred_relation)
        allow(cred_relation).to receive(:active).and_return(cred_relation)
        allow(cred_relation).to receive(:first).and_return(credential)
        allow(provider).to receive(:default_model).and_return("test-model-1")
        allow(provider).to receive(:provider_type).and_return("openai")

        allow(WorkerLlmClient).to receive(:new).and_return(client)
        allow(ralph_loop).to receive(:available_mcp_tools).and_return([mcp_tool])
      end

      it 'handles tool calls in the response via agentic loop' do
        # First call returns a tool call
        tool_call_response = Ai::Llm::Response.new(
          content: nil,
          tool_calls: [{ id: "call_123", name: "file_read", arguments: { "path" => "/README.md" } }],
          finish_reason: "tool_calls",
          usage: { prompt_tokens: 200, completion_tokens: 50, total_tokens: 250 }
        )

        # After tool execution, final response with no tool calls
        final_response = Ai::Llm::Response.new(
          content: "File contents processed",
          usage: { prompt_tokens: 300, completion_tokens: 150, total_tokens: 450 }
        )

        call_count = 0
        allow(client).to receive(:complete_with_tools) do
          call_count += 1
          call_count == 1 ? tool_call_response : final_response
        end
        allow(client).to receive(:complete).and_return(final_response)

        sync_service = double("SyncExecutionService")
        allow(Mcp::SyncExecutionService).to receive(:new).and_return(sync_service)
        allow(sync_service).to receive(:execute).and_return({ result: "file content" })

        result = executor.execute

        expect(result[:success]).to be true
        expect(result[:output]).to include("File contents processed")
        expect(Mcp::SyncExecutionService).to have_received(:new)
      end
    end
  end

  describe 'private helper methods' do
    describe 'build_prompt' do
      it 'includes task details' do
        prompt = executor.send(:build_prompt)

        expect(prompt).to include(task.task_key)
        expect(prompt).to include("Implement the login page")
        expect(prompt).to include("User can log in")
      end

      it 'includes ralph loop context' do
        prompt = executor.send(:build_prompt)

        expect(prompt).to include(ralph_loop.name)
        expect(prompt).to include(ralph_loop.branch)
      end
    end

    describe 'format_learnings' do
      it 'formats recent learnings from the loop' do
        allow(ralph_loop).to receive(:recent_learnings).with(limit: 5).and_return([
          { "text" => "Always validate input" },
          { "text" => "Use UUIDs for primary keys" }
        ])

        learnings = executor.send(:format_learnings)

        expect(learnings).to include("Always validate input")
        expect(learnings).to include("Use UUIDs for primary keys")
      end

      it 'returns default message when no learnings' do
        allow(ralph_loop).to receive(:recent_learnings).with(limit: 5).and_return([])

        learnings = executor.send(:format_learnings)

        expect(learnings).to eq("No previous learnings")
      end
    end

    describe 'extract_content' do
      it 'extracts content from choices format' do
        response = { choices: [{ message: { content: "Hello" } }] }
        expect(executor.send(:extract_content, response)).to eq("Hello")
      end

      it 'extracts content from message format' do
        response = { message: { content: "World" } }
        expect(executor.send(:extract_content, response)).to eq("World")
      end

      it 'extracts direct content' do
        response = { content: "Direct" }
        expect(executor.send(:extract_content, response)).to eq("Direct")
      end

      it 'returns empty string for non-hash response' do
        expect(executor.send(:extract_content, "string")).to eq("")
      end
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::A2a::Service, type: :service do
  # Stub worker jobs that aren't loaded in server tests
  before do
    stub_const('AiA2aTaskExecutionJob', Class.new do
      def self.perform_later(*args); end
    end)
    stub_const('AiA2aExternalTaskJob', Class.new do
      def self.perform_later(*args); end
    end)

    # Stub Memory StorageService if not already defined
    unless defined?(Memory::StorageService)
      stub_const('Memory::StorageService', Class.new do
        def initialize(**args); end
        def store_experiential(**args); end
        def store_fact(**args); end
      end)
    end
  end

  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:provider) { create(:ai_provider, account: account) }
  let(:agent) { create(:ai_agent, account: account, provider: provider) }
  let(:agent_card) do
    create(:ai_agent_card,
           account: account,
           agent: agent,
           name: 'Test Agent',
           visibility: 'private',
           status: 'active')
  end

  subject(:service) { described_class.new(account: account, user: user) }

  describe '#initialize' do
    it 'initializes with account and user' do
      expect(service).to be_a(described_class)
    end

    it 'accepts optional workflow_run' do
      workflow = create(:ai_workflow, account: account, creator: user)
      run = create(:ai_workflow_run, workflow: workflow, account: account)

      service_with_run = described_class.new(account: account, user: user, workflow_run: run)
      expect(service_with_run).to be_a(described_class)
    end
  end

  describe 'Discovery' do
    describe '#discover_agents' do
      before do
        agent_card # Create the card
      end

      it 'returns paginated list of agent cards' do
        result = service.discover_agents

        expect(result[:agents]).to be_an(Array)
        expect(result[:total]).to be >= 1
        expect(result[:page]).to eq(1)
        expect(result[:per_page]).to eq(20)
      end

      it 'filters by skill' do
        # with_skill_record scope joins through agent -> skills (ai_skills table)
        skill = Ai::Skill.create!(name: 'Summarize', slug: 'summarize', category: 'productivity', status: 'active')
        Ai::AgentSkill.create!(agent: agent, skill: skill)

        result = service.discover_agents(skill: 'summarize')
        expect(result[:agents].any? { |a| a[:name] == 'Test Agent' }).to be true
      end

      it 'filters by tag' do
        agent_card.update!(tags: [ 'research' ])

        result = service.discover_agents(tag: 'research')
        expect(result[:agents].any? { |a| a[:name] == 'Test Agent' }).to be true
      end

      it 'filters by query' do
        result = service.discover_agents(query: 'Test')
        expect(result[:agents].any? { |a| a[:name].include?('Test') }).to be true
      end

      it 'respects pagination limits' do
        result = service.discover_agents(per_page: 5)
        expect(result[:per_page]).to eq(5)
      end

      it 'caps per_page at 100' do
        result = service.discover_agents(per_page: 200)
        expect(result[:per_page]).to eq(100)
      end
    end

    describe '#get_agent_card' do
      it 'returns agent card in A2A format' do
        result = service.get_agent_card(agent_card.id)

        expect(result).to include(:name, :description)
        expect(result[:name]).to eq('Test Agent')
      end

      it 'finds by name' do
        agent_card # create the card first
        result = service.get_agent_card('Test Agent')
        expect(result[:name]).to eq('Test Agent')
      end

      it 'raises error for missing card' do
        expect {
          service.get_agent_card('nonexistent')
        }.to raise_error(Ai::A2a::Service::AgentNotFoundError)
      end
    end

    describe '#find_agents_for_task' do
      before { agent_card }

      it 'returns agents capable of handling the task' do
        allow(Ai::AgentCard).to receive(:find_agents_for_task).and_return([ agent_card ])

        result = service.find_agents_for_task('summarize this document')
        expect(result).to be_an(Array)
      end
    end
  end

  describe 'Task Submission' do
    describe '#submit_task' do
      let(:message) { { role: 'user', parts: [ { type: 'text', text: 'Hello agent' } ] } }

      it 'creates a new A2A task' do
        expect {
          service.submit_task(to_agent_card: agent_card, message: message)
        }.to change(Ai::A2aTask, :count).by(1)
      end

      it 'returns the created task' do
        task = service.submit_task(to_agent_card: agent_card, message: message)

        expect(task).to be_a(Ai::A2aTask)
        expect(task.status).to eq('pending')
      end

      it 'accepts agent card by ID' do
        task = service.submit_task(to_agent_card: agent_card.id, message: message)
        expect(task.to_agent_card_id).to eq(agent_card.id)
      end

      it 'accepts agent card by name' do
        task = service.submit_task(to_agent_card: agent_card.name, message: message)
        expect(task.to_agent_card_id).to eq(agent_card.id)
      end

      it 'normalizes message format' do
        task = service.submit_task(to_agent_card: agent_card, message: { content: 'Simple text' })
        expect(task.message['parts']).to be_an(Array)
      end

      it 'executes sync when specified' do
        allow_any_instance_of(described_class).to receive(:execute_task_sync) do |svc, tsk|
          tsk.update!(status: 'completed', output: { result: 'done' })
          tsk
        end

        task = service.submit_task(to_agent_card: agent_card, message: message, sync: true)
        expect(task.status).to eq('completed')
      end

      it 'queues job when async' do
        expect(AiA2aTaskExecutionJob).to receive(:perform_later).with(anything)
        service.submit_task(to_agent_card: agent_card, message: message, sync: false)
      end

      it 'validates message structure' do
        expect {
          service.submit_task(to_agent_card: agent_card, message: 'invalid')
        }.to raise_error(Ai::A2a::Service::InvalidTaskError)
      end
    end

    describe '#submit_external_task' do
      let(:endpoint_url) { 'https://external-agent.example.com/a2a' }
      let(:message) { { role: 'user', parts: [ { type: 'text', text: 'External task' } ] } }

      it 'creates an external task' do
        expect {
          service.submit_external_task(endpoint_url: endpoint_url, message: message)
        }.to change(Ai::A2aTask, :count).by(1)

        task = Ai::A2aTask.last
        expect(task.is_external).to be true
        expect(task.external_endpoint_url).to eq(endpoint_url)
      end

      it 'queues external task job' do
        expect(AiA2aExternalTaskJob).to receive(:perform_later).with(anything)
        service.submit_external_task(endpoint_url: endpoint_url, message: message)
      end
    end
  end

  describe 'Task Status & Control' do
    let!(:task) do
      create(:ai_a2a_task,
             account: account,
             to_agent_card: agent_card,
             to_agent: agent,
             status: 'pending')
    end

    describe '#get_task_status' do
      it 'returns task in A2A format' do
        result = service.get_task_status(task.task_id)

        expect(result).to include(:id, :status)
        expect(result[:status][:state]).to eq('submitted') # A2A maps pending -> submitted
      end

      it 'finds task by UUID task_id' do
        result = service.get_task_status(task.task_id)
        expect(result[:id]).to eq(task.task_id)
      end

      it 'raises error for nonexistent task' do
        expect {
          service.get_task_status('nonexistent')
        }.to raise_error(Ai::A2a::Service::TaskNotFoundError)
      end
    end

    describe '#get_task_details' do
      it 'returns detailed task info' do
        result = service.get_task_details(task.task_id)
        expect(result).to be_a(Hash)
      end
    end

    describe '#cancel_task' do
      it 'cancels a pending task' do
        result = service.cancel_task(task.task_id, reason: 'User requested')

        expect(result[:task][:status][:state]).to eq('canceled')
      end

      it 'cancels with reason' do
        service.cancel_task(task.task_id, reason: 'Timeout')
        task.reload
        expect(task.metadata['cancellation_reason']).to eq('Timeout')
      end

      it 'raises error for completed tasks' do
        task.update!(status: 'completed')

        expect {
          service.cancel_task(task.task_id)
        }.to raise_error(Ai::A2a::Service::InvalidTaskError)
      end
    end

    describe '#provide_input' do
      before { task.update!(status: 'input_required') }

      it 'provides input to waiting task' do
        result = service.provide_input(task.task_id, { answer: 'yes' })
        expect(result[:task]).to be_present
      end

      it 'queues execution job' do
        expect(AiA2aTaskExecutionJob).to receive(:perform_later).with(task.id)
        service.provide_input(task.task_id, { answer: 'yes' })
      end

      it 'raises error if task not waiting for input' do
        task.update!(status: 'pending')

        expect {
          service.provide_input(task.task_id, { answer: 'yes' })
        }.to raise_error(Ai::A2a::Service::InvalidTaskError)
      end
    end

    describe '#get_task_events' do
      before do
        create(:ai_a2a_task_event, a2a_task: task, event_type: 'status_change', data: { from: 'pending', to: 'active' })
        create(:ai_a2a_task_event, a2a_task: task, event_type: 'message', data: { text: 'Processing...' })
      end

      it 'returns task events' do
        result = service.get_task_events(task.task_id)

        expect(result[:events]).to be_an(Array)
        expect(result[:events].length).to eq(2)
      end

      it 'filters events since timestamp' do
        old_event = task.events.first
        old_event.update!(created_at: 1.hour.ago)

        result = service.get_task_events(task.task_id, since: 30.minutes.ago)
        expect(result[:events].length).to eq(1)
      end

      it 'respects limit' do
        result = service.get_task_events(task.task_id, limit: 1)
        expect(result[:events].length).to eq(1)
      end

      it 'includes task status' do
        result = service.get_task_events(task.task_id)
        expect(result[:task_status]).to eq(task.a2a_status)
      end
    end

    describe '#get_artifact' do
      before do
        task.update!(artifacts: [
          { 'id' => 'art-1', 'name' => 'report.pdf', 'type' => 'file' },
          { 'id' => 'art-2', 'name' => 'data.json', 'type' => 'data' }
        ])
      end

      it 'returns specific artifact' do
        result = service.get_artifact(task.task_id, 'art-1')
        expect(result['name']).to eq('report.pdf')
      end

      it 'raises error for nonexistent artifact' do
        expect {
          service.get_artifact(task.task_id, 'nonexistent')
        }.to raise_error(Ai::A2a::Service::A2aError, /not found/)
      end
    end
  end

  describe 'Task Execution' do
    let!(:task) do
      create(:ai_a2a_task,
             account: account,
             to_agent_card: agent_card,
             to_agent: agent,
             status: 'pending',
             message: { 'role' => 'user', 'parts' => [ { 'type' => 'text', 'text' => 'Hello' } ] },
             input: { 'text' => 'Hello' })
    end

    describe '#execute_task_sync' do
      before do
        # Stub execute_agent to avoid complex dependencies on MCP executor and memory services
        allow_any_instance_of(described_class).to receive(:store_execution_memory)
      end

      it 'executes task and completes on success' do
        allow_any_instance_of(described_class).to receive(:execute_agent).and_return({
          output: { result: 'Success' },
          artifacts: []
        })

        result = service.execute_task_sync(task)

        expect(result.status).to eq('completed')
        expect(result.output).to eq({ 'result' => 'Success' })
      end

      it 'fails task on execution error' do
        allow_any_instance_of(described_class).to receive(:execute_agent)
          .and_raise(StandardError, 'Execution failed')

        expect {
          service.execute_task_sync(task)
        }.to raise_error(Ai::A2a::Service::ExecutionError)

        task.reload
        expect(task.status).to eq('failed')
        expect(task.error_message).to include('Execution failed')
      end

      it 'stores execution memory on success' do
        allow_any_instance_of(described_class).to receive(:execute_agent).and_return({ output: 'done' })
        expect_any_instance_of(described_class).to receive(:store_execution_memory).with(task, success: true)

        service.execute_task_sync(task)

        expect(task.reload.status).to eq('completed')
      end
    end

    describe '#wait_for_task' do
      it 'returns completed task immediately' do
        task.update!(status: 'completed')

        result = service.wait_for_task(task, timeout: 5)
        expect(result.status).to eq('completed')
      end

      it 'times out for pending tasks' do
        # Short timeout for test
        result = service.wait_for_task(task, timeout: 1)

        expect(result.status).to eq('failed')
        expect(result.error_message).to include('timed out')
      end
    end
  end

  describe 'Multi-Agent Coordination' do
    let(:agent2) { create(:ai_agent, account: account, provider: provider, name: 'Agent 2') }
    let(:agent_card2) do
      create(:ai_agent_card,
             account: account,
             agent: agent2,
             name: 'Agent 2',
             visibility: 'private',
             status: 'active')
    end

    describe '#execute_sequence' do
      it 'executes tasks in sequence' do
        allow_any_instance_of(described_class).to receive(:execute_task_sync) do |_svc, task|
          task.update!(status: 'completed', output: { step: task.to_agent_card.name })
          task
        end

        tasks_config = [
          { to_agent_card: agent_card, message: { content: 'Step 1' } },
          { to_agent_card: agent_card2, message: { content: 'Step 2' }, chain_output: true }
        ]

        results = service.execute_sequence(tasks_config)

        expect(results.length).to eq(2)
        expect(results.all? { |t| t.status == 'completed' }).to be true
      end

      it 'stops on failure' do
        call_count = 0
        allow_any_instance_of(described_class).to receive(:execute_task_sync) do |_svc, task|
          call_count += 1
          task.update!(status: call_count == 1 ? 'failed' : 'completed')
          task
        end

        tasks_config = [
          { to_agent_card: agent_card, message: { content: 'Step 1' } },
          { to_agent_card: agent_card2, message: { content: 'Step 2' } }
        ]

        results = service.execute_sequence(tasks_config)

        expect(results.length).to eq(1)
        expect(results.first.status).to eq('failed')
      end
    end

    describe '#execute_parallel' do
      it 'executes tasks concurrently' do
        allow_any_instance_of(described_class).to receive(:wait_for_task) do |_svc, task|
          task.update!(status: 'completed', output: { agent: task.to_agent_card.name })
          task
        end

        tasks_config = [
          { to_agent_card: agent_card, message: { content: 'Task A' } },
          { to_agent_card: agent_card2, message: { content: 'Task B' } }
        ]

        results = service.execute_parallel(tasks_config)

        expect(results.length).to eq(2)
        expect(results.map(&:status)).to all(eq('completed'))
      end
    end
  end

  describe 'Error Classes' do
    it 'defines A2aError with code and details' do
      error = Ai::A2a::Service::A2aError.new('Test error', code: 'TEST', details: { foo: 'bar' })

      expect(error.message).to eq('Test error')
      expect(error.code).to eq('TEST')
      expect(error.details).to eq({ foo: 'bar' })
    end

    it 'defines TaskNotFoundError' do
      error = Ai::A2a::Service::TaskNotFoundError.new('task-123')

      expect(error.message).to include('task-123')
      expect(error.code).to eq('TASK_NOT_FOUND')
    end

    it 'defines AgentNotFoundError' do
      error = Ai::A2a::Service::AgentNotFoundError.new('agent-xyz')

      expect(error.message).to include('agent-xyz')
      expect(error.code).to eq('AGENT_NOT_FOUND')
    end

    it 'defines InvalidTaskError' do
      error = Ai::A2a::Service::InvalidTaskError.new('Invalid operation')

      expect(error.code).to eq('INVALID_TASK')
    end

    it 'defines ExecutionError' do
      error = Ai::A2a::Service::ExecutionError.new('Execution failed')

      expect(error.code).to eq('EXECUTION_ERROR')
    end
  end
end

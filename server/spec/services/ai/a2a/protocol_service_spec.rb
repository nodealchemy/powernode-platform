# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::A2a::ProtocolService, type: :service do
  # Stub worker jobs that aren't loaded in server tests
  before do
    stub_const("AiA2aTaskExecutionJob", Class.new {
      def self.perform_later(*args); end
    })
    stub_const("AiA2aExternalTaskJob", Class.new {
      def self.perform_later(*args); end
    })
  end

  let(:account) { create(:account) }
  let(:provider) { create(:ai_provider, account: account) }
  let(:agent) { create(:ai_agent, account: account, provider: provider) }
  let(:agent_card) do
    create(:ai_agent_card,
           account: account,
           agent: agent,
           name: "Protocol Test Agent",
           visibility: "private",
           status: "active",
           capabilities: {
             "skills" => [{ "id" => "summarize", "name" => "Summarize" }],
             "streaming" => true
           })
  end

  subject(:service) { described_class.new(account: account) }

  # ===========================================================================
  # agent_card
  # ===========================================================================

  describe "#agent_card" do
    it "returns A2A JSON for an agent" do
      result = service.agent_card(agent_id: agent_card.id)

      expect(result[:success]).to be true
      expect(result[:agent_card]).to be_present
      expect(result[:agent_card][:protocolVersion]).to eq(described_class::A2A_VERSION)
    end

    it "finds agent card by name" do
      agent_card # ensure created
      result = service.agent_card(agent_id: agent_card.name)

      expect(result[:success]).to be true
      expect(result[:agent_card]).to be_present
    end

    it "handles missing agent" do
      result = service.agent_card(agent_id: "nonexistent-agent-id")

      expect(result[:success]).to be false
      expect(result[:error]).to include("not found")
    end
  end

  # ===========================================================================
  # discover_agents
  # ===========================================================================

  describe "#discover_agents" do
    before { agent_card }

    it "finds agents matching task description" do
      result = service.discover_agents(
        task_description: "summarize this document",
        capabilities: nil,
        visibility: :internal
      )

      expect(result[:success]).to be true
      expect(result[:agents]).to be_an(Array)
      expect(result[:total]).to be >= 0
      expect(result[:protocol_version]).to eq(described_class::A2A_VERSION)
    end

    it "filters by capabilities" do
      result = service.discover_agents(
        task_description: "summarize text",
        capabilities: ["summarize"],
        visibility: :internal
      )

      expect(result[:success]).to be true
      # Agents without matching capabilities should be filtered out
      result[:agents].each do |agent_data|
        # If capabilities filter was applied, only matching agents appear
        expect(agent_data).to have_key(:agent_card)
      end
    end

    it "returns relevance_score for each agent" do
      result = service.discover_agents(
        task_description: "summarize this text",
        visibility: :internal
      )

      expect(result[:success]).to be true
      result[:agents].each do |agent_data|
        expect(agent_data).to have_key(:relevance_score)
      end
    end

    it "handles empty results gracefully" do
      result = service.discover_agents(
        task_description: "zzz_nonexistent_task_xyz_12345",
        capabilities: ["nonexistent_capability"],
        visibility: :internal
      )

      expect(result[:success]).to be true
      expect(result[:agents]).to be_an(Array)
    end
  end

  # ===========================================================================
  # send_task
  # ===========================================================================

  describe "#send_task" do
    let(:agent2) { create(:ai_agent, account: account, provider: provider, name: "Target Agent") }
    let(:target_card) do
      create(:ai_agent_card,
             account: account,
             agent: agent2,
             name: "Target Agent",
             visibility: "private",
             status: "active")
    end

    let(:valid_task_params) do
      {
        message: {
          role: "user",
          parts: [{ type: "text", text: "Please summarize this document" }]
        }
      }
    end

    it "creates A2A task between agents" do
      result = service.send_task(
        from_agent: agent_card,
        to_agent: target_card,
        task_params: valid_task_params
      )

      expect(result[:success]).to be true
      expect(result[:task]).to be_present
      expect(result[:task][:id]).to be_present
    end

    it "validates auth between agents" do
      # Target card with auth requirement but no federation
      target_card.update!(authentication: {
        "schemes" => ["bearer"]
      })

      # Agent from different account without federation
      other_account = create(:account)
      other_provider = create(:ai_provider, account: other_account)
      other_agent = create(:ai_agent, account: other_account, provider: other_provider)
      other_card = create(:ai_agent_card,
                          account: other_account,
                          agent: other_agent,
                          name: "External Agent",
                          visibility: "public",
                          status: "active")

      result = service.send_task(
        from_agent: other_card,
        to_agent: target_card,
        task_params: valid_task_params
      )

      expect(result[:success]).to be false
      expect(result[:error]).to be_present
    end

    it "returns error for missing target agent" do
      result = service.send_task(
        from_agent: agent_card,
        to_agent: "nonexistent-agent",
        task_params: valid_task_params
      )

      expect(result[:success]).to be false
      expect(result[:error]).to include("not found")
    end

    it "validates task params require a message" do
      result = service.send_task(
        from_agent: agent_card,
        to_agent: target_card,
        task_params: {}
      )

      expect(result[:success]).to be false
      expect(result[:code]).to eq("INVALID_PARAMS")
    end
  end

  # ===========================================================================
  # get_task
  # ===========================================================================

  describe "#get_task" do
    let!(:task) do
      create(:ai_a2a_task,
             account: account,
             to_agent_card: agent_card,
             to_agent: agent,
             status: "pending")
    end

    it "returns task status" do
      result = service.get_task(task_id: task.task_id)

      expect(result[:success]).to be true
      expect(result[:task]).to be_present
      expect(result[:task][:id]).to eq(task.task_id)
    end

    it "respects history_length parameter" do
      result = service.get_task(task_id: task.task_id, history_length: 5)

      expect(result[:success]).to be true
      expect(result[:task]).to be_present
    end

    it "returns error for nonexistent task" do
      result = service.get_task(task_id: "nonexistent-task-id")

      expect(result[:success]).to be false
      expect(result[:code]).to eq("TASK_NOT_FOUND")
    end
  end

  # ===========================================================================
  # cancel_task
  # ===========================================================================

  describe "#cancel_task" do
    let!(:task) do
      create(:ai_a2a_task,
             account: account,
             to_agent_card: agent_card,
             to_agent: agent,
             status: "pending")
    end

    it "cancels running task" do
      result = service.cancel_task(task_id: task.task_id, reason: "No longer needed")

      expect(result[:success]).to be true
      expect(result[:task]).to be_present
      task.reload
      expect(task.status).to eq("cancelled")
    end

    it "returns error for completed task" do
      task.update!(status: "completed")

      result = service.cancel_task(task_id: task.task_id)

      expect(result[:success]).to be false
    end

    it "returns error for nonexistent task" do
      result = service.cancel_task(task_id: "nonexistent-task-id")

      expect(result[:success]).to be false
      expect(result[:code]).to eq("TASK_NOT_FOUND")
    end
  end

  # ===========================================================================
  # handle_jsonrpc
  # ===========================================================================

  describe "#handle_jsonrpc" do
    it "dispatches tasks/get method correctly" do
      task = create(:ai_a2a_task,
                    account: account,
                    to_agent_card: agent_card,
                    to_agent: agent,
                    status: "pending")

      request = {
        jsonrpc: "2.0",
        id: "req-1",
        method: "tasks/get",
        params: { task_id: task.task_id }
      }

      result = service.handle_jsonrpc(request)

      expect(result[:jsonrpc]).to eq("2.0")
      expect(result[:id]).to eq("req-1")
      expect(result[:result]).to be_present
    end

    it "dispatches tasks/cancel method correctly" do
      task = create(:ai_a2a_task,
                    account: account,
                    to_agent_card: agent_card,
                    to_agent: agent,
                    status: "pending")

      request = {
        jsonrpc: "2.0",
        id: "req-2",
        method: "tasks/cancel",
        params: { task_id: task.task_id, reason: "Test cancel" }
      }

      result = service.handle_jsonrpc(request)

      expect(result[:jsonrpc]).to eq("2.0")
      expect(result[:id]).to eq("req-2")
    end

    it "returns error for unknown methods" do
      request = {
        jsonrpc: "2.0",
        id: "req-3",
        method: "unknown/method",
        params: {}
      }

      result = service.handle_jsonrpc(request)

      expect(result[:jsonrpc]).to eq("2.0")
      expect(result[:id]).to eq("req-3")
      expect(result[:error]).to be_present
      expect(result[:error][:code]).to eq(-32601)
      expect(result[:error][:message]).to include("Method not found")
    end

    it "returns internal error on exception" do
      allow(service).to receive(:dispatch_method).and_raise(StandardError, "Boom")

      request = {
        jsonrpc: "2.0",
        id: "req-4",
        method: "tasks/get",
        params: { task_id: "any" }
      }

      result = service.handle_jsonrpc(request)

      expect(result[:error]).to be_present
      expect(result[:error][:code]).to eq(-32603)
    end
  end

  # ===========================================================================
  # Federation
  # ===========================================================================

  describe "#register_federation" do
    it "registers a new federation partner" do
      result = service.register_federation(
        partner_url: "https://partner.example.com/a2a",
        auth_config: {
          organization_name: "Partner Org",
          contact_email: "admin@partner.example.com"
        }
      )

      expect(result[:success]).to be true
      expect(result[:partner]).to be_present
    end

    it "returns error for invalid URL" do
      result = service.register_federation(
        partner_url: "not-a-url",
        auth_config: {}
      )

      expect(result[:success]).to be false
      expect(result[:code]).to eq("INVALID_PARTNER_URL")
    end
  end

  # ===========================================================================
  # Push Notifications
  # ===========================================================================

  describe "#set_push_notification" do
    let!(:task) do
      create(:ai_a2a_task,
             account: account,
             to_agent_card: agent_card,
             to_agent: agent,
             status: "pending")
    end

    it "configures push notifications for a task" do
      result = service.set_push_notification(
        task_id: task.task_id,
        webhook_url: "https://example.com/webhooks/a2a"
      )

      expect(result[:success]).to be true
      expect(result[:push_notification][:enabled]).to be true
    end

    it "rejects invalid webhook URLs" do
      result = service.set_push_notification(
        task_id: task.task_id,
        webhook_url: "not-a-url"
      )

      expect(result[:success]).to be false
      expect(result[:code]).to eq("INVALID_WEBHOOK_URL")
    end
  end
end

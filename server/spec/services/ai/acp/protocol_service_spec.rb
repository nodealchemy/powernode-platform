# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Acp::ProtocolService, type: :service do
  # Stub worker jobs that aren't loaded in server tests
  before do
    stub_const("AiA2aTaskExecutionJob", Class.new {
      def self.perform_later(*args); end
    })
    stub_const("AiA2aExternalTaskJob", Class.new {
      def self.perform_later(*args); end
    })

    # AgentCard uses card_version column, but ACP service references .version
    # Define the missing method to avoid NoMethodError
    unless Ai::AgentCard.method_defined?(:version)
      Ai::AgentCard.define_method(:version) { card_version }
    end
  end

  let(:account) { create(:account) }
  let(:provider) { create(:ai_provider, account: account) }
  let(:agent) { create(:ai_agent, account: account, provider: provider) }
  let(:agent_card) do
    create(:ai_agent_card,
           account: account,
           agent: agent,
           name: "ACP Test Agent",
           visibility: "private",
           status: "active",
           capabilities: {
             "skills" => [
               { "id" => "summarize", "name" => "Summarize Text" },
               { "id" => "translate", "name" => "Translate" }
             ],
             "streaming" => true,
             "accepts_files" => true
           })
  end

  subject(:service) { described_class.new(account: account) }

  # ===========================================================================
  # list_agents
  # ===========================================================================

  describe "#list_agents" do
    before { agent_card }

    it "returns all discoverable agents" do
      result = service.list_agents

      expect(result[:success]).to be true
      expect(result[:agents]).to be_an(Array)
      expect(result[:total]).to be >= 1
      expect(result[:protocol]).to eq("acp")
      expect(result[:version]).to eq(described_class::ACP_VERSION)
    end

    it "filters agents by query using ILIKE" do
      result = service.list_agents(filter: { query: "ACP Test" })

      expect(result[:success]).to be true
      expect(result[:agents].any? { |a| a[:name] == "ACP Test Agent" }).to be true
    end

    it "filters agents by capabilities" do
      result = service.list_agents(filter: { capabilities: ["summarize"] })

      expect(result[:success]).to be true
      result[:agents].each do |a|
        expect(a[:capabilities]).to include("summarize")
      end
    end

    it "returns empty results for non-matching query" do
      result = service.list_agents(filter: { query: "nonexistent_zzz_12345" })

      expect(result[:success]).to be true
      expect(result[:agents]).to be_empty
      expect(result[:total]).to eq(0)
    end

    it "sanitizes SQL LIKE special characters in query" do
      # Should not raise an error with SQL injection chars
      result = service.list_agents(filter: { query: "test%_'" })

      expect(result[:success]).to be true
      expect(result[:agents]).to be_an(Array)
    end

    it "returns ACP profile format for each agent" do
      result = service.list_agents

      agent_profile = result[:agents].find { |a| a[:name] == "ACP Test Agent" }
      expect(agent_profile).to be_present
      expect(agent_profile[:protocol]).to eq("acp")
      expect(agent_profile[:protocol_version]).to eq(described_class::ACP_VERSION)
      expect(agent_profile[:capabilities]).to include("summarize", "translate")
      expect(agent_profile[:input_modes]).to include("text", "file")
      expect(agent_profile[:endpoint]).to include("/messages")
      expect(agent_profile[:events_endpoint]).to include("/events")
    end
  end

  # ===========================================================================
  # get_agent_profile
  # ===========================================================================

  describe "#get_agent_profile" do
    it "returns agent profile by ID" do
      result = service.get_agent_profile(agent_id: agent_card.id)

      expect(result[:success]).to be true
      expect(result[:agent][:id]).to eq(agent_card.id)
      expect(result[:agent][:name]).to eq("ACP Test Agent")
      expect(result[:agent][:protocol]).to eq("acp")
    end

    it "returns agent profile by name" do
      agent_card # ensure created
      result = service.get_agent_profile(agent_id: "ACP Test Agent")

      expect(result[:success]).to be true
      expect(result[:agent][:name]).to eq("ACP Test Agent")
    end

    it "returns error for nonexistent agent" do
      result = service.get_agent_profile(agent_id: "nonexistent-id")

      expect(result[:success]).to be false
      expect(result[:code]).to eq("AGENT_NOT_FOUND")
    end
  end

  # ===========================================================================
  # negotiate_capabilities
  # ===========================================================================

  describe "#negotiate_capabilities" do
    it "returns compatible when all required capabilities match" do
      result = service.negotiate_capabilities(
        agent_id: agent_card.id,
        offered_capabilities: ["code_review"],
        required_capabilities: ["summarize", "translate"]
      )

      expect(result[:success]).to be true
      expect(result[:compatible]).to be true
      expect(result[:matched_capabilities]).to contain_exactly("summarize", "translate")
      expect(result[:unmatched_capabilities]).to be_empty
    end

    it "returns incompatible when required capabilities are missing" do
      result = service.negotiate_capabilities(
        agent_id: agent_card.id,
        offered_capabilities: [],
        required_capabilities: ["summarize", "nonexistent_cap"]
      )

      expect(result[:success]).to be true
      expect(result[:compatible]).to be false
      expect(result[:unmatched_capabilities]).to include("nonexistent_cap")
    end

    it "returns error for nonexistent agent" do
      result = service.negotiate_capabilities(
        agent_id: "nonexistent-id",
        offered_capabilities: [],
        required_capabilities: []
      )

      expect(result[:success]).to be false
      expect(result[:code]).to eq("AGENT_NOT_FOUND")
    end

    it "includes negotiated_at timestamp" do
      result = service.negotiate_capabilities(
        agent_id: agent_card.id,
        offered_capabilities: [],
        required_capabilities: []
      )

      expect(result[:success]).to be true
      expect(result[:negotiated_at]).to be_present
    end
  end

  # ===========================================================================
  # send_message
  # ===========================================================================

  describe "#send_message" do
    let(:target_agent) { create(:ai_agent, account: account, provider: provider) }
    let(:target_card) do
      create(:ai_agent_card,
             account: account,
             agent: target_agent,
             name: "Target ACP Agent",
             visibility: "private",
             status: "active")
    end

    it "sends a text message to an agent" do
      result = service.send_message(
        to_agent_id: target_card.id,
        from_agent_id: agent_card.id,
        message: { type: "text", content: "Hello agent" }
      )

      expect(result[:success]).to be true
      expect(result[:message_id]).to be_present
      expect(result[:agent_id]).to eq(target_card.id)
      expect(result[:protocol]).to eq("acp")
    end

    it "rejects unsupported message types" do
      result = service.send_message(
        to_agent_id: target_card.id,
        message: { type: "video", content: "test" }
      )

      expect(result[:success]).to be false
      expect(result[:code]).to eq("INVALID_MESSAGE_TYPE")
    end

    it "returns error for nonexistent target agent" do
      result = service.send_message(
        to_agent_id: "nonexistent-id",
        message: { type: "text", content: "Hello" }
      )

      expect(result[:success]).to be false
      expect(result[:code]).to eq("AGENT_NOT_FOUND")
    end

    it "supports request message type" do
      result = service.send_message(
        to_agent_id: target_card.id,
        from_agent_id: agent_card.id,
        message: { type: "request", content: "Summarize this document" }
      )

      expect(result[:success]).to be true
    end
  end

  # ===========================================================================
  # get_message
  # ===========================================================================

  describe "#get_message" do
    let!(:task) do
      create(:ai_a2a_task,
             account: account,
             to_agent_card: agent_card,
             to_agent: agent,
             status: "pending",
             metadata: { "acp_message_type" => "text" })
    end

    it "returns message by ID" do
      result = service.get_message(message_id: task.task_id)

      expect(result[:success]).to be true
      expect(result[:message]).to be_present
      expect(result[:message][:id]).to eq(task.task_id)
    end

    it "returns error for nonexistent message" do
      result = service.get_message(message_id: "nonexistent-msg-id")

      expect(result[:success]).to be false
      expect(result[:code]).to eq("MESSAGE_NOT_FOUND")
    end
  end

  # ===========================================================================
  # cancel_message
  # ===========================================================================

  describe "#cancel_message" do
    let!(:task) do
      create(:ai_a2a_task,
             account: account,
             to_agent_card: agent_card,
             to_agent: agent,
             status: "pending")
    end

    it "cancels a pending message" do
      result = service.cancel_message(message_id: task.task_id, reason: "No longer needed")

      expect(result[:success]).to be true
      expect(result[:status]).to eq("cancelled")
      expect(result[:reason]).to eq("No longer needed")
    end

    it "returns error for nonexistent message" do
      result = service.cancel_message(message_id: "nonexistent-msg-id")

      expect(result[:success]).to be false
    end
  end

  # ===========================================================================
  # get_agent_events
  # ===========================================================================

  describe "#get_agent_events" do
    let!(:task) do
      create(:ai_a2a_task,
             account: account,
             to_agent_card: agent_card,
             to_agent: agent,
             status: "completed",
             metadata: { "acp_message_type" => "text" })
    end

    it "returns events for an agent" do
      result = service.get_agent_events(agent_id: agent_card.id)

      expect(result[:success]).to be true
      expect(result[:events]).to be_an(Array)
      expect(result[:agent_id]).to eq(agent_card.id)
    end

    it "limits event count" do
      result = service.get_agent_events(agent_id: agent_card.id, limit: 1)

      expect(result[:success]).to be true
      expect(result[:events].size).to be <= 1
    end

    it "returns error for nonexistent agent" do
      result = service.get_agent_events(agent_id: "nonexistent-id")

      expect(result[:success]).to be false
      expect(result[:code]).to eq("AGENT_NOT_FOUND")
    end
  end

  # ===========================================================================
  # protocol_info
  # ===========================================================================

  describe "#protocol_info" do
    it "returns protocol metadata" do
      result = service.protocol_info

      expect(result[:success]).to be true
      expect(result[:protocol]).to eq("acp")
      expect(result[:version]).to eq(described_class::ACP_VERSION)
      expect(result[:supported_protocols]).to include("acp", "a2a")
      expect(result[:supported_message_types]).to eq(described_class::SUPPORTED_MESSAGE_TYPES)
      expect(result[:endpoints]).to be_a(Hash)
      expect(result[:capabilities][:discovery]).to be true
      expect(result[:capabilities][:capability_negotiation]).to be true
    end
  end
end

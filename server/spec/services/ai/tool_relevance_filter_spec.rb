# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::ToolRelevanceFilter do
  def tool(name)
    { name: name, description: "Tool #{name}", parameters: { type: "object", properties: {} } }
  end

  let(:provisioning_tools) do
    %w[platform_provisioning_capture_brief platform_provisioning_compose_plan
       platform_provisioning_approve_plan system_node_create docker_create_container
       kubernetes_get_cluster].map { |n| tool(n) }
  end

  let(:devops_tools) do
    %w[dispatch_to_runner create_gitea_repository trigger_pipeline list_pipelines
       gitea_workflow_dispatch].map { |n| tool(n) }
  end

  let(:knowledge_tools) do
    %w[search_knowledge query_knowledge_base create_kb_article query_learnings
       reinforce_learning].map { |n| tool(n) }
  end

  let(:always_on_tools) do
    %w[request_confirmation get_notifications agent_introspect get_system_health
       search_knowledge query_learnings search_memory get_activity_feed
       dismiss_notification mark_all_notifications_read].map { |n| tool(n) }
  end

  let(:noise_tools) do
    %w[graph_statistics extract_to_knowledge_graph code_static_analysis
       team_optimize emit_signal create_proposal].map { |n| tool(n) }
  end

  describe ".filter" do
    it "returns the input unchanged when below the cap" do
      tools = provisioning_tools + devops_tools
      result = described_class.filter(tools, user_message: "anything", max_tools: 100)
      expect(result).to eq(tools)
    end

    it "narrows to provisioning tools for a provisioning intent message" do
      tools = always_on_tools + provisioning_tools + devops_tools + knowledge_tools + noise_tools
      result = described_class.filter(
        tools,
        user_message: "I want to provision a server in Mississippi",
        max_tools: 20
      )
      names = result.map { |t| t[:name] }
      # Always-on tools survive
      expect(names).to include("request_confirmation", "get_notifications")
      # Provisioning tools picked up
      expect(names).to include("platform_provisioning_capture_brief", "system_node_create", "docker_create_container")
      # Pure-noise non-provisioning tools dropped
      expect(names).not_to include("create_proposal", "team_optimize", "emit_signal")
    end

    it "picks up multiple intents when the message hits multiple keyword sets" do
      tools = always_on_tools + provisioning_tools + devops_tools + knowledge_tools
      result = described_class.filter(
        tools,
        user_message: "deploy a stack via gitea pipeline and search knowledge for the runtime",
        max_tools: 50
      )
      names = result.map { |t| t[:name] }
      expect(names).to include("platform_provisioning_capture_brief")  # provisioning intent
      expect(names).to include("dispatch_to_runner", "trigger_pipeline") # deploy intent
      expect(names).to include("query_learnings")                       # knowledge intent (via always-on)
    end

    it "falls back to always-on plus first slice when no intent is detected" do
      tools = always_on_tools + noise_tools + provisioning_tools
      result = described_class.filter(
        tools,
        user_message: "hi",
        max_tools: 12
      )
      names = result.map { |t| t[:name] }
      # Always-on guaranteed
      expect(names & always_on_tools.map { |t| t[:name] }).not_to be_empty
      # Hard truncated at max_tools
      expect(result.size).to be <= 12
    end

    it "truncates to max_tools when intent set is still over cap" do
      huge = (1..300).map { |i| tool("platform_provisioning_synthetic_#{i}") }
      result = described_class.filter(
        huge,
        user_message: "provision",
        max_tools: 50
      )
      expect(result.size).to eq(50)
    end
  end

  describe ".filter campaign intent" do
    it "surfaces campaign_* + dev-loop tools for a campaign/proposal-queue message" do
      campaign_tools = %w[campaign_list_proposals campaign_propose campaign_delegate
                          dev_next_task dev_list_tasks].map { |n| tool(n) }
      tools = always_on_tools + provisioning_tools + devops_tools + knowledge_tools + noise_tools + campaign_tools
      result = described_class.filter(
        tools, user_message: "what campaign proposals are in the discovery queue?", max_tools: 25
      )
      names = result.map { |t| t[:name] }
      expect(names).to include("campaign_list_proposals", "campaign_propose")
    end
  end

  describe ".detect_intents" do
    it "returns provision_infrastructure for provisioning keywords" do
      expect(described_class.detect_intents("I need to provision a server")).to include("provision_infrastructure")
    end

    it "returns deploy for pipeline keywords" do
      expect(described_class.detect_intents("trigger the gitea pipeline")).to include("deploy")
    end

    it "returns campaign for campaign / proposal-queue keywords" do
      expect(described_class.detect_intents("what campaign proposals are in the discovery queue?")).to include("campaign")
      expect(described_class.detect_intents("propose a new improvement campaign")).to include("campaign")
    end

    it "returns multiple intents when multiple keywords match" do
      intents = described_class.detect_intents("provision a node and deploy the workflow")
      expect(intents).to include("provision_infrastructure", "deploy")
    end

    it "returns empty for content with no keywords" do
      expect(described_class.detect_intents("hello")).to eq([])
    end

    it "is nil-safe" do
      expect(described_class.detect_intents(nil)).to eq([])
      expect(described_class.detect_intents("")).to eq([])
    end
  end
end

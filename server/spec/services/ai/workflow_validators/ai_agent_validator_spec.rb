# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::WorkflowValidators::AiAgentValidator do
  let(:account) { create(:account) }
  let(:workflow) { create(:ai_workflow, account: account) }

  def build_node(configuration: {}, timeout_seconds: 30, retry_count: 0)
    node = build(:ai_workflow_node, node_type: "data_processor", workflow: workflow)
    # Override node_type without triggering the after(:build) callback for ai_agent
    node.node_type = "ai_agent"
    node.configuration = configuration
    node.timeout_seconds = timeout_seconds
    node.retry_count = retry_count
    node
  end

  describe "#validate" do
    context "with valid configuration" do
      it "returns no errors for a complete configuration" do
        agent = create(:ai_agent, account: account)

        node = build_node(configuration: {
          "agent_id" => agent.id,
          "prompt" => "Analyze this data",
          "timeout_seconds" => 60
        })

        issues = described_class.new(node).validate

        errors = issues.select { |i| i[:severity] == "error" }
        expect(errors).to be_empty
      end

      it "accepts system_prompt instead of prompt" do
        agent = create(:ai_agent, account: account)

        node = build_node(configuration: {
          "agent_id" => agent.id,
          "system_prompt" => "You are a helpful assistant",
          "timeout_seconds" => 60
        })

        issues = described_class.new(node).validate

        prompt_issues = issues.select { |i| i[:code] == "missing_prompt" }
        expect(prompt_issues).to be_empty
      end

      it "accepts both prompt and system_prompt" do
        agent = create(:ai_agent, account: account)

        node = build_node(configuration: {
          "agent_id" => agent.id,
          "prompt" => "Analyze this",
          "system_prompt" => "You are a helpful assistant",
          "timeout_seconds" => 60
        })

        issues = described_class.new(node).validate

        errors = issues.select { |i| i[:severity] == "error" }
        expect(errors).to be_empty
      end
    end

    context "with missing agent_id" do
      it "adds missing_agent_id error" do
        node = build_node(configuration: {
          "prompt" => "Test prompt"
        })

        issues = described_class.new(node).validate

        expect(issues).to include(
          hash_including(code: "missing_agent_id", severity: "error")
        )
      end
    end

    context "when referenced agent does not exist" do
      it "adds agent_not_found error" do
        node = build_node(configuration: {
          "agent_id" => SecureRandom.uuid,
          "prompt" => "Test prompt"
        })

        issues = described_class.new(node).validate

        expect(issues).to include(
          hash_including(code: "agent_not_found", severity: "error")
        )
      end
    end

    context "when referenced agent exists" do
      it "does not add agent_not_found error" do
        agent = create(:ai_agent, account: account)

        node = build_node(configuration: {
          "agent_id" => agent.id,
          "prompt" => "Test prompt",
          "timeout_seconds" => 60
        })

        issues = described_class.new(node).validate

        codes = issues.map { |i| i[:code] }
        expect(codes).not_to include("agent_not_found")
      end
    end

    context "when both prompt and system_prompt are missing" do
      it "adds missing_prompt warning" do
        agent = create(:ai_agent, account: account)

        node = build_node(configuration: {
          "agent_id" => agent.id
        })

        issues = described_class.new(node).validate

        expect(issues).to include(
          hash_including(code: "missing_prompt", severity: "warning")
        )
      end
    end

    context "with timeout validation" do
      it "inherits timeout validation from base" do
        agent = create(:ai_agent, account: account)

        node = build_node(configuration: {
          "agent_id" => agent.id,
          "prompt" => "Test",
          "timeout_seconds" => 900
        })

        issues = described_class.new(node).validate

        expect(issues).to include(
          hash_including(code: "timeout_too_long", severity: "warning")
        )
      end
    end

    context "with retry config validation" do
      it "inherits retry validation from base" do
        agent = create(:ai_agent, account: account)

        node = build_node(configuration: {
          "agent_id" => agent.id,
          "prompt" => "Test",
          "retry_count" => 15,
          "timeout_seconds" => 60
        })

        issues = described_class.new(node).validate

        expect(issues).to include(
          hash_including(code: "excessive_retries", severity: "warning")
        )
      end
    end

    context "with blank configuration" do
      it "adds missing_configuration warning" do
        node = build_node(configuration: {})

        issues = described_class.new(node).validate

        expect(issues).to include(
          hash_including(code: "missing_configuration", severity: "warning")
        )
      end
    end
  end
end

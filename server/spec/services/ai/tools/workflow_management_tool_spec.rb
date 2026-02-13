# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Tools::WorkflowManagementTool do
  let(:account) { create(:account) }
  let(:tool) { described_class.new(account: account) }

  describe ".definition" do
    it "returns a valid tool definition" do
      defn = described_class.definition
      expect(defn[:name]).to eq("workflow_management")
      expect(defn[:description]).to be_present
      expect(defn[:parameters]).to include(:action, :workflow_id, :name, :description, :input)
    end

    it "marks action as required" do
      expect(described_class.definition[:parameters][:action][:required]).to be true
    end
  end

  describe ".permitted?" do
    it "requires ai.workflows.execute permission" do
      expect(described_class::REQUIRED_PERMISSION).to eq("ai.workflows.execute")
    end
  end

  describe "#execute" do
    context "with create_workflow action" do
      it "creates a workflow for the account" do
        result = tool.execute(params: { action: "create_workflow", name: "Deploy Pipeline", description: "Auto deploy" })
        expect(result[:success]).to be true
        expect(result[:workflow_id]).to be_present
        expect(result[:name]).to eq("Deploy Pipeline")
      end

      it "generates slug from name" do
        result = tool.execute(params: { action: "create_workflow", name: "My Great Workflow" })
        workflow = Ai::Workflow.find(result[:workflow_id])
        expect(workflow.slug).to eq("my-great-workflow")
      end

      it "sets default version and status" do
        result = tool.execute(params: { action: "create_workflow", name: "Test Flow" })
        workflow = Ai::Workflow.find(result[:workflow_id])
        expect(workflow.version).to eq("1.0.0")
        expect(workflow.status).to eq("active")
      end

      it "returns error on invalid record" do
        result = tool.execute(params: { action: "create_workflow", name: nil })
        expect(result[:success]).to be false
        expect(result[:error]).to be_present
      end
    end

    context "with execute_workflow action" do
      it "queues workflow execution" do
        workflow = create(:ai_workflow, :active, account: account)
        result = tool.execute(params: { action: "execute_workflow", workflow_id: workflow.id })
        expect(result[:success]).to be true
        expect(result[:status]).to eq("execution_queued")
      end

      it "returns error for non-existent workflow" do
        result = tool.execute(params: { action: "execute_workflow", workflow_id: SecureRandom.uuid })
        expect(result[:success]).to be false
        expect(result[:error]).to match(/not found/i)
      end
    end

    context "with list_workflows action" do
      it "returns active workflows for the account" do
        create(:ai_workflow, :active, account: account)
        create(:ai_workflow, :active, account: account)
        create(:ai_workflow, :archived, account: account)

        result = tool.execute(params: { action: "list_workflows" })
        expect(result[:success]).to be true
        expect(result[:workflows].size).to eq(2)
        expect(result[:workflows].first).to include(:id, :name, :status)
      end

      it "does not return workflows from other accounts" do
        other_account = create(:account)
        create(:ai_workflow, :active, account: other_account)
        create(:ai_workflow, :active, account: account)

        result = tool.execute(params: { action: "list_workflows" })
        expect(result[:workflows].size).to eq(1)
      end
    end

    context "with unknown action" do
      it "returns error" do
        result = tool.execute(params: { action: "obliterate" })
        expect(result[:success]).to be false
        expect(result[:error]).to match(/Unknown action/)
      end
    end

    context "parameter validation" do
      it "raises ArgumentError when action is missing" do
        expect { tool.execute(params: {}) }.to raise_error(ArgumentError, /Missing required parameters: action/)
      end
    end
  end
end

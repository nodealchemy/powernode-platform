# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::WorkflowValidators::SubWorkflowValidator do
  let(:account) { create(:account) }
  let(:user) { create(:user, :owner, account: account) }
  let(:workflow) { create(:ai_workflow, account: account, creator: user) }

  def build_node(configuration: {}, timeout_seconds: 30)
    node = build(:ai_workflow_node, node_type: "sub_workflow", workflow: workflow)
    node.configuration = configuration
    node.timeout_seconds = timeout_seconds
    node
  end

  describe "#validate" do
    context "with valid configuration" do
      it "returns no errors for properly configured sub-workflow" do
        sub_workflow = create(:ai_workflow, account: account, creator: user)

        node = build_node(configuration: {
          "workflow_id" => sub_workflow.id,
          "input_mapping" => { "parent.data" => "child.input" },
          "timeout_seconds" => 60
        })

        issues = described_class.new(node).validate

        errors = issues.select { |i| i[:severity] == "error" }
        expect(errors).to be_empty
      end
    end

    context "with missing workflow_id" do
      it "adds missing_workflow_id error" do
        node = build_node(configuration: { "other" => "value" })

        issues = described_class.new(node).validate

        expect(issues).to include(
          hash_including(code: "missing_workflow_id", severity: "error")
        )
      end
    end

    context "when referenced workflow does not exist" do
      it "adds workflow_not_found error" do
        node = build_node(configuration: {
          "workflow_id" => SecureRandom.uuid
        })

        issues = described_class.new(node).validate

        expect(issues).to include(
          hash_including(code: "workflow_not_found", severity: "error")
        )
      end
    end

    context "when workflow references itself (circular)" do
      it "adds circular_workflow_reference error" do
        node = build_node(configuration: {
          "workflow_id" => workflow.id
        })

        issues = described_class.new(node).validate

        expect(issues).to include(
          hash_including(code: "circular_workflow_reference", severity: "error")
        )
      end
    end

    context "when referencing a different valid workflow" do
      it "does not add circular_workflow_reference error" do
        other_workflow = create(:ai_workflow, account: account, creator: user)

        node = build_node(configuration: {
          "workflow_id" => other_workflow.id,
          "timeout_seconds" => 60
        })

        issues = described_class.new(node).validate

        codes = issues.map { |i| i[:code] }
        expect(codes).not_to include("circular_workflow_reference")
        expect(codes).not_to include("workflow_not_found")
      end
    end

    context "with missing input_mapping" do
      it "adds missing_input_mapping info" do
        sub_workflow = create(:ai_workflow, account: account, creator: user)

        node = build_node(configuration: {
          "workflow_id" => sub_workflow.id,
          "timeout_seconds" => 60
        })

        issues = described_class.new(node).validate

        expect(issues).to include(
          hash_including(
            code: "missing_input_mapping",
            severity: "info",
            category: "configuration"
          )
        )
      end
    end

    context "when input_mapping is present" do
      it "does not add missing_input_mapping info" do
        sub_workflow = create(:ai_workflow, account: account, creator: user)

        node = build_node(configuration: {
          "workflow_id" => sub_workflow.id,
          "input_mapping" => { "parent.data" => "child.input" },
          "timeout_seconds" => 60
        })

        issues = described_class.new(node).validate

        codes = issues.map { |i| i[:code] }
        expect(codes).not_to include("missing_input_mapping")
      end
    end

    context "with timeout validation" do
      it "inherits timeout validation from base" do
        sub_workflow = create(:ai_workflow, account: account, creator: user)

        node = build_node(configuration: {
          "workflow_id" => sub_workflow.id,
          "input_mapping" => { "a" => "b" },
          "timeout_seconds" => 900
        })

        issues = described_class.new(node).validate

        expect(issues).to include(
          hash_including(code: "timeout_too_long", severity: "warning")
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

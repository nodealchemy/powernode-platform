# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::WorkflowValidators::HumanApprovalValidator do
  let(:account) { create(:account) }
  let(:workflow) { create(:ai_workflow, account: account) }

  def build_node(configuration: {})
    node = build(:ai_workflow_node, node_type: "human_approval", workflow: workflow)
    node.configuration = configuration
    node
  end

  describe "#validate" do
    context "with valid configuration" do
      it "returns no errors for properly configured approval" do
        node = build_node(configuration: {
          "approvers" => ["user1@example.com", "user2@example.com"],
          "min_approvals" => 1,
          "approval_timeout_seconds" => 86_400
        })

        issues = described_class.new(node).validate

        errors = issues.select { |i| i[:severity] == "error" }
        expect(errors).to be_empty
      end
    end

    context "with missing approvers field" do
      it "adds missing_approvers error" do
        node = build_node(configuration: { "other" => "value" })

        issues = described_class.new(node).validate

        expect(issues).to include(
          hash_including(code: "missing_approvers", severity: "error")
        )
      end
    end

    context "when approvers is not an array" do
      it "adds approvers_not_array error for string" do
        node = build_node(configuration: {
          "approvers" => "user@example.com"
        })

        issues = described_class.new(node).validate

        expect(issues).to include(
          hash_including(code: "approvers_not_array", severity: "error")
        )
      end

      it "adds approvers_not_array error for hash" do
        node = build_node(configuration: {
          "approvers" => { "email" => "user@example.com" }
        })

        issues = described_class.new(node).validate

        expect(issues).to include(
          hash_including(code: "approvers_not_array", severity: "error")
        )
      end
    end

    context "when approvers array is empty" do
      it "treats empty array as blank and skips further validation" do
        node = build_node(configuration: { "approvers" => [] })

        issues = described_class.new(node).validate

        # Empty arrays are blank? in Rails, so the validator returns early
        approver_errors = issues.select { |i| i[:code] =~ /approver/ }
        expect(approver_errors).to be_empty
      end
    end

    context "when min_approvals exceeds approver count" do
      it "adds min_approvals_exceeds_approvers error" do
        node = build_node(configuration: {
          "approvers" => ["user1@example.com"],
          "min_approvals" => 3
        })

        issues = described_class.new(node).validate

        expect(issues).to include(
          hash_including(
            code: "min_approvals_exceeds_approvers",
            severity: "error",
            message: /3.*1/
          )
        )
      end

      it "does not add error when min_approvals equals approver count" do
        node = build_node(configuration: {
          "approvers" => ["user1@example.com", "user2@example.com"],
          "min_approvals" => 2
        })

        issues = described_class.new(node).validate

        codes = issues.map { |i| i[:code] }
        expect(codes).not_to include("min_approvals_exceeds_approvers")
      end

      it "does not add error when min_approvals is less than approver count" do
        node = build_node(configuration: {
          "approvers" => ["user1@example.com", "user2@example.com", "user3@example.com"],
          "min_approvals" => 2
        })

        issues = described_class.new(node).validate

        codes = issues.map { |i| i[:code] }
        expect(codes).not_to include("min_approvals_exceeds_approvers")
      end
    end

    context "when approval timeout is missing" do
      it "adds missing_approval_timeout warning" do
        node = build_node(configuration: {
          "approvers" => ["user1@example.com"]
        })

        issues = described_class.new(node).validate

        expect(issues).to include(
          hash_including(
            code: "missing_approval_timeout",
            severity: "warning",
            auto_fixable: true
          )
        )
      end

      it "includes recommended timeout in metadata" do
        node = build_node(configuration: {
          "approvers" => ["user1@example.com"]
        })

        issues = described_class.new(node).validate

        timeout_issue = issues.find { |i| i[:code] == "missing_approval_timeout" }
        expect(timeout_issue[:metadata]).to eq({ recommended_timeout: 86_400 })
      end
    end

    context "when approval timeout is present" do
      it "does not add missing_approval_timeout warning" do
        node = build_node(configuration: {
          "approvers" => ["user1@example.com"],
          "approval_timeout_seconds" => 3600
        })

        issues = described_class.new(node).validate

        codes = issues.map { |i| i[:code] }
        expect(codes).not_to include("missing_approval_timeout")
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

    context "when min_approvals or approvers is blank" do
      it "does not validate approval criteria" do
        node = build_node(configuration: {
          "approvers" => ["user1@example.com"]
        })

        issues = described_class.new(node).validate

        codes = issues.map { |i| i[:code] }
        expect(codes).not_to include("min_approvals_exceeds_approvers")
      end
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::WorkflowValidators::DelayValidator do
  let(:account) { create(:account) }
  let(:workflow) { create(:ai_workflow, account: account) }

  def build_node(configuration: {})
    node = build(:ai_workflow_node, node_type: "delay", workflow: workflow)
    node.configuration = configuration
    node
  end

  describe "#validate" do
    context "with valid configuration" do
      it "returns no errors for valid delay_seconds" do
        node = build_node(configuration: { "delay_seconds" => 60 })

        issues = described_class.new(node).validate

        errors = issues.select { |i| i[:severity] == "error" }
        expect(errors).to be_empty
      end

      it "returns no errors for delay_expression" do
        node = build_node(configuration: { "delay_expression" => "input.wait_time" })

        issues = described_class.new(node).validate

        errors = issues.select { |i| i[:severity] == "error" }
        expect(errors).to be_empty
      end

      it "returns no errors when both delay_seconds and delay_expression are present" do
        node = build_node(configuration: {
          "delay_seconds" => 30,
          "delay_expression" => "input.wait_time"
        })

        issues = described_class.new(node).validate

        errors = issues.select { |i| i[:severity] == "error" }
        expect(errors).to be_empty
      end
    end

    context "when no delay is configured" do
      it "adds missing_delay error when both are blank" do
        node = build_node(configuration: { "other" => "value" })

        issues = described_class.new(node).validate

        expect(issues).to include(
          hash_including(code: "missing_delay", severity: "error")
        )
      end
    end

    context "when delay_seconds is invalid" do
      it "adds invalid_delay error for zero" do
        node = build_node(configuration: { "delay_seconds" => 0 })

        issues = described_class.new(node).validate

        expect(issues).to include(
          hash_including(code: "invalid_delay", severity: "error")
        )
      end

      it "adds invalid_delay error for negative values" do
        node = build_node(configuration: { "delay_seconds" => -10 })

        issues = described_class.new(node).validate

        expect(issues).to include(
          hash_including(code: "invalid_delay", severity: "error")
        )
      end
    end

    context "when delay is excessive" do
      it "adds excessive_delay warning for values over 1 day" do
        node = build_node(configuration: { "delay_seconds" => 100_000 })

        issues = described_class.new(node).validate

        expect(issues).to include(
          hash_including(
            code: "excessive_delay",
            severity: "warning",
            category: "performance"
          )
        )
      end

      it "does not warn at exactly 1 day (86400s)" do
        node = build_node(configuration: { "delay_seconds" => 86_400 })

        issues = described_class.new(node).validate

        codes = issues.map { |i| i[:code] }
        expect(codes).not_to include("excessive_delay")
      end

      it "warns above 1 day" do
        node = build_node(configuration: { "delay_seconds" => 86_401 })

        issues = described_class.new(node).validate

        expect(issues).to include(
          hash_including(code: "excessive_delay")
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

    context "with boundary values" do
      it "accepts delay of 1 second" do
        node = build_node(configuration: { "delay_seconds" => 1 })

        issues = described_class.new(node).validate

        delay_errors = issues.select { |i| i[:code] == "invalid_delay" }
        expect(delay_errors).to be_empty
      end

      it "accepts delay of exactly 86400 seconds (1 day)" do
        node = build_node(configuration: { "delay_seconds" => 86_400 })

        issues = described_class.new(node).validate

        delay_issues = issues.select { |i| i[:code] =~ /invalid_delay|excessive_delay/ }
        expect(delay_issues).to be_empty
      end
    end
  end
end

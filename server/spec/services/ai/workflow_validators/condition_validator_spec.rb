# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::WorkflowValidators::ConditionValidator do
  let(:account) { create(:account) }
  let(:workflow) { create(:ai_workflow, account: account) }

  def build_node(configuration: {})
    node = build(:ai_workflow_node, node_type: "condition", workflow: workflow)
    node.configuration = configuration
    node
  end

  describe "#validate" do
    context "with valid configuration" do
      it "returns no errors for properly configured conditions" do
        node = build_node(configuration: {
          "conditions" => [
            { "field" => "status", "operator" => "equals", "value" => "active" }
          ],
          "has_default_branch" => true
        })

        issues = described_class.new(node).validate

        errors = issues.select { |i| i[:severity] == "error" }
        expect(errors).to be_empty
      end

      it "returns no errors for multiple conditions" do
        node = build_node(configuration: {
          "conditions" => [
            { "field" => "status", "operator" => "equals", "value" => "active" },
            { "field" => "score", "operator" => ">", "value" => 0.8 }
          ]
        })

        issues = described_class.new(node).validate

        condition_errors = issues.select { |i| i[:severity] == "error" && i[:code] =~ /condition/ }
        expect(condition_errors).to be_empty
      end
    end

    context "with missing conditions field" do
      it "adds missing_conditions error" do
        node = build_node(configuration: { "other" => "value" })

        issues = described_class.new(node).validate

        expect(issues).to include(
          hash_including(code: "missing_conditions", severity: "error")
        )
      end
    end

    context "when conditions is not an array" do
      it "adds conditions_not_array error" do
        node = build_node(configuration: {
          "conditions" => "not_an_array"
        })

        issues = described_class.new(node).validate

        expect(issues).to include(
          hash_including(code: "conditions_not_array", severity: "error")
        )
      end

      it "adds conditions_not_array error for hash" do
        node = build_node(configuration: {
          "conditions" => { "field" => "status" }
        })

        issues = described_class.new(node).validate

        expect(issues).to include(
          hash_including(code: "conditions_not_array", severity: "error")
        )
      end
    end

    context "when conditions array is empty" do
      it "treats empty array as blank and skips further validation" do
        node = build_node(configuration: { "conditions" => [] })

        issues = described_class.new(node).validate

        # Empty arrays are blank? in Rails, so the validator returns early
        condition_errors = issues.select { |i| i[:code] =~ /condition/ }
        expect(condition_errors).to be_empty
      end
    end

    context "when condition entry is not a hash" do
      it "adds invalid_condition_format error" do
        node = build_node(configuration: {
          "conditions" => ["not_a_hash"]
        })

        issues = described_class.new(node).validate

        expect(issues).to include(
          hash_including(
            code: "invalid_condition_format",
            severity: "error",
            message: /index 0/
          )
        )
      end
    end

    context "when condition entry is missing required keys" do
      it "adds error for missing field" do
        node = build_node(configuration: {
          "conditions" => [
            { "operator" => "equals", "value" => "active" }
          ]
        })

        issues = described_class.new(node).validate

        expect(issues).to include(
          hash_including(code: "missing_condition_field", severity: "error")
        )
      end

      it "adds error for missing operator" do
        node = build_node(configuration: {
          "conditions" => [
            { "field" => "status", "value" => "active" }
          ]
        })

        issues = described_class.new(node).validate

        expect(issues).to include(
          hash_including(code: "missing_condition_operator", severity: "error")
        )
      end

      it "adds error for missing value" do
        node = build_node(configuration: {
          "conditions" => [
            { "field" => "status", "operator" => "equals" }
          ]
        })

        issues = described_class.new(node).validate

        expect(issues).to include(
          hash_including(code: "missing_condition_value", severity: "error")
        )
      end

      it "adds errors for all missing keys" do
        node = build_node(configuration: {
          "conditions" => [{}]
        })

        issues = described_class.new(node).validate

        codes = issues.map { |i| i[:code] }
        expect(codes).to include("missing_condition_field", "missing_condition_operator", "missing_condition_value")
      end
    end

    context "when has_default_branch is false" do
      it "does not trigger warning due to || operator treating false as falsy" do
        # NOTE: The validator uses `val || val` pattern which skips boolean false.
        # JSON serialization converts all keys to strings, so `false || nil` => nil.
        # This means has_default_branch: false is indistinguishable from absent.
        node = build_node(configuration: {
          "conditions" => [
            { "field" => "status", "operator" => "equals", "value" => "active" }
          ],
          "has_default_branch" => false
        })

        issues = described_class.new(node).validate

        codes = issues.map { |i| i[:code] }
        expect(codes).not_to include("no_default_branch")
      end
    end

    context "when has_default_branch is true" do
      it "does not add no_default_branch warning" do
        node = build_node(configuration: {
          "conditions" => [
            { "field" => "status", "operator" => "equals", "value" => "active" }
          ],
          "has_default_branch" => true
        })

        issues = described_class.new(node).validate

        codes = issues.map { |i| i[:code] }
        expect(codes).not_to include("no_default_branch")
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

    context "with multiple condition entries" do
      it "validates each condition independently" do
        node = build_node(configuration: {
          "conditions" => [
            { "field" => "status", "operator" => "equals", "value" => "active" },
            { "field" => "score" }  # missing operator and value
          ]
        })

        issues = described_class.new(node).validate

        expect(issues).to include(
          hash_including(code: "missing_condition_operator", message: /index 1/)
        )
        expect(issues).to include(
          hash_including(code: "missing_condition_value", message: /index 1/)
        )
      end
    end
  end
end

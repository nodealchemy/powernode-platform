# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::WorkflowValidators::TransformValidator do
  let(:account) { create(:account) }
  let(:workflow) { create(:ai_workflow, account: account) }

  def build_node(configuration: {})
    node = build(:ai_workflow_node, node_type: "transform", workflow: workflow)
    node.configuration = configuration
    node
  end

  describe "#validate" do
    context "with valid configuration" do
      it "returns no errors for properly configured transformations" do
        node = build_node(configuration: {
          "transformations" => [
            { "type" => "map", "config" => { "field" => "name" } }
          ]
        })

        issues = described_class.new(node).validate

        errors = issues.select { |i| i[:severity] == "error" }
        expect(errors).to be_empty
      end

      it "accepts all valid transformation types" do
        %w[map filter reduce format merge extract].each do |type|
          node = build_node(configuration: {
            "transformations" => [{ "type" => type }]
          })

          issues = described_class.new(node).validate

          type_issues = issues.select { |i| i[:code] == "invalid_transformation_type" }
          expect(type_issues).to be_empty, "Expected type '#{type}' to be valid"
        end
      end
    end

    context "with missing transformations field" do
      it "adds missing_transformations error" do
        node = build_node(configuration: { "other" => "value" })

        issues = described_class.new(node).validate

        expect(issues).to include(
          hash_including(code: "missing_transformations", severity: "error")
        )
      end
    end

    context "when transformations is not an array" do
      it "adds transformations_not_array error for string" do
        node = build_node(configuration: {
          "transformations" => "not_an_array"
        })

        issues = described_class.new(node).validate

        expect(issues).to include(
          hash_including(code: "transformations_not_array", severity: "error")
        )
      end

      it "adds transformations_not_array error for hash" do
        node = build_node(configuration: {
          "transformations" => { "type" => "map" }
        })

        issues = described_class.new(node).validate

        expect(issues).to include(
          hash_including(code: "transformations_not_array", severity: "error")
        )
      end
    end

    context "when transformations array is empty" do
      it "treats empty array as blank and skips further validation" do
        node = build_node(configuration: { "transformations" => [] })

        issues = described_class.new(node).validate

        # Empty arrays are blank? in Rails, so the validator returns early
        transform_errors = issues.select { |i| i[:code] =~ /transformation/ }
        expect(transform_errors).to be_empty
      end
    end

    context "when transformation entry is not a hash" do
      it "adds invalid_transformation_format error" do
        node = build_node(configuration: {
          "transformations" => ["not_a_hash"]
        })

        issues = described_class.new(node).validate

        expect(issues).to include(
          hash_including(
            code: "invalid_transformation_format",
            severity: "error",
            message: /index 0/
          )
        )
      end
    end

    context "when transformation entry is missing type" do
      it "adds missing_transformation_type error" do
        node = build_node(configuration: {
          "transformations" => [
            { "config" => { "field" => "name" } }
          ]
        })

        issues = described_class.new(node).validate

        expect(issues).to include(
          hash_including(
            code: "missing_transformation_type",
            severity: "error",
            message: /index 0/
          )
        )
      end
    end

    context "when transformation has invalid type" do
      it "adds invalid_transformation_type warning" do
        node = build_node(configuration: {
          "transformations" => [
            { "type" => "unknown_type" }
          ]
        })

        issues = described_class.new(node).validate

        expect(issues).to include(
          hash_including(
            code: "invalid_transformation_type",
            severity: "warning",
            message: /unknown_type/
          )
        )
      end
    end

    context "with multiple transformation entries" do
      it "validates each transformation independently" do
        node = build_node(configuration: {
          "transformations" => [
            { "type" => "map" },
            "invalid_entry",
            { "config" => "no_type" }
          ]
        })

        issues = described_class.new(node).validate

        expect(issues).to include(
          hash_including(code: "invalid_transformation_format", message: /index 1/)
        )
        expect(issues).to include(
          hash_including(code: "missing_transformation_type", message: /index 2/)
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

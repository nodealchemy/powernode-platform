# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::WorkflowValidators::LoopValidator do
  let(:account) { create(:account) }
  let(:workflow) { create(:ai_workflow, account: account) }

  def build_node(configuration: {}, timeout_seconds: 30)
    node = build(:ai_workflow_node, node_type: "loop", workflow: workflow)
    node.configuration = configuration
    node.timeout_seconds = timeout_seconds
    node
  end

  describe "#validate" do
    context "with valid configuration" do
      it "returns no errors for properly configured loop" do
        node = build_node(configuration: {
          "iteration_source" => "array",
          "max_iterations" => 100,
          "timeout_seconds" => 30
        })

        issues = described_class.new(node).validate

        errors = issues.select { |i| i[:severity] == "error" }
        expect(errors).to be_empty
      end

      it "accepts all valid iteration source types" do
        %w[array range count variable].each do |source|
          node = build_node(configuration: {
            "iteration_source" => source,
            "max_iterations" => 100,
            "timeout_seconds" => 30
          })

          issues = described_class.new(node).validate

          source_errors = issues.select { |i| i[:code] == "invalid_iteration_source_value" }
          expect(source_errors).to be_empty, "Expected iteration_source '#{source}' to be valid"
        end
      end
    end

    context "with missing iteration_source" do
      it "adds missing_iteration_source error" do
        node = build_node(configuration: {
          "max_iterations" => 100
        })

        issues = described_class.new(node).validate

        expect(issues).to include(
          hash_including(code: "missing_iteration_source", severity: "error")
        )
      end
    end

    context "with invalid iteration_source" do
      it "adds invalid_iteration_source_value error" do
        node = build_node(configuration: {
          "iteration_source" => "invalid_source",
          "max_iterations" => 100
        })

        issues = described_class.new(node).validate

        expect(issues).to include(
          hash_including(code: "invalid_iteration_source_value", severity: "error")
        )
      end
    end

    context "with missing max_iterations" do
      it "adds missing_max_iterations warning" do
        node = build_node(configuration: {
          "iteration_source" => "array",
          "timeout_seconds" => 30
        })

        issues = described_class.new(node).validate

        expect(issues).to include(
          hash_including(
            code: "missing_max_iterations",
            severity: "warning",
            auto_fixable: true
          )
        )
      end

      it "includes recommended value in metadata" do
        node = build_node(configuration: {
          "iteration_source" => "array",
          "timeout_seconds" => 30
        })

        issues = described_class.new(node).validate

        issue = issues.find { |i| i[:code] == "missing_max_iterations" }
        expect(issue[:metadata]).to eq({ recommended_max_iterations: 1000 })
      end
    end

    context "with invalid max_iterations" do
      it "adds invalid_max_iterations error for zero" do
        node = build_node(configuration: {
          "iteration_source" => "array",
          "max_iterations" => 0
        })

        issues = described_class.new(node).validate

        expect(issues).to include(
          hash_including(code: "invalid_max_iterations", severity: "error")
        )
      end

      it "adds invalid_max_iterations error for negative values" do
        node = build_node(configuration: {
          "iteration_source" => "array",
          "max_iterations" => -5
        })

        issues = described_class.new(node).validate

        expect(issues).to include(
          hash_including(code: "invalid_max_iterations", severity: "error")
        )
      end
    end

    context "with excessive max_iterations" do
      it "adds excessive_max_iterations warning for values over 10000" do
        node = build_node(configuration: {
          "iteration_source" => "array",
          "max_iterations" => 50_000
        })

        issues = described_class.new(node).validate

        expect(issues).to include(
          hash_including(
            code: "excessive_max_iterations",
            severity: "warning",
            category: "performance"
          )
        )
      end

      it "does not warn at exactly 10000" do
        node = build_node(configuration: {
          "iteration_source" => "array",
          "max_iterations" => 10_000,
          "timeout_seconds" => 30
        })

        issues = described_class.new(node).validate

        codes = issues.map { |i| i[:code] }
        expect(codes).not_to include("excessive_max_iterations")
      end
    end

    context "with timeout validation" do
      it "inherits timeout validation from base" do
        node = build_node(configuration: {
          "iteration_source" => "array",
          "max_iterations" => 100,
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

    context "with boundary values for max_iterations" do
      it "accepts max_iterations of 1" do
        node = build_node(configuration: {
          "iteration_source" => "array",
          "max_iterations" => 1,
          "timeout_seconds" => 30
        })

        issues = described_class.new(node).validate

        iteration_errors = issues.select { |i| i[:code] =~ /invalid_max_iterations|excessive_max_iterations/ }
        expect(iteration_errors).to be_empty
      end
    end
  end
end

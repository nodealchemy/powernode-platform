# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::WorkflowValidators::BaseValidator do
  let(:account) { create(:account) }
  let(:workflow) { create(:ai_workflow, account: account) }

  def build_node(configuration: {}, timeout_seconds: 30, retry_count: 0)
    node = build(:ai_workflow_node, node_type: "data_processor", workflow: workflow)
    node.configuration = configuration
    node.timeout_seconds = timeout_seconds
    node.retry_count = retry_count
    node
  end

  describe "#validate" do
    it "returns an array of issues" do
      node = build_node(configuration: { "operation" => "test" })
      issues = described_class.new(node).validate

      expect(issues).to be_an(Array)
    end

    context "when configuration is blank" do
      it "adds missing_configuration warning" do
        node = build_node(configuration: {})
        issues = described_class.new(node).validate

        expect(issues).to include(
          hash_including(
            code: "missing_configuration",
            severity: "warning",
            category: "configuration"
          )
        )
      end
    end

    context "when configuration is present" do
      it "does not add missing_configuration warning" do
        node = build_node(configuration: { "key" => "value" })
        issues = described_class.new(node).validate

        codes = issues.map { |i| i[:code] }
        expect(codes).not_to include("missing_configuration")
      end
    end
  end

  describe "#validate_required_fields" do
    it "adds error for each missing required field" do
      node = build_node(configuration: { "name" => "test" })
      validator = described_class.new(node)

      validator.send(:validate_required_fields, :name, :url, :method)

      expect(validator.issues).to include(
        hash_including(code: "missing_url", severity: "error")
      )
      expect(validator.issues).to include(
        hash_including(code: "missing_method", severity: "error")
      )
    end

    it "does not add errors for present fields" do
      node = build_node(configuration: { "url" => "https://example.com", "method" => "GET" })
      validator = described_class.new(node)

      validator.send(:validate_required_fields, :url, :method)

      expect(validator.issues).to be_empty
    end

    it "skips validation when configuration is blank" do
      node = build_node(configuration: {})
      validator = described_class.new(node)

      validator.send(:validate_required_fields, :url)

      codes = validator.issues.map { |i| i[:code] }
      expect(codes).not_to include("missing_url")
    end

    it "accepts symbol keys in configuration" do
      node = build_node(configuration: { url: "https://example.com" })
      validator = described_class.new(node)

      validator.send(:validate_required_fields, :url)

      expect(validator.issues).to be_empty
    end
  end

  describe "#validate_field_type" do
    it "adds error when field type does not match" do
      node = build_node(configuration: { "count" => "not_a_number" })
      validator = described_class.new(node)

      validator.send(:validate_field_type, :count, Integer)

      expect(validator.issues).to include(
        hash_including(code: "invalid_count_type", severity: "error")
      )
    end

    it "does not add error when field type matches" do
      node = build_node(configuration: { "count" => 42 })
      validator = described_class.new(node)

      validator.send(:validate_field_type, :count, Integer)

      expect(validator.issues).to be_empty
    end

    it "skips validation when field is nil" do
      node = build_node(configuration: { "other" => "value" })
      validator = described_class.new(node)

      validator.send(:validate_field_type, :count, Integer)

      expect(validator.issues).to be_empty
    end
  end

  describe "#validate_field_not_blank" do
    it "adds warning when field is blank" do
      node = build_node(configuration: { "name" => "" })
      validator = described_class.new(node)

      validator.send(:validate_field_not_blank, :name)

      expect(validator.issues).to include(
        hash_including(code: "blank_name", severity: "warning")
      )
    end

    it "does not add warning when field has value" do
      node = build_node(configuration: { "name" => "test" })
      validator = described_class.new(node)

      validator.send(:validate_field_not_blank, :name)

      expect(validator.issues).to be_empty
    end
  end

  describe "#validate_field_options" do
    it "adds error when field value is not in valid options" do
      node = build_node(configuration: { "method" => "INVALID" })
      validator = described_class.new(node)

      validator.send(:validate_field_options, :method, %w[GET POST PUT])

      expect(validator.issues).to include(
        hash_including(code: "invalid_method_value", severity: "error")
      )
    end

    it "does not add error when field value is valid" do
      node = build_node(configuration: { "method" => "GET" })
      validator = described_class.new(node)

      validator.send(:validate_field_options, :method, %w[GET POST PUT])

      expect(validator.issues).to be_empty
    end

    it "skips validation when field is nil" do
      node = build_node(configuration: { "other" => "value" })
      validator = described_class.new(node)

      validator.send(:validate_field_options, :method, %w[GET POST PUT])

      expect(validator.issues).to be_empty
    end
  end

  describe "#validate_timeout" do
    it "adds info when timeout is missing" do
      node = build_node(configuration: { "key" => "value" }, timeout_seconds: nil)
      # Override timeout_seconds to nil via configuration
      node.configuration.delete("timeout_seconds")
      validator = described_class.new(node)

      validator.send(:validate_timeout)

      expect(validator.issues).to include(
        hash_including(
          code: "missing_timeout",
          severity: "info",
          category: "performance",
          auto_fixable: true
        )
      )
    end

    it "adds warning when timeout is too long (>600s)" do
      node = build_node(configuration: { "timeout_seconds" => 900 })
      validator = described_class.new(node)

      validator.send(:validate_timeout)

      expect(validator.issues).to include(
        hash_including(code: "timeout_too_long", severity: "warning")
      )
    end

    it "adds warning when timeout is too short (<5s)" do
      node = build_node(configuration: { "timeout_seconds" => 2 })
      validator = described_class.new(node)

      validator.send(:validate_timeout)

      expect(validator.issues).to include(
        hash_including(code: "timeout_too_short", severity: "warning")
      )
    end

    it "does not add issues for reasonable timeout" do
      node = build_node(configuration: { "timeout_seconds" => 30 })
      validator = described_class.new(node)

      validator.send(:validate_timeout)

      timeout_issues = validator.issues.select { |i| i[:code] =~ /timeout/ }
      expect(timeout_issues).to be_empty
    end
  end

  describe "#validate_retry_config" do
    it "adds warning when retry count is excessive (>10)" do
      node = build_node(configuration: { "retry_count" => 15 })
      validator = described_class.new(node)

      validator.send(:validate_retry_config)

      expect(validator.issues).to include(
        hash_including(code: "excessive_retries", severity: "warning")
      )
    end

    it "does not add warning for reasonable retry count" do
      node = build_node(configuration: { "retry_count" => 3 })
      validator = described_class.new(node)

      validator.send(:validate_retry_config)

      expect(validator.issues).to be_empty
    end
  end

  describe "#add_issue" do
    it "sets default values for optional fields" do
      node = build_node(configuration: { "key" => "value" })
      validator = described_class.new(node)

      validator.send(:add_issue, { code: "test_issue", message: "Test" })

      issue = validator.issues.first
      expect(issue[:severity]).to eq("warning")
      expect(issue[:category]).to eq("configuration")
      expect(issue[:auto_fixable]).to eq(false)
      expect(issue[:rule_id]).to eq("test_issue")
      expect(issue[:rule_name]).to eq("Test Issue")
    end

    it "preserves explicitly set values" do
      node = build_node(configuration: { "key" => "value" })
      validator = described_class.new(node)

      validator.send(:add_issue, {
        code: "custom",
        severity: "error",
        category: "security",
        auto_fixable: true,
        message: "Custom issue"
      })

      issue = validator.issues.first
      expect(issue[:severity]).to eq("error")
      expect(issue[:category]).to eq("security")
      expect(issue[:auto_fixable]).to eq(true)
    end
  end
end

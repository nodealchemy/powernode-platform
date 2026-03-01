# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::WorkflowValidators::WebhookValidator do
  let(:account) { create(:account) }
  let(:workflow) { create(:ai_workflow, account: account) }

  def build_node(configuration: {}, timeout_seconds: 30, retry_count: 0)
    node = build(:ai_workflow_node, node_type: "webhook", workflow: workflow)
    node.configuration = configuration
    node.timeout_seconds = timeout_seconds
    node.retry_count = retry_count
    node
  end

  describe "#validate" do
    context "with valid configuration" do
      it "returns no errors for a complete configuration" do
        node = build_node(configuration: {
          "url" => "https://webhook.example.com/notify",
          "method" => "POST",
          "payload_template" => '{"event": "completed"}',
          "timeout_seconds" => 30
        })

        issues = described_class.new(node).validate

        errors = issues.select { |i| i[:severity] == "error" }
        expect(errors).to be_empty
      end
    end

    context "with missing url" do
      it "adds missing_url error" do
        node = build_node(configuration: { "method" => "POST" })

        issues = described_class.new(node).validate

        expect(issues).to include(
          hash_including(code: "missing_url", severity: "error")
        )
      end
    end

    context "with invalid URL format" do
      it "adds invalid_webhook_url error for malformed URL" do
        node = build_node(configuration: {
          "url" => "not-a-valid-url",
          "method" => "POST"
        })

        issues = described_class.new(node).validate

        expect(issues).to include(
          hash_including(code: "invalid_webhook_url", severity: "error")
        )
      end

      it "does not add error for valid HTTPS URL" do
        node = build_node(configuration: {
          "url" => "https://webhook.example.com/api/v1/events",
          "method" => "POST"
        })

        issues = described_class.new(node).validate

        url_issues = issues.select { |i| i[:code] == "invalid_webhook_url" }
        expect(url_issues).to be_empty
      end
    end

    context "with invalid webhook method" do
      it "adds invalid_webhook_method warning for GET" do
        node = build_node(configuration: {
          "url" => "https://webhook.example.com",
          "method" => "GET"
        })

        issues = described_class.new(node).validate

        expect(issues).to include(
          hash_including(code: "invalid_webhook_method", severity: "warning")
        )
      end

      it "adds invalid_webhook_method warning for DELETE" do
        node = build_node(configuration: {
          "url" => "https://webhook.example.com",
          "method" => "DELETE"
        })

        issues = described_class.new(node).validate

        expect(issues).to include(
          hash_including(code: "invalid_webhook_method", severity: "warning")
        )
      end

      it "accepts POST method" do
        node = build_node(configuration: {
          "url" => "https://webhook.example.com",
          "method" => "POST"
        })

        issues = described_class.new(node).validate

        codes = issues.map { |i| i[:code] }
        expect(codes).not_to include("invalid_webhook_method")
      end

      it "accepts PUT method" do
        node = build_node(configuration: {
          "url" => "https://webhook.example.com",
          "method" => "PUT"
        })

        issues = described_class.new(node).validate

        codes = issues.map { |i| i[:code] }
        expect(codes).not_to include("invalid_webhook_method")
      end

      it "accepts PATCH method" do
        node = build_node(configuration: {
          "url" => "https://webhook.example.com",
          "method" => "PATCH"
        })

        issues = described_class.new(node).validate

        codes = issues.map { |i| i[:code] }
        expect(codes).not_to include("invalid_webhook_method")
      end

      it "defaults to POST when method is not configured" do
        node = build_node(configuration: {
          "url" => "https://webhook.example.com"
        })

        issues = described_class.new(node).validate

        codes = issues.map { |i| i[:code] }
        expect(codes).not_to include("invalid_webhook_method")
      end
    end

    context "with missing payload configuration" do
      it "adds missing_webhook_payload info when both template and mapping are missing" do
        node = build_node(configuration: {
          "url" => "https://webhook.example.com",
          "method" => "POST",
          "timeout_seconds" => 30
        })

        issues = described_class.new(node).validate

        expect(issues).to include(
          hash_including(
            code: "missing_webhook_payload",
            severity: "info"
          )
        )
      end

      it "does not add info when payload_template is present" do
        node = build_node(configuration: {
          "url" => "https://webhook.example.com",
          "method" => "POST",
          "payload_template" => '{"event": "test"}'
        })

        issues = described_class.new(node).validate

        codes = issues.map { |i| i[:code] }
        expect(codes).not_to include("missing_webhook_payload")
      end

      it "does not add info when payload_mapping is present" do
        node = build_node(configuration: {
          "url" => "https://webhook.example.com",
          "method" => "POST",
          "payload_mapping" => { "event" => "input.event_type" }
        })

        issues = described_class.new(node).validate

        codes = issues.map { |i| i[:code] }
        expect(codes).not_to include("missing_webhook_payload")
      end
    end

    context "with timeout validation" do
      it "inherits timeout validation from base" do
        node = build_node(configuration: {
          "url" => "https://webhook.example.com",
          "method" => "POST",
          "payload_template" => "{}",
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
        node = build_node(configuration: {
          "url" => "https://webhook.example.com",
          "method" => "POST",
          "payload_template" => "{}",
          "retry_count" => 20
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

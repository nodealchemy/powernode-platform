# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::WorkflowValidators::ApiCallValidator do
  let(:account) { create(:account) }
  let(:workflow) { create(:ai_workflow, account: account) }

  def build_node(configuration: {}, timeout_seconds: 30, retry_count: 0)
    node = build(:ai_workflow_node, node_type: "api_call", workflow: workflow)
    node.configuration = configuration
    node.timeout_seconds = timeout_seconds
    node.retry_count = retry_count
    node
  end

  describe "#validate" do
    context "with valid configuration" do
      it "returns no errors for a complete configuration" do
        node = build_node(configuration: {
          "url" => "https://api.example.com/data",
          "method" => "GET",
          "timeout_seconds" => 30
        })

        issues = described_class.new(node).validate

        errors = issues.select { |i| i[:severity] == "error" }
        expect(errors).to be_empty
      end

      it "accepts all valid HTTP methods" do
        %w[GET POST PUT PATCH DELETE HEAD OPTIONS].each do |method|
          node = build_node(configuration: {
            "url" => "https://api.example.com",
            "method" => method,
            "timeout_seconds" => 30
          })

          issues = described_class.new(node).validate

          method_issues = issues.select { |i| i[:code] == "invalid_method_value" }
          expect(method_issues).to be_empty, "Expected method '#{method}' to be valid"
        end
      end
    end

    context "with missing required fields" do
      it "adds error for missing url" do
        node = build_node(configuration: { "method" => "GET" })

        issues = described_class.new(node).validate

        expect(issues).to include(
          hash_including(code: "missing_url", severity: "error")
        )
      end

      it "adds error for missing method" do
        node = build_node(configuration: { "url" => "https://api.example.com" })

        issues = described_class.new(node).validate

        expect(issues).to include(
          hash_including(code: "missing_method", severity: "error")
        )
      end

      it "adds errors for both missing url and method" do
        node = build_node(configuration: { "other" => "value" })

        issues = described_class.new(node).validate

        codes = issues.map { |i| i[:code] }
        expect(codes).to include("missing_url", "missing_method")
      end
    end

    context "with invalid URL format" do
      it "adds invalid_url error for malformed URL" do
        node = build_node(configuration: {
          "url" => "not-a-valid-url",
          "method" => "GET"
        })

        issues = described_class.new(node).validate

        expect(issues).to include(
          hash_including(code: "invalid_url", severity: "error")
        )
      end

      it "does not add error for valid HTTPS URL" do
        node = build_node(configuration: {
          "url" => "https://api.example.com/v1/data?key=value",
          "method" => "GET"
        })

        issues = described_class.new(node).validate

        url_issues = issues.select { |i| i[:code] == "invalid_url" }
        expect(url_issues).to be_empty
      end

      it "does not add error for valid HTTP URL" do
        node = build_node(configuration: {
          "url" => "http://localhost:3000/api",
          "method" => "GET"
        })

        issues = described_class.new(node).validate

        url_issues = issues.select { |i| i[:code] == "invalid_url" }
        expect(url_issues).to be_empty
      end
    end

    context "with invalid HTTP method" do
      it "adds invalid_method_value error" do
        node = build_node(configuration: {
          "url" => "https://api.example.com",
          "method" => "INVALID"
        })

        issues = described_class.new(node).validate

        expect(issues).to include(
          hash_including(code: "invalid_method_value", severity: "error")
        )
      end
    end

    context "with bearer auth configuration" do
      it "adds warning when auth_token is blank" do
        node = build_node(configuration: {
          "url" => "https://api.example.com",
          "method" => "GET",
          "auth_type" => "bearer",
          "auth_token" => ""
        })

        issues = described_class.new(node).validate

        expect(issues).to include(
          hash_including(code: "blank_auth_token", severity: "warning")
        )
      end

      it "does not add warning when auth_token is present" do
        node = build_node(configuration: {
          "url" => "https://api.example.com",
          "method" => "GET",
          "auth_type" => "bearer",
          "auth_token" => "my-token-123"
        })

        issues = described_class.new(node).validate

        codes = issues.map { |i| i[:code] }
        expect(codes).not_to include("blank_auth_token")
      end
    end

    context "with basic auth configuration" do
      it "adds warnings when username and password are blank" do
        node = build_node(configuration: {
          "url" => "https://api.example.com",
          "method" => "GET",
          "auth_type" => "basic",
          "username" => "",
          "password" => ""
        })

        issues = described_class.new(node).validate

        codes = issues.map { |i| i[:code] }
        expect(codes).to include("blank_username", "blank_password")
      end
    end

    context "with api_key auth configuration" do
      it "adds warnings when api_key and api_key_header are blank" do
        node = build_node(configuration: {
          "url" => "https://api.example.com",
          "method" => "GET",
          "auth_type" => "api_key",
          "api_key" => "",
          "api_key_header" => ""
        })

        issues = described_class.new(node).validate

        codes = issues.map { |i| i[:code] }
        expect(codes).to include("blank_api_key", "blank_api_key_header")
      end
    end

    context "with no auth_type" do
      it "does not validate auth fields" do
        node = build_node(configuration: {
          "url" => "https://api.example.com",
          "method" => "GET",
          "timeout_seconds" => 30
        })

        issues = described_class.new(node).validate

        auth_codes = issues.select { |i| i[:code] =~ /blank_auth|blank_username|blank_password|blank_api_key/ }
        expect(auth_codes).to be_empty
      end
    end

    context "with timeout validation" do
      it "inherits timeout validation from base" do
        node = build_node(configuration: {
          "url" => "https://api.example.com",
          "method" => "GET",
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
          "url" => "https://api.example.com",
          "method" => "GET",
          "retry_count" => 15
        })

        issues = described_class.new(node).validate

        expect(issues).to include(
          hash_including(code: "excessive_retries", severity: "warning")
        )
      end
    end
  end
end

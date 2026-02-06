# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Mcp::ElicitationService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:mock_redis) { instance_double(Redis) }
  let(:service) { described_class.new(account: account, user: user) }

  before do
    allow(Redis).to receive(:new).and_return(mock_redis)
    allow(ActionCable.server).to receive(:broadcast)
  end

  describe "constants" do
    it "has an elicitation timeout of 300 seconds" do
      expect(described_class::ELICITATION_TIMEOUT).to eq(300)
    end

    it "has a pending TTL of 600 seconds" do
      expect(described_class::PENDING_TTL).to eq(600)
    end
  end

  describe "#initialize" do
    it "initializes with account and user" do
      expect(service).to be_a(described_class)
    end

    it "accepts nil user" do
      service_without_user = described_class.new(account: account)
      expect(service_without_user).to be_a(described_class)
    end
  end

  describe "#create_request" do
    let(:tool_execution_id) { SecureRandom.uuid }
    let(:message) { "Please provide your API key" }
    let(:schema) do
      {
        "required" => ["api_key"],
        "properties" => {
          "api_key" => { "type" => "string" }
        }
      }
    end

    before do
      allow(mock_redis).to receive(:setex)
    end

    it "returns a request with a unique id" do
      request = service.create_request(
        tool_execution_id: tool_execution_id,
        message: message
      )

      expect(request[:id]).to be_a(String)
      expect(request[:id].length).to eq(36) # UUID format
    end

    it "stores the request data correctly" do
      request = service.create_request(
        tool_execution_id: tool_execution_id,
        message: message,
        schema: schema,
        metadata: { tool_name: "api_caller" }
      )

      expect(request[:tool_execution_id]).to eq(tool_execution_id)
      expect(request[:account_id]).to eq(account.id)
      expect(request[:user_id]).to eq(user.id)
      expect(request[:message]).to eq(message)
      expect(request[:schema]).to eq(schema)
      expect(request[:metadata]).to eq({ tool_name: "api_caller" })
      expect(request[:status]).to eq("pending")
      expect(request[:created_at]).to be_a(String)
    end

    it "stores request in Redis with TTL" do
      expect(mock_redis).to receive(:setex).with(
        /^mcp_elicitation:#{account.id}:#{tool_execution_id}:/,
        described_class::PENDING_TTL,
        anything
      )

      service.create_request(
        tool_execution_id: tool_execution_id,
        message: message
      )
    end

    it "broadcasts elicitation request via ActionCable" do
      expect(ActionCable.server).to receive(:broadcast).with(
        "mcp_elicitation_#{account.id}",
        hash_including(type: "elicitation_request")
      )

      service.create_request(
        tool_execution_id: tool_execution_id,
        message: message
      )
    end

    it "handles broadcast failures gracefully" do
      allow(ActionCable.server).to receive(:broadcast).and_raise(StandardError, "Channel error")

      expect {
        service.create_request(
          tool_execution_id: tool_execution_id,
          message: message
        )
      }.not_to raise_error
    end
  end

  describe "#respond" do
    let(:request_id) { SecureRandom.uuid }
    let(:tool_execution_id) { SecureRandom.uuid }
    let(:stored_request) do
      {
        "id" => request_id,
        "tool_execution_id" => tool_execution_id,
        "account_id" => account.id,
        "status" => "pending",
        "message" => "Provide input",
        "schema" => nil,
        "created_at" => Time.current.iso8601
      }
    end

    before do
      allow(mock_redis).to receive(:keys).and_return(["mcp_elicitation:#{account.id}:#{tool_execution_id}:#{request_id}"])
      allow(mock_redis).to receive(:get).and_return(stored_request.to_json)
      allow(mock_redis).to receive(:setex)
    end

    context "when approved" do
      it "returns accepted: true with the response" do
        result = service.respond(request_id: request_id, response: { answer: "yes" })

        expect(result[:accepted]).to be true
        expect(result[:response]).to eq({ answer: "yes" })
      end

      it "updates request status to responded" do
        expect(mock_redis).to receive(:setex) do |_key, _ttl, data|
          parsed = JSON.parse(data)
          expect(parsed["status"]).to eq("responded")
          expect(parsed["responded_at"]).to be_a(String)
          expect(parsed["responded_by"]).to eq(user.id)
        end

        service.respond(request_id: request_id, response: { answer: "yes" })
      end

      it "broadcasts elicitation update" do
        expect(ActionCable.server).to receive(:broadcast).with(
          "mcp_elicitation_#{account.id}",
          hash_including(type: "elicitation_update")
        )

        service.respond(request_id: request_id, response: { answer: "yes" })
      end
    end

    context "when denied" do
      it "raises ElicitationDeniedError" do
        expect {
          service.respond(request_id: request_id, response: {}, approved: false)
        }.to raise_error(Ai::Mcp::ElicitationService::ElicitationDeniedError, /denied by user/)
      end

      it "updates request status to denied" do
        expect(mock_redis).to receive(:setex) do |_key, _ttl, data|
          parsed = JSON.parse(data)
          expect(parsed["status"]).to eq("denied")
          expect(parsed["denied_by"]).to eq(user.id)
        end

        begin
          service.respond(request_id: request_id, response: {}, approved: false)
        rescue Ai::Mcp::ElicitationService::ElicitationDeniedError
          # Expected
        end
      end
    end

    context "when request not found" do
      it "raises ElicitationError" do
        allow(mock_redis).to receive(:keys).and_return([])
        allow(mock_redis).to receive(:get).and_return(nil)

        expect {
          service.respond(request_id: "nonexistent", response: {})
        }.to raise_error(Ai::Mcp::ElicitationService::ElicitationError, /not found/)
      end
    end

    context "when request already responded" do
      it "raises ElicitationError" do
        responded_request = stored_request.merge("status" => "responded")
        allow(mock_redis).to receive(:get).and_return(responded_request.to_json)

        expect {
          service.respond(request_id: request_id, response: {})
        }.to raise_error(Ai::Mcp::ElicitationService::ElicitationError, /already responded/)
      end
    end

    context "with schema validation" do
      let(:schema) do
        {
          "required" => ["api_key", "region"],
          "properties" => {
            "api_key" => { "type" => "string" },
            "region" => { "type" => "string" },
            "count" => { "type" => "integer" },
            "enabled" => { "type" => "boolean" }
          }
        }
      end

      before do
        request_with_schema = stored_request.merge("schema" => schema)
        allow(mock_redis).to receive(:get).and_return(request_with_schema.to_json)
      end

      it "validates required fields" do
        expect {
          service.respond(request_id: request_id, response: { "api_key" => "key123" })
        }.to raise_error(Ai::Mcp::ElicitationService::ElicitationError, /Missing required field: region/)
      end

      it "validates field types" do
        expect {
          service.respond(request_id: request_id, response: { "api_key" => "key123", "region" => "us-east", "count" => "not_a_number" })
        }.to raise_error(Ai::Mcp::ElicitationService::ElicitationError, /count must be integer/)
      end

      it "accepts valid responses matching schema" do
        result = service.respond(
          request_id: request_id,
          response: { "api_key" => "key123", "region" => "us-east", "count" => 5, "enabled" => true }
        )

        expect(result[:accepted]).to be true
      end
    end
  end

  describe "#pending_requests" do
    it "returns pending requests for the account" do
      pending_request = {
        "id" => SecureRandom.uuid,
        "status" => "pending",
        "created_at" => Time.current.iso8601
      }
      responded_request = {
        "id" => SecureRandom.uuid,
        "status" => "responded",
        "created_at" => 1.minute.ago.iso8601
      }

      allow(mock_redis).to receive(:keys)
        .with("mcp_elicitation:#{account.id}:*")
        .and_return(["key1", "key2"])
      allow(mock_redis).to receive(:get).with("key1").and_return(pending_request.to_json)
      allow(mock_redis).to receive(:get).with("key2").and_return(responded_request.to_json)

      results = service.pending_requests

      expect(results.length).to eq(1)
      expect(results.first["status"]).to eq("pending")
    end

    it "filters by tool_execution_id when provided" do
      tool_execution_id = SecureRandom.uuid

      expect(mock_redis).to receive(:keys)
        .with("mcp_elicitation:#{account.id}:#{tool_execution_id}:*")
        .and_return([])

      service.pending_requests(tool_execution_id: tool_execution_id)
    end

    it "returns empty array on error" do
      allow(mock_redis).to receive(:keys).and_raise(StandardError, "Redis down")

      result = service.pending_requests

      expect(result).to eq([])
    end

    it "sorts results by created_at" do
      older_request = {
        "id" => "req-1",
        "status" => "pending",
        "created_at" => 5.minutes.ago.iso8601
      }
      newer_request = {
        "id" => "req-2",
        "status" => "pending",
        "created_at" => 1.minute.ago.iso8601
      }

      allow(mock_redis).to receive(:keys).and_return(["key1", "key2"])
      allow(mock_redis).to receive(:get).with("key1").and_return(newer_request.to_json)
      allow(mock_redis).to receive(:get).with("key2").and_return(older_request.to_json)

      results = service.pending_requests

      expect(results.first["id"]).to eq("req-1")
      expect(results.last["id"]).to eq("req-2")
    end
  end

  describe "error classes" do
    it "ElicitationError is a StandardError" do
      expect(described_class::ElicitationError.new).to be_a(StandardError)
    end

    it "ElicitationTimeoutError is an ElicitationError" do
      expect(described_class::ElicitationTimeoutError.new).to be_a(described_class::ElicitationError)
    end

    it "ElicitationDeniedError is an ElicitationError" do
      expect(described_class::ElicitationDeniedError.new).to be_a(described_class::ElicitationError)
    end
  end
end

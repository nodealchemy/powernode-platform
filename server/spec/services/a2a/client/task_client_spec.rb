# frozen_string_literal: true

require "rails_helper"

RSpec.describe A2a::Client::TaskClient do
  let(:account) { create(:account) }
  let(:external_agent) do
    create(:external_agent, :with_cached_card, account: account,
                                               cached_card: {
                                                 "name" => "Test Agent",
                                                 "url" => "https://example.com/a2a",
                                                 "authentication" => { "schemes" => [ "bearer" ] }
                                               })
  end
  let(:client) { described_class.new(external_agent) }

  describe "#send_message" do
    let(:a2a_url) { "https://example.com/a2a" }

    context "when successful" do
      before do
        stub_request(:post, a2a_url)
          .to_return(status: 200, body: {
            jsonrpc: "2.0",
            result: {
              id: "task-123",
              status: "completed",
              output: { result: "success" }
            }
          }.to_json)
      end

      it "sends message and returns task" do
        result = client.send_message(skill: "test.skill", input: { data: "test" })

        expect(result[:success]).to be true
        expect(result[:task]["id"]).to eq("task-123")
      end

      it "records successful task result" do
        expect(external_agent).to receive(:record_task_result!).with(
          success: true,
          response_time_ms: anything
        )

        client.send_message(skill: "test.skill", input: {})
      end
    end

    context "when error" do
      before do
        stub_request(:post, a2a_url)
          .to_return(status: 200, body: {
            jsonrpc: "2.0",
            error: { code: -32000, message: "Execution failed" }
          }.to_json)
      end

      it "returns error" do
        result = client.send_message(skill: "test.skill", input: {})

        expect(result[:success]).to be false
        expect(result[:error]).to be_present
      end

      it "records failed task result" do
        expect(external_agent).to receive(:record_task_result!).with(
          success: false,
          response_time_ms: anything
        )

        client.send_message(skill: "test.skill", input: {})
      end
    end

    context "when HTTP error" do
      before do
        stub_request(:post, a2a_url)
          .to_return(status: 500)
      end

      it "returns error" do
        result = client.send_message(skill: "test.skill", input: {})

        expect(result[:success]).to be false
        expect(result[:error]).to include("500")
      end
    end
  end

  describe "#get_task" do
    let(:a2a_url) { "https://example.com/a2a" }

    context "when successful" do
      before do
        stub_request(:post, a2a_url)
          .to_return(status: 200, body: {
            jsonrpc: "2.0",
            result: { id: "task-123", status: "completed" }
          }.to_json)
      end

      it "returns task details" do
        result = client.get_task("task-123")

        expect(result[:success]).to be true
        expect(result[:task]["id"]).to eq("task-123")
      end
    end
  end

  describe "#cancel_task" do
    let(:a2a_url) { "https://example.com/a2a" }

    before do
      stub_request(:post, a2a_url)
        .to_return(status: 200, body: {
          jsonrpc: "2.0",
          result: { id: "task-123", status: "cancelled" }
        }.to_json)
    end

    it "cancels the task" do
      result = client.cancel_task("task-123", reason: "User cancelled")

      expect(result[:success]).to be true
      expect(result[:task]["status"]).to eq("cancelled")
    end
  end

  describe "#wait_for_task" do
    let(:a2a_url) { "https://example.com/a2a" }

    context "when task completes" do
      before do
        stub_request(:post, a2a_url)
          .to_return(status: 200, body: {
            jsonrpc: "2.0",
            result: { id: "task-123", status: "completed" }
          }.to_json)
      end

      it "returns completed task" do
        result = client.wait_for_task("task-123", timeout: 5)

        expect(result[:success]).to be true
        expect(result[:completed]).to be true
      end
    end

    context "when task still running" do
      before do
        call_count = 0
        stub_request(:post, a2a_url)
          .to_return do
            call_count += 1
            {
              status: 200,
              body: {
                jsonrpc: "2.0",
                result: { id: "task-123", status: call_count < 3 ? "working" : "completed" }
              }.to_json
            }
          end
      end

      it "polls until completed" do
        result = client.wait_for_task("task-123", timeout: 10)

        expect(result[:success]).to be true
        expect(result[:completed]).to be true
      end
    end
  end

  describe "message building" do
    let(:a2a_url) { "https://example.com/a2a" }

    before do
      stub_request(:post, a2a_url)
        .to_return(status: 200, body: {
          jsonrpc: "2.0",
          result: { id: "task-123", status: "completed" }
        }.to_json)
    end

    it "builds message from string input" do
      client.send_message(skill: "test.skill", input: "Hello world")

      expect(WebMock).to have_requested(:post, a2a_url)
        .with { |req|
          body = JSON.parse(req.body)
          message = body.dig("params", "message")
          message["parts"].any? { |p| p["text"] == "Hello world" }
        }
    end

    it "builds message from hash input" do
      client.send_message(skill: "test.skill", input: { "text" => "Hello world" })

      expect(WebMock).to have_requested(:post, a2a_url)
        .with { |req|
          body = JSON.parse(req.body)
          message = body.dig("params", "message")
          message["parts"].any? { |p| p["text"] == "Hello world" }
        }
    end
  end
end

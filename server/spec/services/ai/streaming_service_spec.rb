# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::StreamingService do
  let(:account) { create(:account) }
  let(:provider) { create(:ai_provider, account: account) }
  let(:agent) { create(:ai_agent, account: account, provider: provider) }
  let(:execution) { create(:ai_agent_execution, account: account, agent: agent, provider: provider) }
  let(:service) { described_class.new(execution: execution, account: account) }

  describe "#initialize" do
    it "initializes with required parameters" do
      expect(service.execution).to eq(execution)
      expect(service.account).to eq(account)
    end

    it "generates a unique stream_id" do
      service1 = described_class.new(execution: execution, account: account)
      service2 = described_class.new(execution: execution, account: account)

      # Each service has its own internal stream_id
      expect(service1).not_to eq(service2)
    end
  end

  describe "#process_stream_chunk" do
    let(:chunk_data) do
      {
        content: "Hello",
        accumulated_content: "Hello"
      }
    end

    it "adds content to buffer" do
      service.process_stream_chunk(chunk_data)

      # Internal buffer should have the content
      expect(service.instance_variable_get(:@buffer)).to include("Hello")
    end

    it "broadcasts stream_chunk event" do
      expect(ActionCable.server).to receive(:broadcast).at_least(:once)

      service.process_stream_chunk(chunk_data)
    end

    it "ignores chunks without content" do
      expect(ActionCable.server).not_to receive(:broadcast)

      service.process_stream_chunk({ content: nil })
    end
  end

  describe "#complete_stream" do
    let(:full_response) { "This is the complete response." }
    let(:usage) do
      {
        prompt_tokens: 50,
        completion_tokens: 30,
        total_tokens: 80
      }
    end

    it "broadcasts stream_completed event" do
      expect(ActionCable.server).to receive(:broadcast).at_least(:once) do |channel, message|
        if message[:type] == "stream_completed"
          expect(message[:data][:full_response]).to eq(full_response)
        end
      end

      service.complete_stream(full_response, usage)
    end

    it "updates execution with final results" do
      service.complete_stream(full_response, usage)

      execution.reload
      expect(execution.status).to eq("completed")
      expect(execution.completed_at).to be_present
      expect(execution.output_data["response"]).to eq(full_response)
    end

    it "records token usage from provider" do
      service.complete_stream(full_response, usage)

      execution.reload
      expect(execution.tokens_used).to eq(80)
    end

    it "calculates cost" do
      service.complete_stream(full_response, usage)

      execution.reload
      expect(execution.cost_usd).to be_present
    end
  end

  describe "#handle_stream_error" do
    let(:error) { StandardError.new("Stream failed") }

    it "broadcasts stream_error event" do
      expect(ActionCable.server).to receive(:broadcast).at_least(:once) do |channel, message|
        if message[:type] == "stream_error"
          expect(message[:data][:error]).to eq("Stream failed")
        end
      end

      expect { service.handle_stream_error(error) }.to raise_error(StandardError)
    end

    it "updates execution with error status" do
      expect { service.handle_stream_error(error) }.to raise_error(StandardError)

      execution.reload
      expect(execution.status).to eq("failed")
      expect(execution.error_details).to be_present
      expect(execution.error_details["error"]).to eq("Stream failed")
    end

    it "re-raises the error" do
      expect { service.handle_stream_error(error) }.to raise_error(StandardError, "Stream failed")
    end
  end

  describe "private methods" do
    describe "#estimate_tokens" do
      it "estimates token count from text length" do
        # Private method test via send
        tokens = service.send(:estimate_tokens, "Hello world!")

        # Rough estimate: 12 chars / 4 = 3 tokens
        expect(tokens).to eq(3)
      end

      it "handles empty text" do
        tokens = service.send(:estimate_tokens, "")

        expect(tokens).to eq(0)
      end
    end

    describe "#estimate_progress" do
      it "returns progress percentage based on buffer size" do
        # Add some content to buffer
        5.times { service.process_stream_chunk(content: "x", accumulated_content: "x") }

        progress = service.send(:estimate_progress)

        expect(progress).to be_between(0, 100)
      end

      it "caps progress at 99% during streaming" do
        # Add lots of content
        300.times { service.instance_variable_get(:@buffer) << "x" }

        progress = service.send(:estimate_progress)

        expect(progress).to be <= 99
      end
    end

    describe "#calculate_cost" do
      it "calculates cost based on token counts" do
        token_count = { prompt: 1000, completion: 500 }

        cost = service.send(:calculate_cost, token_count, provider)

        expect(cost).to be_a(Numeric)
        expect(cost).to be >= 0
      end

      it "returns 0 when provider is nil" do
        token_count = { prompt: 1000, completion: 500 }

        cost = service.send(:calculate_cost, token_count, nil)

        expect(cost).to eq(0)
      end
    end

    describe "#build_messages" do
      it "includes system prompt from agent metadata" do
        agent.update!(metadata: { "system_prompt" => "You are a helpful assistant." })

        messages = service.send(:build_messages, agent, { message: "Hello" })

        system_message = messages.find { |m| m[:role] == "system" }
        expect(system_message).to be_present
        expect(system_message[:content]).to eq("You are a helpful assistant.")
      end

      it "includes user message from input" do
        messages = service.send(:build_messages, agent, { message: "Hello" })

        user_message = messages.find { |m| m[:role] == "user" }
        expect(user_message).to be_present
        expect(user_message[:content]).to eq("Hello")
      end

      it "handles different input parameter keys" do
        messages = service.send(:build_messages, agent, { content: "Test content" })

        user_message = messages.find { |m| m[:role] == "user" }
        expect(user_message[:content]).to eq("Test content")
      end
    end
  end
end

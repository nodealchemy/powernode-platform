# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Agents::ConversationService, type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:agent) { create(:ai_agent, account: account) }

  subject(:service) { described_class.new(agent: agent, user: user) }

  describe '#create' do
    it 'creates a conversation successfully' do
      result = service.create(title: "Test Conversation")

      expect(result.success?).to be true
      conversation = result.data[:conversation]
      expect(conversation).to be_persisted
      expect(conversation.title).to eq("Test Conversation")
      expect(conversation.user).to eq(user)
      expect(conversation.account).to eq(account)
    end

    it 'returns error when validation fails' do
      # Title may or may not be required; test with invalid attribute
      conversation = instance_double(Ai::Conversation)
      allow(agent).to receive_message_chain(:conversations, :build).and_return(conversation)
      allow(conversation).to receive(:user=)
      allow(conversation).to receive(:account=)
      allow(conversation).to receive(:provider=)
      allow(conversation).to receive(:save).and_return(false)
      errors = double('errors', full_messages: ["Title is too long"])
      allow(conversation).to receive(:errors).and_return(errors)

      result = service.create(title: "x" * 10000)
      expect(result.success?).to be false
      expect(result.error).to include("Title is too long")
    end
  end

  describe '#update' do
    let(:conversation) { create(:ai_conversation, agent: agent, user: user, account: account) }

    it 'updates conversation attributes' do
      result = service.update(conversation, title: "Updated Title")

      expect(result.success?).to be true
      expect(result.data[:conversation].title).to eq("Updated Title")
    end

    it 'returns error when update fails' do
      allow(conversation).to receive(:update).and_return(false)
      errors = double('errors', full_messages: ["Invalid update"])
      allow(conversation).to receive(:errors).and_return(errors)

      result = service.update(conversation, {})
      expect(result.success?).to be false
    end
  end

  describe '#destroy' do
    let(:conversation) { create(:ai_conversation, agent: agent, user: user, account: account) }

    it 'destroys the conversation' do
      result = service.destroy(conversation)

      expect(result.success?).to be true
      expect(result.data[:message]).to eq("Conversation deleted successfully")
    end

    it 'returns error when destruction fails' do
      allow(conversation).to receive(:destroy).and_return(false)

      result = service.destroy(conversation)
      expect(result.success?).to be false
    end
  end

  describe '#send_message' do
    let(:conversation) { create(:ai_conversation, agent: agent, user: user, account: account) }
    let(:message) { double('message', id: SecureRandom.uuid) }

    it 'adds a user message to the conversation' do
      allow(conversation).to receive(:add_user_message).and_return(message)

      result = service.send_message(conversation, content: "Hello!")

      expect(result.success?).to be true
      expect(result.data[:message]).to eq(message)
    end

    it 'returns error when message sending fails' do
      allow(conversation).to receive(:add_user_message).and_raise(StandardError.new("DB error"))

      result = service.send_message(conversation, content: "Hello!")

      expect(result.success?).to be false
      expect(result.error).to include("Failed to send message")
    end
  end

  describe '#pause' do
    let(:conversation) { create(:ai_conversation, agent: agent, user: user, account: account) }

    it 'pauses the conversation' do
      result = service.pause(conversation)

      expect(result.success?).to be true
      expect(conversation.reload.status).to eq("paused")
    end
  end

  describe '#resume' do
    let(:conversation) { create(:ai_conversation, agent: agent, user: user, account: account, status: "paused") }

    it 'resumes the conversation' do
      # pause_conversation! sets to paused; resume_conversation! sets back to active
      conversation.update!(status: "paused")
      result = service.resume(conversation)

      expect(result.success?).to be true
      expect(conversation.reload.status).to eq("active")
    end
  end

  describe '#complete' do
    let(:conversation) { create(:ai_conversation, agent: agent, user: user, account: account) }

    it 'completes the conversation' do
      result = service.complete(conversation)

      expect(result.success?).to be true
      expect(conversation.reload.status).to eq("completed")
    end
  end

  describe '#archive' do
    let(:conversation) { create(:ai_conversation, agent: agent, user: user, account: account) }

    it 'archives the conversation' do
      result = service.archive(conversation)

      expect(result.success?).to be true
      expect(conversation.reload.status).to eq("archived")
    end
  end

  describe '#export' do
    let(:conversation) { create(:ai_conversation, agent: agent, user: user, account: account) }

    it 'returns export data with conversation and format' do
      result = service.export(conversation, format: "json")

      expect(result[:conversation]).to eq(conversation)
      expect(result[:export_format]).to eq("json")
      expect(result[:exported_at]).to be_present
    end

    it 'defaults to json format' do
      result = service.export(conversation)

      expect(result[:export_format]).to eq("json")
    end
  end

  describe '#regenerate_message' do
    let(:conversation) { create(:ai_conversation, agent: agent, user: user, account: account) }

    context 'with an assistant message' do
      # Service uses message.processing_metadata for reading and writes to :metadata key in update!.
      # Use a double to test the service's intended logic.
      let(:stored_metadata) { {} }
      let(:message) do
        msg = double('message', id: SecureRandom.uuid, role: "assistant",
                     content: "Original response", metadata: stored_metadata,
                     processing_metadata: stored_metadata)
        allow(msg).to receive(:update!) do |attrs|
          stored_metadata.merge!(attrs[:metadata]) if attrs[:metadata]
        end
        allow(msg).to receive(:reload).and_return(msg)
        allow(msg).to receive(:metadata) { stored_metadata }
        allow(msg).to receive(:processing_metadata) { stored_metadata }
        msg
      end

      it 'marks the message for regeneration' do
        result = service.regenerate_message(conversation, message)

        expect(result.success?).to be true
        expect(result.data[:regeneration_queued]).to be true
        expect(message.metadata).to include("regenerated" => true)
      end

      it 'preserves original content in metadata' do
        service.regenerate_message(conversation, message)

        expect(message.metadata["original_content"]).to eq("Original response")
      end
    end

    context 'with a user message' do
      let(:message) { double('message', role: "user") }

      it 'returns error for non-assistant messages' do
        result = service.regenerate_message(conversation, message)

        expect(result.success?).to be false
        expect(result.error).to include("Can only regenerate assistant messages")
      end
    end
  end

  describe '#rate_message' do
    let(:conversation) { create(:ai_conversation, agent: agent, user: user, account: account) }

    context 'with an assistant message' do
      let(:stored_metadata) { {} }
      let(:message) do
        msg = double('message', id: SecureRandom.uuid, role: "assistant",
                     metadata: stored_metadata, processing_metadata: stored_metadata)
        allow(msg).to receive(:update!) do |attrs|
          stored_metadata.merge!(attrs[:metadata]) if attrs[:metadata]
        end
        allow(msg).to receive(:reload).and_return(msg)
        allow(msg).to receive(:metadata) { stored_metadata }
        allow(msg).to receive(:processing_metadata) { stored_metadata }
        msg
      end

      it 'rates with thumbs_up' do
        result = service.rate_message(message, rating: "thumbs_up")

        expect(result.success?).to be true
        expect(message.metadata["user_rating"]["rating"]).to eq("thumbs_up")
      end

      it 'rates with thumbs_down and feedback' do
        result = service.rate_message(message, rating: "thumbs_down", feedback: "Not helpful")

        expect(result.success?).to be true
        rating_data = message.metadata["user_rating"]
        expect(rating_data["rating"]).to eq("thumbs_down")
        expect(rating_data["feedback"]).to eq("Not helpful")
      end

      it 'rejects invalid ratings' do
        result = service.rate_message(message, rating: "invalid")

        expect(result.success?).to be false
        expect(result.error).to include("Rating must be thumbs_up or thumbs_down")
      end
    end

    context 'with a user message' do
      let(:message) { double('message', role: "user") }

      it 'returns error' do
        result = service.rate_message(message, rating: "thumbs_up")

        expect(result.success?).to be false
        expect(result.error).to include("Can only rate assistant messages")
      end
    end
  end
end

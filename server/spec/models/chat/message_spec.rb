# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Chat::Message, type: :model do
  describe 'associations' do
    it { should belong_to(:session).class_name('Chat::Session') }
    it { should have_many(:attachments).class_name('Chat::MessageAttachment').dependent(:destroy) }
  end

  describe 'validations' do
    subject { build(:chat_message) }

    it { should validate_presence_of(:direction) }
    it { should validate_inclusion_of(:direction).in_array(%w[inbound outbound]) }
    it { should validate_presence_of(:message_type) }
    it { should validate_inclusion_of(:message_type).in_array(%w[text image audio video document location sticker]) }
    it { should validate_inclusion_of(:delivery_status).in_array(%w[pending sent delivered read failed]) }
  end

  describe 'scopes' do
    let!(:inbound_message) { create(:chat_message, :inbound) }
    let!(:outbound_message) { create(:chat_message, :outbound) }
    let!(:text_message) { create(:chat_message, :text) }
    let!(:image_message) { create(:chat_message, :image) }

    describe '.inbound' do
      it 'returns only inbound messages' do
        expect(Chat::Message.inbound).to include(inbound_message)
        expect(Chat::Message.inbound).not_to include(outbound_message)
      end
    end

    describe '.outbound' do
      it 'returns only outbound messages' do
        expect(Chat::Message.outbound).to include(outbound_message)
        expect(Chat::Message.outbound).not_to include(inbound_message)
      end
    end

    describe '.by_type' do
      it 'filters by message type' do
        expect(Chat::Message.by_type('text')).to include(text_message)
        expect(Chat::Message.by_type('text')).not_to include(image_message)
      end
    end
  end

  describe 'sanitized_content' do
    # Note: Sanitization is handled by the Session model when adding inbound messages
    # The Message model stores both raw content and sanitized_content
    it 'stores separate sanitized_content field' do
      message = build(:chat_message, content: 'Hello', sanitized_content: 'Sanitized Hello')
      expect(message.content).to eq('Hello')
      expect(message.sanitized_content).to eq('Sanitized Hello')
    end
  end

  describe 'direction methods' do
    describe '#inbound?' do
      it 'returns true for inbound messages' do
        message = build(:chat_message, :inbound)
        expect(message.inbound?).to be true
      end
    end

    describe '#outbound?' do
      it 'returns true for outbound messages' do
        message = build(:chat_message, :outbound)
        expect(message.outbound?).to be true
      end
    end
  end

  describe 'delivery status methods' do
    describe '#delivered?' do
      it 'returns true when delivered' do
        message = build(:chat_message, :delivered)
        expect(message.delivered?).to be true
      end
    end

    describe '#failed?' do
      it 'returns true when failed' do
        message = build(:chat_message, :failed)
        expect(message.failed?).to be true
      end
    end
  end

  describe '#mark_delivered!' do
    let(:message) { create(:chat_message, :pending) }

    it 'changes delivery status to delivered' do
      message.mark_delivered!
      expect(message.reload.delivery_status).to eq('delivered')
    end
  end

  describe '#mark_read!' do
    let(:message) { create(:chat_message, :delivered) }

    it 'changes delivery status to read' do
      message.mark_read!
      expect(message.reload.delivery_status).to eq('read')
    end
  end

  describe '#mark_failed!' do
    let(:message) { create(:chat_message, :pending) }

    it 'changes delivery status to failed' do
      message.mark_failed!('Delivery error')
      expect(message.reload.delivery_status).to eq('failed')
      expect(message.platform_metadata['error']).to eq('Delivery error')
    end
  end

  describe '#mark_sent!' do
    let(:message) { create(:chat_message, :pending) }

    it 'changes delivery status to sent' do
      message.mark_sent!('plat_msg_123')
      expect(message.reload.delivery_status).to eq('sent')
      expect(message.sent_at).to be_present
      expect(message.platform_message_id).to eq('plat_msg_123')
    end

    it 'works without platform_message_id' do
      message.mark_sent!
      expect(message.reload.delivery_status).to eq('sent')
    end
  end

  describe '#display_content' do
    it 'returns content for text messages' do
      message = build(:chat_message, :text, content: 'Hello world')
      expect(message.display_content).to eq('Hello world')
    end

    it 'returns formatted string for image messages' do
      message = build(:chat_message, :image)
      expect(message.display_content).to match(/\[Image:/)
    end

    it 'returns formatted string for audio messages' do
      message = build(:chat_message, :audio)
      expect(message.display_content).to match(/\[Audio:/)
    end

    it 'returns sticker placeholder for sticker type' do
      message = build(:chat_message, message_type: 'sticker', content: 'sticker')
      expect(message.display_content).to eq('[Sticker]')
    end
  end

  describe '#content_for_ai' do
    it 'returns sanitized_content when present' do
      message = build(:chat_message, content: 'raw', sanitized_content: 'sanitized')
      expect(message.content_for_ai).to eq('sanitized')
    end

    it 'falls back to content when sanitized_content is nil' do
      message = build(:chat_message, content: 'raw', sanitized_content: nil)
      expect(message.content_for_ai).to eq('raw')
    end
  end

  describe '#to_a2a_message' do
    it 'returns user role for inbound messages' do
      message = build(:chat_message, :inbound, content: 'Hello')
      a2a = message.to_a2a_message
      expect(a2a[:role]).to eq('user')
      expect(a2a[:parts]).to be_an(Array)
      expect(a2a[:parts].first[:type]).to eq('text')
    end

    it 'returns assistant role for outbound messages' do
      message = build(:chat_message, :outbound, content: 'Hi there')
      a2a = message.to_a2a_message
      expect(a2a[:role]).to eq('assistant')
    end
  end
end

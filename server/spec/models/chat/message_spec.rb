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

  describe 'callbacks' do
    describe 'before_save' do
      it 'sanitizes content' do
        message = create(:chat_message, content: 'Hello <script>alert("xss")</script>')
        expect(message.sanitized_content).not_to include('<script>')
      end
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
end

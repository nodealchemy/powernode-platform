# frozen_string_literal: true

FactoryBot.define do
  factory :chat_message, class: 'Chat::Message' do
    association :session, factory: :chat_session
    direction { 'inbound' }
    message_type { 'text' }
    content { Faker::Lorem.sentence }
    sanitized_content { content }
    delivery_status { 'delivered' }
    sequence(:platform_message_id) { |n| "msg_#{n}_#{SecureRandom.hex(8)}" }
    platform_metadata { {} }

    trait :inbound do
      direction { 'inbound' }
    end

    trait :outbound do
      direction { 'outbound' }
    end

    trait :text do
      message_type { 'text' }
      content { Faker::Lorem.paragraph }
    end

    trait :image do
      message_type { 'image' }
      content { 'Image attachment' }
      platform_metadata do
        {
          'mime_type' => 'image/jpeg',
          'file_size' => 102_400
        }
      end
    end

    trait :audio do
      message_type { 'audio' }
      content { 'Voice message' }
      platform_metadata do
        {
          'mime_type' => 'audio/ogg',
          'duration' => 15
        }
      end
    end

    trait :video do
      message_type { 'video' }
      content { 'Video attachment' }
      platform_metadata do
        {
          'mime_type' => 'video/mp4',
          'duration' => 30
        }
      end
    end

    trait :document do
      message_type { 'document' }
      content { 'Document attachment' }
      platform_metadata do
        {
          'mime_type' => 'application/pdf',
          'file_name' => 'document.pdf'
        }
      end
    end

    trait :location do
      message_type { 'location' }
      content { 'Location shared' }
      platform_metadata do
        {
          'latitude' => 37.7749,
          'longitude' => -122.4194
        }
      end
    end

    trait :pending do
      delivery_status { 'pending' }
    end

    trait :sent do
      delivery_status { 'sent' }
    end

    trait :delivered do
      delivery_status { 'delivered' }
    end

    trait :read do
      delivery_status { 'read' }
    end

    trait :failed do
      delivery_status { 'failed' }
      platform_metadata do
        {
          'error' => 'Delivery failed',
          'error_code' => 'MSG_FAILED'
        }
      end
    end

    trait :with_attachment do
      after(:create) do |message|
        create(:chat_message_attachment, message: message)
      end
    end
  end
end

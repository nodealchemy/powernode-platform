# frozen_string_literal: true

FactoryBot.define do
  factory :chat_message_attachment, class: 'Chat::MessageAttachment' do
    association :message, factory: :chat_message
    attachment_type { 'image' }
    sequence(:platform_file_id) { |n| "file_#{n}_#{SecureRandom.hex(8)}" }
    mime_type { 'image/jpeg' }
    file_size { 102_400 }
    file_name { 'image.jpg' }
    storage_path { "chat/attachments/#{SecureRandom.uuid}/image.jpg" }
    malware_scanned { false }
    malware_detected { false }
    metadata { {} }

    trait :image do
      attachment_type { 'image' }
      mime_type { 'image/jpeg' }
      file_name { 'photo.jpg' }
    end

    trait :audio do
      attachment_type { 'audio' }
      mime_type { 'audio/ogg' }
      file_name { 'voice.ogg' }
      metadata do
        {
          'duration' => 15,
          'transcription' => nil
        }
      end
    end

    trait :video do
      attachment_type { 'video' }
      mime_type { 'video/mp4' }
      file_name { 'video.mp4' }
      metadata do
        {
          'duration' => 30,
          'width' => 1920,
          'height' => 1080
        }
      end
    end

    trait :document do
      attachment_type { 'document' }
      mime_type { 'application/pdf' }
      file_name { 'document.pdf' }
    end

    trait :scanned do
      malware_scanned { true }
      malware_detected { false }
    end

    trait :malware_detected do
      malware_scanned { true }
      malware_detected { true }
      metadata do
        {
          'threat_name' => 'Test.Threat.Detected',
          'scan_date' => Time.current.iso8601
        }
      end
    end

    trait :transcribed do
      attachment_type { 'audio' }
      metadata do
        {
          'duration' => 15,
          'transcription' => 'This is the transcribed text from the voice message.'
        }
      end
    end
  end
end

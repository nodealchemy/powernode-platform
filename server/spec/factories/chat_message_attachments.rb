# frozen_string_literal: true

FactoryBot.define do
  factory :chat_message_attachment, class: 'Chat::MessageAttachment' do
    association :message, factory: :chat_message
    attachment_type { 'image' }
    sequence(:platform_file_id) { |n| "file_#{n}_#{SecureRandom.hex(8)}" }
    mime_type { 'image/jpeg' }
    file_size { 102_400 }
    filename { 'image.jpg' }
    storage_url { "https://storage.example.com/chat/attachments/#{SecureRandom.uuid}/image.jpg" }
    scanned_for_malware { false }
    malware_detected { false }
    metadata { {} }

    trait :image do
      attachment_type { 'image' }
      mime_type { 'image/jpeg' }
      filename { 'photo.jpg' }
    end

    trait :audio do
      attachment_type { 'audio' }
      mime_type { 'audio/ogg' }
      filename { 'voice.ogg' }
      metadata { { 'duration' => 15 } }
    end

    trait :video do
      attachment_type { 'video' }
      mime_type { 'video/mp4' }
      filename { 'video.mp4' }
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
      filename { 'document.pdf' }
    end

    # Links a real FileManagement::Object so the scan pipeline can resolve bytes.
    trait :with_file_object do
      association :file_object, factory: :file_object
    end

    trait :scanned do
      scanned_for_malware { true }
      malware_detected { false }
      scanned_at { Time.current }
    end

    trait :malware_detected do
      scanned_for_malware { true }
      malware_detected { true }
      scanned_at { Time.current }
      metadata { { 'threat' => 'Test.Threat.Detected' } }
    end

    trait :transcribed do
      attachment_type { 'audio' }
      mime_type { 'audio/ogg' }
      filename { 'voice.ogg' }
      transcription { 'This is the transcribed text from the voice message.' }
    end
  end
end

# frozen_string_literal: true

FactoryBot.define do
  factory :file_object do
    account
    file_storage
    association :uploaded_by, factory: :user

    filename { "test_file_#{SecureRandom.hex(4)}.pdf" }
    storage_key { "uploads/#{Date.current.strftime('%Y%m%d')}/#{SecureRandom.hex(16)}_#{filename}" }
    content_type { 'application/pdf' }
    file_size { rand(1024..10.megabytes) }
    checksum_md5 { Digest::MD5.hexdigest(SecureRandom.random_bytes(1024)) }
    checksum_sha256 { Digest::SHA256.hexdigest(SecureRandom.random_bytes(1024)) }

    file_type { 'document' }
    category { 'user_upload' }
    visibility { 'private' }
    version { 1 }
    is_latest_version { true }

    processing_status { 'completed' }

    metadata { {} }

    trait :image do
      filename { "image_#{SecureRandom.hex(4)}.png" }
      content_type { 'image/png' }
      file_type { 'image' }
      dimensions { { 'width' => 1920, 'height' => 1080 } }
      exif_data { { 'camera' => 'Test Camera', 'date_taken' => Time.current.to_s } }
    end

    trait :video do
      filename { "video_#{SecureRandom.hex(4)}.mp4" }
      content_type { 'video/mp4' }
      file_type { 'video' }
      file_size { 50.megabytes }
      dimensions { { 'width' => 1920, 'height' => 1080, 'duration' => 120 } }
    end

    trait :audio do
      filename { "audio_#{SecureRandom.hex(4)}.mp3" }
      content_type { 'audio/mpeg' }
      file_type { 'audio' }
      dimensions { { 'duration' => 180 } }
    end

    trait :public do
      visibility { 'public' }
    end

    trait :shared do
      visibility { 'shared' }
    end

    trait :workflow_output do
      category { 'workflow_output' }
    end

    trait :ai_generated do
      category { 'ai_generated' }
    end

    trait :temp do
      category { 'temp' }
      expires_at { 24.hours.from_now }
    end

    trait :with_versions do
      after(:create) do |file_object|
        create_list(:file_version, 3, file_object: file_object, account: file_object.account)
      end
    end

    trait :deleted do
      deleted_at { Time.current }
      association :deleted_by, factory: :user
    end

    trait :processing do
      processing_status { 'processing' }
    end

    trait :failed do
      processing_status { 'failed' }
      processing_metadata { { 'error' => 'Test processing error' } }
    end
  end
end

# frozen_string_literal: true

FactoryBot.define do
  factory :file_version do
    file_object
    account
    association :created_by, factory: :user

    sequence(:version_number) { |n| n }
    storage_key { "versions/#{SecureRandom.hex(16)}_v#{version_number}" }
    file_size { rand(1024..5.megabytes) }
    checksum_sha256 { Digest::SHA256.hexdigest(SecureRandom.random_bytes(1024)) }

    change_description { "Version #{version_number} changes" }
    change_metadata { { 'reason' => 'update', 'changes' => [ 'content' ] } }
    metadata { {} }
  end
end

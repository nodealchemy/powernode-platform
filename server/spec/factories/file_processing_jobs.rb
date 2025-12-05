# frozen_string_literal: true

FactoryBot.define do
  factory :file_processing_job do
    file_object
    account

    job_type { 'thumbnail' }
    status { 'pending' }
    priority { 50 }
    retry_count { 0 }
    max_retries { 3 }

    job_parameters { {} }
    result_data { {} }
    error_details { {} }
    metadata { {} }

    trait :thumbnail do
      job_type { 'thumbnail' }
      job_parameters do
        {
          'width' => 200,
          'height' => 200,
          'quality' => 85
        }
      end
    end

    trait :resize do
      job_type { 'resize' }
      job_parameters do
        {
          'width' => 1024,
          'height' => 768
        }
      end
    end

    trait :processing do
      status { 'processing' }
      started_at { Time.current }
    end

    trait :completed do
      status { 'completed' }
      started_at { 5.minutes.ago }
      completed_at { Time.current }
      duration_ms { 300 }
      result_data do
        {
          'success' => true,
          'output_key' => "processed/#{SecureRandom.uuid}/output.jpg"
        }
      end
    end

    trait :failed do
      status { 'failed' }
      started_at { 5.minutes.ago }
      completed_at { Time.current }
      error_details do
        {
          'error' => 'Processing failed',
          'message' => 'File format not supported'
        }
      end
    end
  end
end

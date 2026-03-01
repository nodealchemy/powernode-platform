# frozen_string_literal: true

FactoryBot.define do
  factory :worker_activity do
    association :worker
    activity_type { "authentication" }
    occurred_at { Time.current }
    details do
      {
        "status" => "success",
        "ip_address" => "127.0.0.1",
        "user_agent" => "Worker/1.0"
      }
    end

    trait :authentication do
      activity_type { "authentication" }
    end

    trait :job_enqueue do
      activity_type { "job_enqueue" }
      details do
        {
          "status" => "success",
          "job_class" => "TestJob",
          "job_id" => SecureRandom.uuid,
          "queue" => "default"
        }
      end
    end

    trait :api_request do
      activity_type { "api_request" }
      details do
        {
          "status" => "success",
          "request_path" => "/api/v1/test",
          "response_status" => 200,
          "duration" => 150
        }
      end
    end

    trait :health_check do
      activity_type { "health_check" }
      details do
        {
          "status" => "success",
          "checks" => { "database" => "ok", "redis" => "ok" }
        }
      end
    end

    trait :error_occurred do
      activity_type { "error_occurred" }
      details do
        {
          "status" => "error",
          "error_message" => "Connection timeout",
          "error_class" => "ConnectionError"
        }
      end
    end

    trait :service_created do
      activity_type { "service_created" }
    end

    trait :service_updated do
      activity_type { "service_updated" }
    end

    trait :service_deleted do
      activity_type { "service_deleted" }
    end

    trait :token_regenerated do
      activity_type { "token_regenerated" }
    end

    trait :successful do
      details { { "status" => "success" } }
    end

    trait :failed do
      details do
        {
          "status" => "error",
          "error_message" => "Operation failed"
        }
      end
    end

    trait :recent do
      occurred_at { 1.hour.ago }
    end

    trait :old do
      occurred_at { 7.days.ago }
    end
  end
end

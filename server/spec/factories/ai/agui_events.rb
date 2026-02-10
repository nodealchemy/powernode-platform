# frozen_string_literal: true

FactoryBot.define do
  factory :ai_agui_event, class: "Ai::AguiEvent" do
    association :session, factory: :ai_agui_session
    account { session.account }
    event_type { "TEXT_MESSAGE_CONTENT" }
    sequence(:sequence_number) { |n| n }
    metadata { {} }
    delta { {} }

    trait :text_start do
      event_type { "TEXT_MESSAGE_START" }
      role { "assistant" }
      message_id { "msg_#{SecureRandom.hex(8)}" }
    end

    trait :text_content do
      event_type { "TEXT_MESSAGE_CONTENT" }
      content { "Hello, world!" }
      message_id { "msg_#{SecureRandom.hex(8)}" }
    end

    trait :text_end do
      event_type { "TEXT_MESSAGE_END" }
      message_id { "msg_#{SecureRandom.hex(8)}" }
    end

    trait :tool_call_start do
      event_type { "TOOL_CALL_START" }
      tool_call_id { "tc_#{SecureRandom.hex(8)}" }
    end

    trait :tool_call_args do
      event_type { "TOOL_CALL_ARGS" }
      tool_call_id { "tc_#{SecureRandom.hex(8)}" }
      content { '{"param": "value"}' }
    end

    trait :tool_call_end do
      event_type { "TOOL_CALL_END" }
      tool_call_id { "tc_#{SecureRandom.hex(8)}" }
    end

    trait :tool_call_result do
      event_type { "TOOL_CALL_RESULT" }
      tool_call_id { "tc_#{SecureRandom.hex(8)}" }
      content { "Result data" }
    end

    trait :run_started do
      event_type { "RUN_STARTED" }
      run_id { "run_#{SecureRandom.hex(12)}" }
    end

    trait :run_finished do
      event_type { "RUN_FINISHED" }
      run_id { "run_#{SecureRandom.hex(12)}" }
    end

    trait :run_error do
      event_type { "RUN_ERROR" }
      run_id { "run_#{SecureRandom.hex(12)}" }
      content { "Something went wrong" }
    end

    trait :state_delta do
      event_type { "STATE_DELTA" }
      delta { [{ "op" => "add", "path" => "/key", "value" => "val" }] }
    end

    trait :state_snapshot do
      event_type { "STATE_SNAPSHOT" }
      delta { { "key" => "value" } }
    end

    trait :step_started do
      event_type { "STEP_STARTED" }
      step_id { "step_#{SecureRandom.hex(8)}" }
    end

    trait :step_finished do
      event_type { "STEP_FINISHED" }
      step_id { "step_#{SecureRandom.hex(8)}" }
    end
  end
end
